// SPDX-License-Identifier: GPL-3.0-or-later
#import "GalaxyVisionSettings.h"
#include <stdio.h>
#include <stdlib.h>

NSString *const GVKeyViewMode = @"gv.viewMode";
NSString *const GVKeyStereoDepth = @"gv.stereoDepth";
NSString *const GVKeyStereoConvergence = @"gv.stereoConvergence";
NSString *const GVKeyPointerSensitivity = @"gv.pointerSensitivity";
NSString *const GVKeyPointerMode = @"gv.pointerMode";
NSString *const GVKeyGyroAim = @"gv.gyroAim";
NSString *const GVKeyGyroInvertX = @"gv.gyroInvertX";
NSString *const GVKeyGyroInvertY = @"gv.gyroInvertY";
NSString *const GVKeyBButtonJumps = @"gv.bButtonJumps";
NSString *const GVKeyRenderScale = @"gv.supersampling";
NSString *const GVKeyAspect = @"gv.aspect";
NSString *const GVKeySmoothMotion = @"gv.smoothMotion";

static NSUserDefaults *Defaults(void) { return NSUserDefaults.standardUserDefaults; }

@implementation GalaxyVisionSettings
+ (void)registerDefaults {
  [Defaults() registerDefaults:@{
    GVKeyViewMode: @"flat",
    GVKeyStereoDepth: @1.0,
    GVKeyStereoConvergence: @1200.0,
    GVKeyPointerSensitivity: @1.0,
    GVKeyPointerMode: @0,
    GVKeyGyroAim: @NO,
    GVKeyGyroInvertX: @NO,
    GVKeyGyroInvertY: @NO,
    GVKeyBButtonJumps: @YES,
    GVKeyRenderScale: @0.0,
    GVKeyAspect: @-1,
    GVKeySmoothMotion: @NO,
  }];
}
+ (float)pointerSensitivity {
  float v = (float)[Defaults() doubleForKey:GVKeyPointerSensitivity];
  return (v >= 0.25f && v <= 4.0f) ? v : 1.0f;
}
+ (NSInteger)pointerMode { return [Defaults() integerForKey:GVKeyPointerMode]; }
+ (BOOL)gyroAim { return [Defaults() boolForKey:GVKeyGyroAim]; }
+ (BOOL)gyroInvertX { return [Defaults() boolForKey:GVKeyGyroInvertX]; }
+ (BOOL)gyroInvertY { return [Defaults() boolForKey:GVKeyGyroInvertY]; }
+ (BOOL)bButtonJumps { return [Defaults() boolForKey:GVKeyBButtonJumps]; }
// Only 2x and 3x of the game's framebuffer (640x456; both at or below the 2560x1440 headset window) are
// offered. Anything above (the old 4x option) exceeds the window's drawable and broke the aspect ratio,
// so it is never honoured: it means native.
+ (double)renderScale {
  const double v = [Defaults() doubleForKey:GVKeyRenderScale];
  return (v >= 1.0 && v <= 3.0) ? v : 0.0;
}
+ (NSInteger)aspect { return [Defaults() integerForKey:GVKeyAspect]; }
+ (BOOL)smoothMotion { return [Defaults() boolForKey:GVKeySmoothMotion]; }
+ (BOOL)stereoSelected { return [[Defaults() stringForKey:GVKeyViewMode] isEqualToString:@"stereo"]; }
+ (float)stereoDepth {
  const double v = [Defaults() doubleForKey:GVKeyStereoDepth];
  return (v >= 0.0 && v <= 2.0) ? (float)v : 1.0f;
}
+ (float)stereoConvergence {
  const double v = [Defaults() doubleForKey:GVKeyStereoConvergence];
  return (v >= 400.0 && v <= 3000.0) ? (float)v : 1200.0f;
}

// Library/Caches/galaxyvision-trace.log in the app container: the engine's stderr (size trace, stereo bridge log).
static void RedirectTraceLog(void) {
  static BOOL done;
  if (done) return;
  done = YES;
  setenv("PETARI_TRACE_BOOT", "1", 1);
  NSURL *caches = [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
  NSString *log = [caches URLByAppendingPathComponent:@"galaxyvision-trace.log"].path;
  freopen(log.fileSystemRepresentation, "w", stderr);
  setvbuf(stderr, NULL, _IOLBF, 0);
}

+ (void)applyStartupEnvironment {
  // The shell keeps the phone touch controls off (TARGET_OS_IPHONE is true on visionOS).
  setenv("PETARI_TOUCH_CONTROLS", "0", 1);
  // Supersampling: the engine renders at N x the game's framebuffer when PETARI_RENDER_SCALE
  // is set (VISetFrameBufferScale). Unset keeps the engine's own choice (screen pixels).
  const double scale = self.renderScale;
  if (scale >= 1.0 && scale <= 3.0) {
    char text[32];
    snprintf(text, sizeof text, "%.2f", scale);
    setenv("PETARI_RENDER_SCALE", text, 1);
    // Diagnostics for a non-default scale: the engine's size trace (surface / EFB / XFB / viewport).
    RedirectTraceLog();
  } else {
    unsetenv("PETARI_RENDER_SCALE");
  }
  if (self.stereoSelected) {
    // Stereoscopic window (beta): the stereo bridge reports to the same trace log. The engine picks the
    // render scale (3x, 1920x1080 for 16:9) when stereo starts; the launcher does not set one for it.
    RedirectTraceLog();
    setenv("PETARI_STEREO_TRACE", "1", 1);
    unsetenv("PETARI_RENDER_SCALE");
  }
}
@end
