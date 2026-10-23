// SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// Shared GalaxyVision settings, stored in NSUserDefaults. The SwiftUI launcher edits them
// (via @AppStorage with these keys) and the controller / engine start-up read them.
NS_ASSUME_NONNULL_BEGIN

extern NSString *const GVKeyViewMode;           // String: "flat" (others are not implemented yet)
extern NSString *const GVKeyPointerSensitivity; // Double 0.5...2.0, scales pointer speed (default 1.0)
extern NSString *const GVKeyPointerMode;        // Int: 0 when moved, 1 always, 2 hidden
extern NSString *const GVKeyGyroAim;            // Bool, PS pads with motion only (default off)
extern NSString *const GVKeyGyroInvertX;        // Bool
extern NSString *const GVKeyGyroInvertY;        // Bool
extern NSString *const GVKeyBButtonJumps;       // Bool: Circle / N64 B jump (Switch style) instead of Wii B
extern NSString *const GVKeyRenderScale;        // Double: 0 = native (engine default), else PETARI_RENDER_SCALE 2 or 3 (below native)
extern NSString *const GVKeyAspect;             // Int: -1 leave engine setting, 0 = 4:3, 1 = 16:9
extern NSString *const GVKeySmoothMotion;       // Bool (only has an effect on >=110 Hz displays)

@interface GalaxyVisionSettings : NSObject
+ (void)registerDefaults;
@property(class, readonly) float pointerSensitivity;
@property(class, readonly) NSInteger pointerMode;
@property(class, readonly) BOOL gyroAim;
@property(class, readonly) BOOL gyroInvertX;
@property(class, readonly) BOOL gyroInvertY;
@property(class, readonly) BOOL bButtonJumps;
@property(class, readonly) double renderScale;
@property(class, readonly) NSInteger aspect;
@property(class, readonly) BOOL smoothMotion;
// Exports settings that must exist before the engine starts (PETARI_RENDER_SCALE).
+ (void)applyStartupEnvironment;
@end

NS_ASSUME_NONNULL_END
