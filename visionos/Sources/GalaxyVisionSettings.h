// SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// Shared GalaxyVision settings, stored in NSUserDefaults. The SwiftUI launcher edits them
// (via @AppStorage with these keys) and the controller / engine start-up read them.
NS_ASSUME_NONNULL_BEGIN

extern NSString *const GVKeyViewMode;           // String: "flat" (default), "stereo" (Stereoscopic window, beta) or "immersive" (Immersive space, beta)
extern NSString *const GVKeyImmersiveDepth;     // Bool: Immersive space "Screen depth (3D)": the screen shows stereo depth (default off = flat)
extern NSString *const GVKeyImmersiveSize;      // Double 2...14: Immersive space screen width in metres (default 6)
extern NSString *const GVKeyImmersiveDistance;  // Double 2...8: Immersive space screen distance in metres (default 3.5)
extern NSString *const GVKeyStereoDepth;        // Double 0...2: eye separation scale (1 = default, 0 = no depth)
extern NSString *const GVKeyStereoResolution;   // Int 540 / 720 / 1080: the stereo window's render height per eye (default 720)
extern NSString *const GVKeyStereoSharp;        // Bool: sharp upscaling (MetalFX) of the stereo eye images at Low / Medium (default on)
extern NSString *const GVKeyStereoConvergence;  // Double 400...3000: game units to the zero-parallax plane (default 1200)
extern NSString *const GVKeyShowFPS;            // Bool: small frame-rate counter in the game window's top-right corner (testing, default on)
extern NSString *const GVKeyAmbientGlow;        // Bool: soft glow of the picture's edge colours around the flat window (default off)
extern NSString *const GVKeyGlowStrength;       // Double 0.1...1: glow brightness (default 0.7)
extern NSString *const GVKeyGlowSize;           // Double 0...1: how far the glow reaches, 3% to 12% of the window per side (default 0.5)
extern NSString *const GVKeyPointerSensitivity; // Double 0.5...2.0, scales pointer speed (default 1.0)
extern NSString *const GVKeyPointerMode;        // Int: 0 when moved, 1 always, 2 hidden
extern NSString *const GVKeyGyroAim;            // Bool, PS pads with motion only (default off)
extern NSString *const GVKeyGyroInvertX;        // Bool
extern NSString *const GVKeyGyroInvertY;        // Bool
extern NSString *const GVKeyBButtonJumps;       // Bool: Circle / N64 B jump (Switch style) instead of Wii B
extern NSString *const GVKeyRenderScale;        // Double: 0 = Off / native (engine default), else PETARI_RENDER_SCALE 2 or 3 (at or below native)
extern NSString *const GVKeyAspect;             // Int: -1 leave engine setting, 0 = 4:3, 1 = 16:9
extern NSString *const GVKeySmoothMotion;       // Bool (only has an effect on >=110 Hz displays)

@interface GalaxyVisionSettings : NSObject
+ (void)registerDefaults;
@property(class, readonly) BOOL showFPS;
@property(class, readonly) BOOL ambientGlow;
@property(class, readonly) float glowStrength;
@property(class, readonly) float glowSize;
@property(class, readonly) float pointerSensitivity;
@property(class, readonly) NSInteger pointerMode;
@property(class, readonly) BOOL gyroAim;
@property(class, readonly) BOOL gyroInvertX;
@property(class, readonly) BOOL gyroInvertY;
@property(class, readonly) BOOL bButtonJumps;
@property(class, readonly) double renderScale;
@property(class, readonly) NSInteger aspect;
@property(class, readonly) BOOL smoothMotion;
@property(class, readonly) BOOL stereoSelected;      // view mode is the Stereoscopic window (beta)
@property(class, readonly) BOOL immersiveSelected;   // view mode is the Immersive space (beta)
@property(class, readonly) BOOL bridgeSelected;      // stereo window or immersive space: the engine's eye bridge is used
@property(class, readonly) BOOL immersiveDepth;
@property(class, readonly) float stereoDepth;
@property(class, readonly) float stereoConvergence;
@property(class, readonly) BOOL stereoSharp;
@property(class, readonly) NSInteger stereoResolution;  // eye render height: 540 Low, 720 Medium (default), 1080 High
// Exports settings that must exist before the engine starts (PETARI_RENDER_SCALE).
+ (void)applyStartupEnvironment;
@end

NS_ASSUME_NONNULL_END
