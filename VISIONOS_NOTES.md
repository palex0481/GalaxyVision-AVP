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

## Stereo performance pass (unmeasured on device)

Starting point (Low 540p stereo, trace of the c03120e MetalFX build): about 42 game steps/s, 22-25 ms per step.
Per step the game thread was busy about 13 ms and then waited about 10 ms for the draw-done (the GX processor drain
plus the EFB-snapshot GPU round trip). Resolution barely changed the step time (old 3x stereo about 25 ms), so the
step is latency/serialisation bound, not pixel bound. Flat 60 fps for comparison: 8.4 ms work + 4.8 ms draw-done.

Changes (engine commit "Stereo: Wii order ..."):
- **Wii frame order for stereo.** Draw left, draw right, then update/calcAnim, so the game logic overlaps the right
  eye's GX drain (as the flat window already does). `Stereo::beginEyes(previousStep)` uses the view stage saved by the
  previous step's calcAnim. Cost: the eyes show the state of the previous update, i.e. up to one step more latency.
- **Left eye skips its EFB captures.** `Stereo::skipDrawSync()` makes LensFlare / StarPointerDirector / TalkDirector
  skip `setDrawSyncToken()` while drawing the left eye. The right eye's captures always overwrote the left's before, so the
  game sees the same data. Removes 3 render-pass splits and a GPU round trip from the left eye.
- **Balanced 1600x900 stereo resolution** (MetalFX) between Medium and High.
- **Timers** (no behaviour change), printed to the trace log (Library/Caches/galaxyvision-trace.log):
  - `Petari Stereo timing (ms per step ...)`: update, calcAnim, draw left (game-thread CPU), present left (left drain wait),
    draw right, end frame, seam, retrace wait.
  - `Petari Stereo GX processor thread: N ms busy per step`: time the Aurora FIFO processor thread spends turning GX
    commands into draws (pipeline/bind-group lookup, uniforms, texture upload, draw building).
  - `Petari Stereo GPU ...`: submit-to-GPU-done per eye.
  - `GalaxyVision stereo host ...`: pairs/s and copy/MetalFX GPU time of the RealityKit side.

Not done: recording the GX stream once and replaying it for the second eye. J3D loads each shape's view*model matrices
inside the draw stream, so a replay has to patch matrices in the FIFO; too risky to do without a device to test on.
Expected gain of the shipped changes is an estimate only (about 23 ms -> 13-17 ms per step); read the new log lines after
a stereo session to verify. 60 fps at 1080p per eye is unproven.

## Ambient glow (flat window)

A switch in the launcher's View tab (flat mode) and the in-game Graphics tab: **Ambient glow** (default off), with
**Glow strength** and **Glow size** sliders shown while it is on. Settings keys `gv.ambientGlow`, `gv.glowStrength`
(0.1-1, default 0.7), `gv.glowSize` (0-1, default 0.5). The app reads them every 50 ms, so they apply live.

- **Layout constraint.** A visionOS window can't draw outside its bounds, so the glow lives in a border inside the window:
  while on, the engine's Metal view is scaled down about its centre (view transform only; the drawable, aspect and
  window size are untouched) by 1 - 2f, f = 3%..12% per side (Glow size). The glow is a black UIView with four
  gradient strips inserted directly below the Metal view in the SDL window's root view (not a UIWindow, so no glass
  material). Off: nothing is inserted, the transform is the identity, the layout is the old one. Stereo mode: no glow.
- **Colours.** `present_aurora.cpp` (render worker): while enabled, about 20x/s a tiny compute pass averages 16 cells per
  edge (a band 7% deep, 8x6 taps each) of the presented XFB into 64 RGB values, copies the 256 bytes to a small buffer
  and maps it asynchronously (no wait, no full-frame readback). Disabled: no work at all. Exports
  `galaxypad_engine_glow_enable` / `galaxypad_engine_glow_colors`. The app smooths them (about 0.15 s) and fades to
  black when no new sample arrives for 0.7 s (VI black).
- Pointer note: with the picture scaled, window-pointer (not controller) positions are off by the scale while the glow is on.
- Unverified on device.

