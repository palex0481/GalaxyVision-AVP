// SPDX-License-Identifier: GPL-3.0-or-later
#import "GalaxyVisionSettings.h"
#include <stdio.h>
#include <stdlib.h>

NSString *const GVKeyViewMode = @"gv.viewMode";
NSString *const GVKeyPointerSensitivity = @"gv.pointerSensitivity";
NSString *const GVKeyPointerMode = @"gv.pointerMode";
NSString *const GVKeyGyroAim = @"gv.gyroAim";
NSString *const GVKeyGyroInvertX = @"gv.gyroInvertX";
NSString *const GVKeyGyroInvertY = @"gv.gyroInvertY";
NSString *const GVKeyBButtonJumps = @"gv.bButtonJumps";
NSString *const GVKeyRenderScale = @"gv.renderScale";
NSString *const GVKeyAspect = @"gv.aspect";
NSString *const GVKeySmoothMotion = @"gv.smoothMotion";

static NSUserDefaults *Defaults(void) { return NSUserDefaults.standardUserDefaults; }

@implementation GalaxyVisionSettings
+ (void)registerDefaults {
  [Defaults() registerDefaults:@{
    GVKeyViewMode: @"flat",
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
+ (double)renderScale { return [Defaults() doubleForKey:GVKeyRenderScale]; }
+ (NSInteger)aspect { return [Defaults() integerForKey:GVKeyAspect]; }
+ (BOOL)smoothMotion { return [Defaults() boolForKey:GVKeySmoothMotion]; }

+ (void)applyStartupEnvironment {
  // The shell keeps the phone touch controls off (TARGET_OS_IPHONE is true on visionOS).
  setenv("PETARI_TOUCH_CONTROLS", "0", 1);
  // Supersampling: the engine renders at N x the game's framebuffer when PETARI_RENDER_SCALE
  // is set (VISetFrameBufferScale). Unset keeps the engine's own choice (screen pixels).
  const double scale = self.renderScale;
  if (scale >= 1.0 && scale <= 8.0) {
    char text[32];
    snprintf(text, sizeof text, "%.2f", scale);
    setenv("PETARI_RENDER_SCALE", text, 1);
  } else {
    unsetenv("PETARI_RENDER_SCALE");
  }
}
@end
