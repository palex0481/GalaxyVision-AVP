// SPDX-License-Identifier: GPL-3.0-or-later
#import "GalaxyVisionStereoEngine.h"
#import "GalaxyVisionSettings.h"

extern "C" {
int galaxypad_engine_started(void);
void galaxypad_engine_stereo_configure(int enabled, float depth, float convergence);
void galaxypad_engine_stereo_open(int open);
void galaxypad_engine_stereo_set_resolution(int height);
void galaxypad_engine_stereo_set_rect(int lines);
int galaxypad_engine_stereo_slot_size(int eye, int slot, int *width, int *height);
int galaxypad_engine_stereo_status(void);
const char *galaxypad_engine_stereo_error(void);
void *galaxypad_engine_stereo_surface(int eye, int slot);
int galaxypad_engine_stereo_latest(int eye, uint64_t *sequence);
}

static BOOL sSharpFailed;
static BOOL sFlatOverride;
static BOOL sSharpActive;
static BOOL sSessionStereo;
static BOOL sStartRequested;

@implementation GVStereoEngine
+ (BOOL)flatOverride { return sFlatOverride; }
+ (void)setFlatOverride:(BOOL)value { sFlatOverride = value; }
+ (BOOL)sessionStereo { return sSessionStereo; }
+ (void)setSessionStereo:(BOOL)value { sSessionStereo = value; }
+ (void)requestStereoStart { sStartRequested = YES; }
+ (BOOL)takeStartRequest {
  const BOOL requested = sStartRequested;
  sStartRequested = NO;
  return requested;
}
+ (BOOL)sharpFailed { return sSharpFailed; }
+ (void)setSharpFailed:(BOOL)value { sSharpFailed = value; }
+ (BOOL)sharpActive { return sSharpActive; }
+ (void)setSharpActive:(BOOL)value { sSharpActive = value; }
+ (BOOL)sizeForEye:(NSInteger)eye slot:(NSInteger)slot width:(NSInteger *)width height:(NSInteger *)height {
  int w = 0, h = 0;
  if (!galaxypad_engine_stereo_slot_size((int)eye, (int)slot, &w, &h)) return NO;
  if (width) *width = w;
  if (height) *height = h;
  return YES;
}
+ (void)setBridgeOpen:(BOOL)open { galaxypad_engine_stereo_open(open ? 1 : 0); }
+ (NSInteger)status { return galaxypad_engine_stereo_status(); }
+ (NSString *)error { return [NSString stringWithUTF8String:galaxypad_engine_stereo_error()] ?: @""; }
+ (BOOL)engineStarted { return galaxypad_engine_started() != 0; }
+ (IOSurfaceRef)surfaceForEye:(NSInteger)eye slot:(NSInteger)slot {
  return (IOSurfaceRef)galaxypad_engine_stereo_surface((int)eye, (int)slot);
}
+ (NSInteger)latestSlotForEye:(NSInteger)eye sequence:(uint64_t *)sequence {
  return galaxypad_engine_stereo_latest((int)eye, sequence);
}
+ (void)applyEnabled:(BOOL)enabled depth:(float)depth convergence:(float)convergence {
  galaxypad_engine_stereo_configure(enabled ? 1 : 0, depth, convergence);
}
+ (void)applySavedSettings {
  const NSInteger height = GalaxyVisionSettings.stereoResolution;
  galaxypad_engine_stereo_set_resolution((int)height);
  // MetalFX: the engine draws at the render size (top-left rectangle) only below High and while MetalFX works;
  // otherwise it scales the picture across the whole eye image itself (the plain path).
  const BOOL sharp = GalaxyVisionSettings.stereoSharp && !sSharpFailed && height < 1080;
  galaxypad_engine_stereo_set_rect(sharp ? (int)height : 0);
  [self applyEnabled:(self.status == 1 && sSessionStereo && !sFlatOverride)
               depth:GalaxyVisionSettings.stereoDepth
         convergence:GalaxyVisionSettings.stereoConvergence];
}
@end