## Immersive space (beta): a big flat screen in outer space

View tab > **Immersive space** (BETA), next to Flat window and Stereoscopic window (the old "Immersive: coming soon" row
now reads "Immersive 3D: coming soon", a placeholder for the separate 3D mode, see the assessment below). Settings keys:
`gv.viewMode = "immersive"`, `gv.immersiveSize` (screen width in metres, 2-14, default 6), `gv.immersiveDistance`
(2-8 m, default 3.5), `gv.immersiveDepth` ("Screen depth (3D)", default off). The screen is straight ahead at eye height
(1.5 m). Picture resolution / Sharp upscaling / depth strength reuse the stereo keys (`gv.stereoResolution`,
`gv.stereoSharp`, `gv.stereoDepth`). Size and distance apply live, also in the in-game options (Graphics tab).

- **Hosting (new, UNVERIFIED on device).** visionOS 26 UIKit scene bridging: `GVImmersiveSceneDelegate`
  (`UIHostingSceneDelegate`, `GalaxyVisionImmersive.swift`) declares `ImmersiveSpace(id:)` (`.immersionStyle(.full)`);
  `main.mm` activates it with `UISceneSessionActivationRequest(hostingDelegateClass:id:)` once the stereo bridge is up
  (`GVOpenImmersive`). `project.yml` / Info.plist gained a `UISceneSessionRoleImmersiveSpaceApplication` configuration
  naming that delegate class, and **`UIApplicationSupportsMultipleScenes` is now true** (needed to open a second scene; the
  game window is still one scene with the same `GalaxyPad` configuration; risk: the system could offer a second
  game window, which the engine does not support).
- **What is in the space.** A RealityKit `RealityView`: an inside-out star sphere (radius 100 m, unlit) textured with a
  4096x2048 equirectangular sky painted at start by `GVSpaceSky` (CoreGraphics, seeded and deterministic: ~25k stars in
  four colour classes, a Milky Way band, three nebulae, a spiral galaxy; about 0.27 s on the Mac, checked as an image
  there), a particle emitter of slow drifting specks (30 s life, 14x7x14 m box around the player), and the game
  screen: the same `GVStereoRenderer.screen` entity as the Stereoscopic window (engine eye IOSurfaces -> two
  `LowLevelTexture`s -> NativeStereo ShaderGraph material) plus a thin black bezel child. Nothing was removed from or
  changed in the stereo path except that `fit()` is called with the user's size.
- **Screen depth (3D).** Off (default): `GVStereoEngine.applySavedSettings` sends depth 0 and the engine
  (`Stereo::beginEyes`, new `gDepth < 0.005` test) draws each step once through its existing mono path, which publishes
  the same picture to both eye images, so the screen is flat and cheaper than stereo. On: both eyes are drawn with the
  stereo depth setting. (The Stereoscopic window with depth 0 now also takes the mono path; same picture, less work.)
- **Controls and pause/options.** The SDL game window is kept (it paces the engine, takes the controller and hosts
  the overlay); when the space opens it is requested to shrink to 560x340 (`requestGeometryUpdate(.Vision(size:))`) and
  shows a small black control panel (Exit immersive space; when the space is closed: Enter immersive space / Use the
  flat window). R1 (or the other combos) opens the existing options overlay in that window; the window is
  requested back to its previous size while the overlay is up and shrunk again on Resume (`GVImmersive.setOverlay`). So
  the options are used in the window that sits in the room beside the screen; the paused game stays visible on the big
  screen. Closing the window ends the game (as before).
- **Failure.** If the space cannot be requested, or the renderer fails, the panel is removed, the bridge is closed and
  the flat window is used with a toast saying why.
- **Not done / ideas.** Glow tinting the surroundings; a head-locked or Digital-Crown recentre of the screen; options
  inside the space itself (a SwiftUI attachment); real star geometry instead of the 4096 px sky texture (stars are a
  little soft at 40 px/deg); passthrough dimming levels.
- Unverified on device: that the bridged scene activates under the SDL app delegate, that the window shrinks, that the
  sky/particles/bezel look right, the frame rate in the space.
