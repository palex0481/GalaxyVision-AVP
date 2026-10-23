// SPDX-License-Identifier: GPL-3.0-or-later
#import "GalaxyVisionStereoEngine.h"
#import "GalaxyVisionSettings.h"

extern "C" {
int galaxypad_engine_started(void);
void galaxypad_engine_stereo_configure(int enabled, float depth, float convergence);
void galaxypad_engine_stereo_open(int open);
int galaxypad_engine_stereo_status(void);
const char *galaxypad_engine_stereo_error(void);
void *galaxypad_engine_stereo_surface(int eye, int slot);
int galaxypad_engine_stereo_latest(int eye, uint64_t *sequence);
}

@implementation GVStereoEngine
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
  [self applyEnabled:(self.status == 1 && GalaxyVisionSettings.stereoSelected)
               depth:GalaxyVisionSettings.stereoDepth
         convergence:GalaxyVisionSettings.stereoConvergence];
}
@end
