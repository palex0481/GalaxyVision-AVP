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
