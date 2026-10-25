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
// The size of the picture in the slot (the top-left rectangle of the 1920x1080 image; the whole image unless the
// engine draws at the render size for MetalFX). NO if there is no such slot.
+ (BOOL)sizeForEye:(NSInteger)eye slot:(NSInteger)slot width:(NSInteger *)width height:(NSInteger *)height;
// Sharp upscaling (MetalFX): `sharpFailed` is set (for the rest of the run) when MetalFX cannot be used, so the
// plain path takes over; `sharpActive` is true while the stereo window shows MetalFX-scaled pictures.
@property(class) BOOL sharpFailed;
@property(class) BOOL sharpActive;
// Turns the per-eye rendering on or off and sets the tuning (also live, from the options screen).
+ (void)applyEnabled:(BOOL)enabled depth:(float)depth convergence:(float)convergence;
// Session-only 2D switch (in-game options): while set, the engine draws the flat window only (no second eye) and
// the stereo screen is hidden. Not saved; a game started in the Stereoscopic window always starts in 3D.
@property(class) BOOL flatOverride;
// This run uses the Stereoscopic window: started in it from the launcher, or 3D was picked mid-game from a flat
// start. Set by main.mm when the stereo start-up begins, cleared if it fails.
@property(class) BOOL sessionStereo;
// In-game options, 3D picked while this run has no stereo yet: asks main.mm to start the Stereoscopic window when
// the options close (the game is paused while they are up). takeStartRequest returns and clears the request.
+ (void)requestStereoStart;
+ (BOOL)takeStartRequest;
// Applies the saved depth / convergence settings; on only if the bridge is ready.
+ (void)applySavedSettings;
@end
NS_ASSUME_NONNULL_END
