# GalaxyPad visionOS port notes (branch `visionos-port`)

Status (2026-10-23): engine framework builds for visionOS device (arm64, xros 2.0+, SDK 27.0);
minimal app `visionos/GalaxyVision` compiles and links with the generic visionOS destination
(CODE_SIGNING_ALLOWED=NO). NOT yet run on a headset. Nothing pushed.

## Build
1. Engine: `DEVELOPER_DIR=<Xcode>/Contents/Developer scripts/build-visionos-engine.sh`
   -> `generated/build/visionos-device-engine/native/app/GalaxyPadEngine.framework` (~2.5 GB build dir, 1st build ~hours of CPU).
   Dawn is built from source (no visionOS prebuilt), via the same "vendor" path as the iOS Simulator.
2. App: `cd visionos && xcodegen generate && xcodebuild -project GalaxyVision.xcodeproj -scheme GalaxyVision -configuration Debug -destination 'generic/platform=visionOS' -derivedDataPath .build/dd CODE_SIGNING_ALLOWED=NO build`

## Engine changes (ref/galaxypad-engine, local branch visionos-port, not pushed)
- CMake `CMAKE_SYSTEM_NAME STREQUAL "iOS"` checks also accept `visionOS` (4 places incl. verify_downloads.cmake).
- Dawn from source for visionOS (AURORA_DAWN_PROVIDER=vendor).
- CoreAudio link skipped on visionOS (as on iOS).
- Aurora's `if (IOS)` block (CoreHaptics device rumble, lib/device_ios.mm) does not fire on visionOS; native/gx/CMakeLists.txt adds it for visionOS. Without it: undefined `aurora::device::detail::shutdown_rumble()` at link.
- `scripts/visionos-device-toolchain.cmake` (xros sysroot, arm64) and `scripts/build-visionos-engine.sh`.

