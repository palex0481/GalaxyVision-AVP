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
- Graphics: the MSAA row was removed (not usable in this engine) and the Supersampling picker was removed too (2x/3x were below
  the engine's native size and confusing). Rendering is always engine-native; the stored `gv.renderScale` is ignored unless the
  process env has `GV_ALLOW_RENDER_SCALE=1`, in which case it maps to `PETARI_RENDER_SCALE` (debug only; the old 4x, with a
  framebuffer larger than the window drawable, showed the picture at ~80% size, anchored top-left; with a non-default scale the shell
  writes PETARI_TRACE_BOOT output to `Library/Caches/galaxyvision-trace.log`).
- In game: a subtle "Options" pill (top right, own non-key passthrough UIWindow, shown once the engine reports started, with a
  7 s hint toast) opens the overlay; so does R1/RB on PS/Xbox pads. The overlay's Saving tab has "Quit GalaxyVision..." (confirmation
  dialog, calls galaxypad_engine_quit, no save). The engine's PauseMenu is decompiled game code inside the framework (the shell
  can't add an entry without rebuilding the engine; no exported pause-state query), so no hook was added.
- Overlay (R1/RB press, pill, or N64 pad Start + Capture held 0.5 s; Options is pause only) -> options overlay (second UIWindow in the game's
  scene, game paused via galaxypad_engine_pause, no input forwarded). Pointer/gyro/button settings apply live, aspect and
  smooth motion are re-applied to the engine. The engine cannot return to the
  launcher mid-game (SDL window + render loop live until exit).
- Save: the game's own save sequence cannot be started safely from a lifecycle callback, so on scene re-activation after a
  resign/background the shell shows a "Closing the window does not save" toast; the overlay and launcher repeat it.
  Aspect ratio and Smooth Motion are applied after the engine starts
  (aspect saved by the game for the next start; smooth motion needs >= 110 Hz).
