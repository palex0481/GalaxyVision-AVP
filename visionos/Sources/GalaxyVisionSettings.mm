// SPDX-License-Identifier: GPL-3.0-or-later
#import "GalaxyVisionSettings.h"
#import "GalaxyVisionController.h"
#include <stdio.h>
#include <stdlib.h>

NSString *const GVKeyViewMode = @"gv.viewMode";
NSString *const GVKeyStereoDepth = @"gv.stereoDepth";
NSString *const GVKeyStereoConvergence = @"gv.stereoConvergence";
NSString *const GVKeyStereoSharp = @"gv.stereoSharp";
NSString *const GVKeyStereoResolution = @"gv.stereoResolution";
NSString *const GVKeyShowFPS = @"gv.showFPS";
NSString *const GVKeyPointerSensitivity = @"gv.pointerSensitivity";
NSString *const GVKeyPointerMode = @"gv.pointerMode";
NSString *const GVKeyGyroAim = @"gv.gyroAim";
NSString *const GVKeyGyroInvertX = @"gv.gyroInvertX";
NSString *const GVKeyGyroInvertY = @"gv.gyroInvertY";
NSString *const GVKeyTiltSteer = @"gv.tiltSteer";
NSString *const GVKeyTiltInvert = @"gv.tiltInvert";
NSString *const GVKeyBButtonJumps = @"gv.bButtonJumps";
NSString *const GVKeyAspect = @"gv.aspect";
NSString *const GVKeySmoothMotion = @"gv.smoothMotion";
NSString *const GVKeyMute = @"gv.mute";

static NSUserDefaults *Defaults(void) { return NSUserDefaults.standardUserDefaults; }

@implementation GalaxyVisionSettings
+ (void)registerDefaults {
  [Defaults() registerDefaults:@{
    GVKeyViewMode: @"flat",
    GVKeyStereoDepth: @1.0,
    GVKeyStereoConvergence: @1200.0,
    GVKeyStereoResolution: @720,
    GVKeyStereoSharp: @YES,
    GVKeyShowFPS: @YES,
    GVKeyTiltSteer: @YES,
    GVKeyPointerSensitivity: @1.0,
    GVKeyPointerMode: @0,
    GVKeyGyroAim: @NO,
    GVKeyGyroInvertX: @NO,
    GVKeyGyroInvertY: @NO,
    GVKeyBButtonJumps: @YES,
    GVKeyAspect: @-1,
    GVKeySmoothMotion: @NO,
    GVKeyMute: @NO,
  }];
  // The ambient glow was removed: drop its old saved settings.
  for (NSString *key in @[ @"gv.ambientGlow", @"gv.glowStrength", @"gv.glowSize" ]) [Defaults() removeObjectForKey:key];
  // The Immersive space and 3D portal window modes were removed: a saved choice of either means Flat now.
  NSString *mode = [Defaults() stringForKey:GVKeyViewMode];
  if (![mode isEqualToString:@"flat"] && ![mode isEqualToString:@"stereo"]) [Defaults() setObject:@"flat" forKey:GVKeyViewMode];
}
+ (BOOL)showFPS { return [Defaults() boolForKey:GVKeyShowFPS]; }
+ (float)pointerSensitivity {
  float v = (float)[Defaults() doubleForKey:GVKeyPointerSensitivity];
  return (v >= 0.25f && v <= 4.0f) ? v : 1.0f;
}
+ (NSInteger)pointerMode { return [Defaults() integerForKey:GVKeyPointerMode]; }
+ (BOOL)gyroAim { return [Defaults() boolForKey:GVKeyGyroAim]; }
+ (BOOL)gyroInvertX { return [Defaults() boolForKey:GVKeyGyroInvertX]; }
+ (BOOL)gyroInvertY { return [Defaults() boolForKey:GVKeyGyroInvertY]; }
+ (BOOL)tiltSteer { return [Defaults() boolForKey:GVKeyTiltSteer]; }
+ (BOOL)tiltInvert { return [Defaults() boolForKey:GVKeyTiltInvert]; }
+ (BOOL)bButtonJumps { return [Defaults() boolForKey:GVKeyBButtonJumps]; }
+ (NSInteger)aspect { return [Defaults() integerForKey:GVKeyAspect]; }
+ (BOOL)smoothMotion { return [Defaults() boolForKey:GVKeySmoothMotion]; }
+ (BOOL)muted { return [Defaults() boolForKey:GVKeyMute]; }
// The engine keeps this volume across its own pause (galaxypad_engine_pause restores it on resume),
// so unmuting always brings back full volume.
+ (void)applyAudio { galaxypad_engine_set_volume(self.muted ? 0.0f : 1.0f); }
+ (BOOL)stereoSelected { return [[Defaults() stringForKey:GVKeyViewMode] isEqualToString:@"stereo"]; }
+ (float)stereoDepth {
  const double v = [Defaults() doubleForKey:GVKeyStereoDepth];
  return (v >= 0.0 && v <= 2.0) ? (float)v : 1.0f;
}
+ (NSInteger)stereoResolution {
  const NSInteger v = [Defaults() integerForKey:GVKeyStereoResolution];
  return (v == 540 || v == 720 || v == 900 || v == 1080) ? v : 720;
}
+ (BOOL)stereoSharp { return [Defaults() boolForKey:GVKeyStereoSharp]; }
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
  // Mix with other apps' audio instead of ducking it. SDL's default session is Playback with
  // MixWithOthers + DuckOthers, which turns other apps' video down while the game runs (even muted);
  // its "ambient" category hint is Ambient + MixWithOthers, no ducking. SDL still activates the
  // session and handles interruptions as before.
  setenv("SDL_AUDIO_CATEGORY", "ambient", 1);
  // The flat window always renders at the window's native size (Supersampling removed).
  unsetenv("PETARI_RENDER_SCALE");
  if (self.stereoSelected) {
    // Stereoscopic window (beta): the stereo bridge reports to the same trace log. The engine picks the
    // render scale (3x, 1920x1080 for 16:9) when stereo starts; the launcher does not set one for it.
    RedirectTraceLog();
    setenv("PETARI_STEREO_TRACE", "1", 1);
    unsetenv("PETARI_RENDER_SCALE");
  }
}
@end