## App (visionos/)
- XcodeGen `project.yml`; bundle id `com.example.galaxyvision`, team copied from SM64-Vision's Config/Signing.xcconfig.
- `main.mm`: if `Application Support/GalaxyPad/GameData/RMGE01/sys/main.dol` exists, calls `galaxypad_engine_main` with `--disc/--user` (the engine's SDL3 window is the flat screen; scene handoff mirrors apple/ios/main.mm). Otherwise a placeholder UIKit screen with an unimplemented "Import" button.
- `GalaxyVisionController`: polls GCExtendedGamepad at 60 Hz -> `galaxypad_engine_input`.

## Known gaps / risks
- Not run anywhere yet: SDL3 window behaviour on visionOS, memory limit, performance, first-launch shader/pipeline precompile.
- Engine framework Info.plist lacks CFBundleSupportedPlatforms/MinimumOSVersion; device signing/validation may complain.
- Framework contains a `Licenses/` dir; codesign may object to it.
- Game data import not implemented; data must be placed in the app container by hand. Disc extraction (iOS GalaxyPadDiscExtractor) not ported.
- Touch/gyro/haptics UI, engine pause/widescreen/smooth-motion controls not wired.
- `ref/ModernGekko` shows as deleted in the superproject worktree (not used by the visionOS build); left untouched/uncommitted.

## Controls and launcher (visionos-port)

- `visionos/Sources/GalaxyVisionSettings.*`: UserDefaults-backed settings (`gv.*` keys) shared by the launcher
  (`@AppStorage`) and the controller / engine start-up.
- `GalaxyVisionController.mm`: Switch-style mapping. Engine bits: A=North (A everywhere), B=East (Wii B: shoot
  Star Bits / menu Back), C=Nunchuk C, Z=Nunchuk Z, Spin=Wii shake. Hovering the pointer collects Star Bits by
  itself; B shoots them; holding A on the pointer grabs Pull Stars.
  - PS / Xbox: left stick move, Cross A, Circle A (setting; else B), Square/Triangle spin, R2 B, L2 Z, L1 C,
    right stick pointer (1.2 x dt/s x sensitivity, 0.15 dead zone), L3/R3 recenter, Options Plus (pause only),
    Create/Share Minus. R1/RB opens the options overlay (edge-triggered press, as SM64-Vision's R button; never sent to the game). Optional gyro aim (default off, axes unverified).
  - N64 (Switch Online): A/B jump, Z crouch, L camera, R spin, C buttons nudge the pointer (hold accelerates),
    C-down shoots (while Capture is held it nudges down instead), Capture recenters, Start pauses, Start + Capture held 0.5 s opens the overlay (R is spin).
- `GalaxyVisionLauncher.swift`: SwiftUI launcher (Play / View / Controls / Graphics). It lives in the scene
  delegate; Play hides it and hands the scene to the engine's SDL scene delegate (no second UIApplicationMain).
- Graphics: no MSAA row (not usable in this engine). Supersampling picker: "Off (native, default)" (engine default = 2560x1440
  window pixels), "3x" (PETARI_RENDER_SCALE=3, EFB ~2432x1368) and "2x" (~1625x1216). All options are at or below native: a framebuffer
  larger than the drawable (the old 4x) showed the picture at ~80% size, anchored top-left, so nothing above native is offered. The
  stored key is `gv.supersampling` (renamed to reset stale values to Off). With a non-default scale the shell writes PETARI_TRACE_BOOT
  output to `Library/Caches/galaxyvision-trace.log`.
- In game there is NO on-screen button or hint toast. The options overlay opens only while the game's own pause menu is up
  (`galaxypad_engine_game_paused()`, an engine export built from the PauseMenu.Open/Close milestones): R1/RB on PS/Xbox pads, Start +
  Capture held 0.5 s on the N64 pad. The overlay's Saving tab has "Quit GalaxyVision..." (confirmation dialog, calls
  galaxypad_engine_quit, no save).
- The overlay and the save toast are SUBVIEWS of the SDL game window (child VC on its rootViewController), never extra UIWindows:
  visionOS gives every extra UIWindow a glass material, and a full-scene window (the old Options pill, 20ea626) blurred the whole game.
- Overlay (R1/RB press, pill, or N64 pad Start + Capture held 0.5 s; Options is pause only) -> options overlay (second UIWindow in the game's
  scene, game paused via galaxypad_engine_pause, no input forwarded). Pointer/gyro/button settings apply live, aspect and
  smooth motion are re-applied to the engine. The engine cannot return to the
  launcher mid-game (SDL window + render loop live until exit).
- Save: the game's own save sequence cannot be started safely from a lifecycle callback, so on scene re-activation after a
  resign/background the shell shows a "Closing the window does not save" toast; the overlay and launcher repeat it.
  Aspect ratio and Smooth Motion are applied after the engine starts
  (aspect saved by the game for the next start; smooth motion needs >= 110 Hz).

## Stereoscopic window (beta)

Launcher > View > "Stereoscopic window (beta)"; flat stays the default (`gv.viewMode` = `flat` | `stereo`).
Depth and convergence sliders: `gv.stereoDepth` (0-2, default 1) and `gv.stereoConvergence` (400-3000, default 1200).

- Engine (`Stereo.cpp`): per game step, update/calcAnim once, then draw the scene twice (left, right) with a view
  offset plus projection shear (zero parallax at the convergence distance). SmoothMotion is off while stereo is on.
  Render size per eye is the "Stereo resolution" option (`gv.stereoResolution`: 540 Low, 720 Medium = default,
  1080 High; applied live via `galaxypad_engine_stereo_set_resolution`): render scale = height / 456, so the EFB is
  960x540 / 1280x720 / 1920x1080. (It used to be a fixed 3x = 2432x1368 per eye, drawn twice; the first device trace
  showed ~31 fps in gameplay: game thread 17.5 ms of CPU work + ~13 ms waiting for the GPU.) The eye images stay
  1920x1080; the bridge's copy pass scales the picture up into them. Env override: `PETARI_STEREO_HEIGHT`.
  Pulling the trace from the headset: `devicectl device copy from ... --domain-type appDataContainer
  --domain-identifier com.example.galaxyvision --source Library/Caches/galaxyvision-trace.log`.
  Present modes in `Frame::stereoEye`: 1 left (eye image only),
  2 right (eye image + window present, keeps vsync pacing), 3 mono (both eyes, used when the view stage isn't ready).
- Bridge (`stereo_bridge.cpp`, `patch_aurora_stereo.py`): per eye, 4 IOSurfaces (BGRA 1920x1080) imported into Dawn
  via SharedTextureMemoryIOSurface (+ SharedFenceMTLSharedEvent). The engine renders into them; the latest slot and a
  sequence number are published after `OnSubmittedWorkDone`. No CPU readback.
- App (`GalaxyVisionStereo.swift`): wraps the IOSurfaces as MTLTextures, a CADisplayLink blits newest slots into two
  `LowLevelTexture`s shown on a 16:9 plane with `NativeStereo.usda` (camera-index switch; from Apple's
  RenderingAWindowedGameInStereo sample, license bundled as `Stereo-Apple-LICENSE.txt`). Hosted as a child view
  controller of the SDL window VC (not a new UIWindow, so no frosted blur).
- Failure falls back to flat with a toast. Trace log: `Library/Caches/galaxyvision-trace.log`.
- Known: the shear sign / depth direction is unverified on device; home menu / RmlUi overlays only render to the
  flat window (hidden behind the stereo view); no HUD depth option; ImGui not in the eye images.

## FPS counter (testing)
- `main.mm` (`GVFPSTick`): a small non-interactive `UILabel` subview of the game window's root view (top-right; not a
  UIWindow), refreshed every 0.5 s. Flat: delta of `galaxypad_engine_presented_frames()`. Stereo: that counter runs at
  2x (left eye present-between + right eye present), so the right eye's published sequence is used (one per game step),
  plus the eye resolution. Toggle "Show FPS counter (testing)" in the Graphics tab (`gv.showFPS`, default on), live.

## Sharp upscaling (MetalFX) for the stereo window
- Setting `gv.stereoSharp` ("Sharp upscaling (MetalFX)", stereo settings in the View tab and in-game Graphics tab, default on,
  live). Only below High (Low 960x540 / Medium 1280x720); High and any failure use the plain path (engine scales across the image).
- Engine (`stereo_bridge.cpp`, `galaxypad_engine_stereo_set_rect` / `_slot_size`): with a rect height set, the XFB is drawn 1:1
  into the top-left 16:9 rectangle of the 1920x1080 eye IOSurface (no scale-up), and each slot publishes its picture size.
- App (`GalaxyVisionStereo.swift`): per tick, if the pair's picture is smaller than the image: blit the rectangle from a raw
  (`bgra8Unorm`) view of the IOSurface into a private input texture of exactly that size, `MTLFXSpatialScaler` (perceptual mode,
  the data is already display-encoded) to a private 1920x1080 `bgra8Unorm` output, blit it through an sRGB view into the
  LowLevelTexture. Scalers are cached per size, one per eye. Frames that are sub-sized while sharp is off/failed are skipped
  (never shown unscaled). Any failure sets `GVStereoEngine.sharpFailed` for the run and the engine returns to the plain path.
- The FPS counter shows "sharp" while MetalFX pictures are being shown. Untested on device.

## Pause in the stereo window (fix)
- Cause (from code and the device trace, not yet confirmed on the headset): the game opens its own pause menu by holding Plus (or
  Minus) for 12 game STEPS (`PauseButtonCheckerInGame`, `sHoldCounterMax`, 0.2 s at the Wii's 60 steps/s). The stereo window draws
  each step twice and runs about 20-45 steps/s, so the same hold took 0.3-0.6 s and a normal press never reached 12. The R1 options
  overlay (PS5/Xbox pads) and the N64 Start+Capture combo only act while the game's pause menu is up, so they looked broken too.
- Fix (engine `PauseButtonCheckerInGame.cpp`, native only): the hold also counts in real time. A button held for 200 ms counts as held
  even if fewer than 12 steps passed ("Petari pause: Plus held N ms (M steps, slow frame rate): counted as held" in the trace log).
  At 60 steps/s nothing changes; it still fires once per hold.
- Overlay visibility (`main.mm`): `GVShowOverlay` hides the stereo child view while the options overlay (a subview of the game window,
  never a UIWindow) is up, so the 2D overlay cannot end up behind the 3D RealityKit plane; the paused game's flat frame shows behind
  it. `GVHideOverlay` shows the stereo view again before unpausing.
