// SPDX-License-Identifier: GPL-3.0-or-later
// game audio tap (see GVAudioTap.h).
//
// The engine framework exports no SDL audio API, so the recorder gets the game's sound by rebinding the framework's
// non-lazy symbol pointers (__got, the same technique as fishhook) for two AudioToolbox calls:
//  - AudioQueueNewOutput: remembers the output queue and its stream format;
//  - AudioQueueEnqueueBuffer: hands each output buffer to the handler, then enqueues it as before.
// Only the GalaxyPadEngine image is touched; the rest of the process calls AudioToolbox directly.
#import "GVAudioTap.h"
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#include <mach/mach.h>
#include <os/lock.h>
#include <string.h>

typedef OSStatus (*NewOutputFn)(const AudioStreamBasicDescription *, AudioQueueOutputCallback, void *, CFRunLoopRef,
                                CFStringRef, UInt32, AudioQueueRef *);
typedef OSStatus (*EnqueueFn)(AudioQueueRef, AudioQueueBufferRef, UInt32, const AudioStreamPacketDescription *);

static NewOutputFn sRealNewOutput = AudioQueueNewOutput;
static EnqueueFn sRealEnqueue = AudioQueueEnqueueBuffer;
static os_unfair_lock sLock = OS_UNFAIR_LOCK_INIT;
static AudioQueueRef sQueue = nullptr;  // the newest output queue
static AudioStreamBasicDescription sFormat;
static GVAudioTapHandler sHandler = nil;
static BOOL sInstalled = NO;

static OSStatus HookNewOutput(const AudioStreamBasicDescription *format, AudioQueueOutputCallback callback, void *user,
                              CFRunLoopRef runLoop, CFStringRef mode, UInt32 flags, AudioQueueRef *outQueue) {
  OSStatus status = sRealNewOutput(format, callback, user, runLoop, mode, flags, outQueue);
  if (status == noErr && outQueue && *outQueue && format) {
    os_unfair_lock_lock(&sLock);
    sQueue = *outQueue;
    sFormat = *format;
    os_unfair_lock_unlock(&sLock);
  }
  return status;
}

static OSStatus HookEnqueue(AudioQueueRef queue, AudioQueueBufferRef buffer, UInt32 packets,
                            const AudioStreamPacketDescription *descriptions) {
  if (buffer && buffer->mAudioDataByteSize > 0) {
    GVAudioTapHandler handler = nil;
    AudioStreamBasicDescription format;
    os_unfair_lock_lock(&sLock);
    if (queue == sQueue && sHandler) {
      handler = sHandler;
      format = sFormat;
    }
    os_unfair_lock_unlock(&sLock);
    if (handler) handler(buffer->mAudioData, buffer->mAudioDataByteSize, &format);
  }
  return sRealEnqueue(queue, buffer, packets, descriptions);
}

#ifdef __LP64__
typedef struct mach_header_64 GVHeader;
typedef struct segment_command_64 GVSegment;
typedef struct section_64 GVSection;
typedef struct nlist_64 GVNlist;
#define GV_SEGMENT LC_SEGMENT_64
#endif

