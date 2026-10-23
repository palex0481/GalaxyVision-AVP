// SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>
#import <IOSurface/IOSurfaceRef.h>

// Swift-visible wrapper for the engine's stereoscopic window bridge (galaxypad_engine_stereo_*).
// The engine draws the left and right eye into a ring of 1920x1080 BGRA IOSurfaces each (Dawn shared
// texture memory); the RealityKit side copies the newest slot into its textures.
NS_ASSUME_NONNULL_BEGIN
@interface GVStereoEngine : NSObject
+ (void)setBridgeOpen:(BOOL)open;
// 0 not open or pending, 1 ready, -1 failed (see +error).
@property(class, readonly) NSInteger status;
@property(class, readonly) NSString *error;
@property(class, readonly) BOOL engineStarted;
// eye 0 left, 1 right; slot 0...3. The engine keeps ownership.
+ (nullable IOSurfaceRef)surfaceForEye:(NSInteger)eye slot:(NSInteger)slot CF_RETURNS_NOT_RETAINED;
// The newest finished slot of the eye (-1 if none); `sequence` increments with every finished frame.
+ (NSInteger)latestSlotForEye:(NSInteger)eye sequence:(uint64_t *)sequence;
// Turns the per-eye rendering on or off and sets the tuning (also live, from the options screen).
+ (void)applyEnabled:(BOOL)enabled depth:(float)depth convergence:(float)convergence;
// Applies the saved depth / convergence settings; on only if the bridge is ready.
+ (void)applySavedSettings;
@end
NS_ASSUME_NONNULL_END
