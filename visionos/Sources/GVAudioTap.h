// SPDX-License-Identifier: GPL-3.0-or-later
// game audio tap for the side-by-side 3D recorder.
#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

NS_ASSUME_NONNULL_BEGIN
// Called on the engine's audio thread with a copy-able view of every buffer the game hands to its output
// AudioQueue (SDL3's CoreAudio backend), before the queue plays it.
typedef void (^GVAudioTapHandler)(const void *data, uint32_t bytes, const AudioStreamBasicDescription *format);

@interface GVAudioTap : NSObject
// Redirects the engine framework's AudioQueueNewOutput / AudioQueueEnqueueBuffer imports (once, before the engine
// starts) so output buffers can be copied. Returns NO if the engine image or its imports were not found.
+ (BOOL)install;
@property(class, readonly) BOOL installed;
// nil: no copying (the hook only forwards to AudioToolbox).
+ (void)setHandler:(nullable GVAudioTapHandler)handler;
@end
NS_ASSUME_NONNULL_END