static int RebindImage(const struct mach_header *mh, intptr_t slide) {
  const GVHeader *header = (const GVHeader *)mh;
  const GVSegment *linkedit = nullptr;
  const struct symtab_command *symtab = nullptr;
  const struct dysymtab_command *dysymtab = nullptr;
  uintptr_t cursor = (uintptr_t)header + sizeof(GVHeader);
  for (uint32_t i = 0; i < header->ncmds; i++) {
    const struct load_command *lc = (const struct load_command *)cursor;
    if (lc->cmd == GV_SEGMENT && strcmp(((const GVSegment *)lc)->segname, SEG_LINKEDIT) == 0) linkedit = (const GVSegment *)lc;
    else if (lc->cmd == LC_SYMTAB) symtab = (const struct symtab_command *)lc;
    else if (lc->cmd == LC_DYSYMTAB) dysymtab = (const struct dysymtab_command *)lc;
    cursor += lc->cmdsize;
  }
  if (!linkedit || !symtab || !dysymtab || !dysymtab->nindirectsyms) return 0;
  const uintptr_t base = (uintptr_t)slide + linkedit->vmaddr - linkedit->fileoff;
  const GVNlist *symbols = (const GVNlist *)(base + symtab->symoff);
  const char *strings = (const char *)(base + symtab->stroff);
  const uint32_t *indirect = (const uint32_t *)(base + dysymtab->indirectsymoff);
  int replaced = 0;
  cursor = (uintptr_t)header + sizeof(GVHeader);
  for (uint32_t i = 0; i < header->ncmds; i++) {
    const struct load_command *lc = (const struct load_command *)cursor;
    cursor += lc->cmdsize;
    if (lc->cmd != GV_SEGMENT) continue;
    const GVSegment *segment = (const GVSegment *)lc;
    if (strcmp(segment->segname, SEG_DATA) != 0 && strcmp(segment->segname, "__DATA_CONST") != 0) continue;
    const GVSection *sections = (const GVSection *)(segment + 1);
    for (uint32_t s = 0; s < segment->nsects; s++) {
      const GVSection *section = &sections[s];
      const uint32_t type = section->flags & SECTION_TYPE;
      if (type != S_NON_LAZY_SYMBOL_POINTERS && type != S_LAZY_SYMBOL_POINTERS) continue;
      void **pointers = (void **)((uintptr_t)slide + section->addr);
      const uint32_t *entries = indirect + section->reserved1;
      for (uint64_t k = 0; k < section->size / sizeof(void *); k++) {
        const uint32_t index = entries[k];
        if (index == INDIRECT_SYMBOL_ABS || index == INDIRECT_SYMBOL_LOCAL ||
            index == (INDIRECT_SYMBOL_LOCAL | INDIRECT_SYMBOL_ABS)) continue;
        const char *name = strings + symbols[index].n_un.n_strx;
        void *replacement = nullptr;
        if (strcmp(name, "_AudioQueueNewOutput") == 0) replacement = (void *)HookNewOutput;
        else if (strcmp(name, "_AudioQueueEnqueueBuffer") == 0) replacement = (void *)HookEnqueue;
        if (!replacement) continue;
        // __DATA_CONST is read-only after dyld binds it: make the page writable for the store.
        const vm_size_t page = vm_page_size;
        const vm_address_t start = (vm_address_t)&pointers[k] & ~(page - 1);
        if (vm_protect(mach_task_self(), start, page, false, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY) != KERN_SUCCESS &&
            vm_protect(mach_task_self(), start, page, false, VM_PROT_READ | VM_PROT_WRITE) != KERN_SUCCESS)
          continue;
        pointers[k] = replacement;
        replaced++;
      }
    }
  }
  return replaced;
}

@implementation GVAudioTap
+ (BOOL)installed { return sInstalled; }

+ (BOOL)install {
  if (sInstalled) return YES;
  for (uint32_t i = 0; i < _dyld_image_count(); i++) {
    const char *name = _dyld_get_image_name(i);
    if (!name || !strstr(name, "GalaxyPadEngine.framework/GalaxyPadEngine")) continue;
    const int replaced = RebindImage(_dyld_get_image_header(i), _dyld_get_image_vmaddr_slide(i));
    sInstalled = replaced >= 2;
    fprintf(stderr, "GalaxyVision recorder: audio tap %s (%d imports)\n", sInstalled ? "installed" : "NOT installed", replaced);
    return sInstalled;
  }
  fprintf(stderr, "GalaxyVision recorder: audio tap: engine image not found\n");
  return NO;
}

+ (void)setHandler:(GVAudioTapHandler)handler {
  os_unfair_lock_lock(&sLock);
  sHandler = [handler copy];
  os_unfair_lock_unlock(&sLock);
}
@end
