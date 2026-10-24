# GalaxyVision

GalaxyVision is an Apple Vision Pro port of [GalaxyPad](https://github.com/chrissotraidis/galaxypad), which runs Super Mario Galaxy natively on Apple devices. This fork adds a visionOS app.

- **Flat window**: the game on a floating virtual screen.
- **Stereoscopic 3D window (beta)**: the game drawn once per eye, shown as real 3D inside one window.
- **Controllers**: PS5 DualSense, PS4 DualShock 4, Xbox controllers, the Nintendo Switch Online N64 pad, and PS VR2 Sense controllers (experimental, untested).
- **Launcher**: pick the view mode, check the controls, and change graphics settings before you press Play.

## Status: hobby project, not in active development

This is a hobby project. I am not actively developing it and I can't promise fixes, support or replies to issues. You are welcome to take the source and make your own changes. It is licensed GPL-3.0 (see `LICENSE`), so if you share a modified version you must share your source under the same license. Please keep the credit for the people whose work this stands on (see Credits below).

## Legal

- You must supply your own legally dumped copy of Super Mario Galaxy: the **USA disc, game ID RMGE01, revision 0**.
- No game files, disc images or extracted game data are included in this repository, and none should ever be added to it.
- This project is not affiliated with or endorsed by Nintendo. Super Mario Galaxy and related names belong to their owners.

## What you need

- A Mac with Apple silicon. (UNVERIFIED on Intel Macs.)
- Xcode with the visionOS SDK. It was built here with Xcode 27.1 (visionOS 27 SDK). The app targets visionOS 26.0, and the upstream project asks for Xcode 26 or newer. The lowest Xcode that works has NOT been tested.
- An Apple Vision Pro, plus an Apple developer account (a free account is enough to install on your own device; UNVERIFIED for this app) for code signing.
- Command line tools: `git`, `cmake` 3.28 or newer, `ninja`, `python3`, and [`xcodegen`](https://github.com/yonaskolb/XcodeGen). With Homebrew: `brew install cmake ninja xcodegen python`. Tested versions here: cmake 4.4.4, ninja 1.13.2, xcodegen 2.46.0.
- Network access during the engine build (it downloads Dawn, SDL3 and other dependencies while configuring).
- Plenty of disk space and time. The `generated/` build folder was about 2.4 GB here, and a first engine build can take hours.

## Build and run in Xcode

1. **Get the source, including the engine.** The engine lives in `ref/galaxypad-engine`.

   ```sh
   git clone --recurse-submodules <URL OF THIS REPO> galaxypad-vision
   cd galaxypad-vision
   ```

   (The build script expects the engine at exactly `ref/galaxypad-engine`. The `ref/ModernGekko` submodule, and its `vendor/dolphin` submodule, are also needed: the app builds a small part of Dolphin's disc reader (DiscIO) from them for the Import button. `--recurse-submodules` fetches both. If you cloned without it, run `git submodule update --init --recursive`.)

2. **Build the engine** for the Vision Pro (device build):

   ```sh
   scripts/build-visionos-engine.sh
   ```

   This produces `generated/build/visionos-device-engine/native/app/GalaxyPadEngine.framework`. If you use Xcode from a non-default location, set `DEVELOPER_DIR` first, for example `export DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer`.

3. **Set your own signing details.** Open `visionos/project.yml` and change these two lines (and `bundleIdPrefix` near the top) to your own values:

   ```yaml
   PRODUCT_BUNDLE_IDENTIFIER: <your.bundle.id>        # for example com.yourname.galaxyvision
   DEVELOPMENT_TEAM: <YOUR_TEAM_ID>                  # your 10-character Apple team ID
   ```

   You can find your team ID in Xcode under Settings > Accounts, or on developer.apple.com under Membership.

4. **Generate the Xcode project.**

   ```sh
   cd visionos
   xcodegen generate
   ```

5. **Build and run.** Open `visionos/GalaxyVision.xcodeproj` in Xcode, choose the **GalaxyVision** scheme, pick your Vision Pro as the destination and press Run. (Your Vision Pro needs to be paired with the Mac and have Developer Mode turned on.) From the command line the equivalent is:

   ```sh
   xcodebuild -project GalaxyVision.xcodeproj -scheme GalaxyVision -configuration Debug \
     -destination 'id=<YOUR DEVICE UDID>' -derivedDataPath .build/dd-device \
     -allowProvisioningUpdates build
   ```

   The simulator is not supported: the engine is built for the device only.

## Putting your game data on the device

The in-app Import accepts a normal CleanRip `.iso`, a `.wbfs`, an extracted folder, or a decrypted `.iso`. Only the USA disc, RMGE01 revision 0, is accepted.

1. Get your RMGE01 game data in one of these forms:
   - **A normal disc image (`.iso`) dumped from your own disc with [CleanRip](https://wiibrew.org/wiki/CleanRip)** on a homebrewed Wii. This is the easiest option: pick the ISO as it is, with no decrypting or extracting. The app reads it with Dolphin's disc code (DiscIO), the same way upstream GalaxyPad's iOS importer does. Tested on a Mac against a real CleanRip dump: the result matched a `wit` extraction byte for byte. Not yet tested on the headset itself.
   - **A `.wbfs`** image of the same disc (read by the same DiscIO code; UNTESTED).
   - **A decrypted Wii `.iso`**. If DiscIO can't open the file, the app falls back to its own decrypted-ISO reader (only checked against a synthetic test image).
   - **An extracted folder** that contains `sys/` (with `sys/main.dol`) and `files/`. In Dolphin: right-click the game > Properties > Filesystem > right-click the disc > Extract Entire Disc. [Wiimms ISO Tools](https://wit.wiimm.de/) (`wit extract`) also works (exact command line UNVERIFIED).
2. Put it on the Vision Pro so it shows up in the Files app: for example through iCloud Drive, or AirDrop it from a Mac.
3. Open GalaxyVision, press **Import game data…** on the Play tab, and pick the ISO or the folder. You can also pick a parent folder that contains `RMGE01` or a `DATA` partition folder. The app copies or extracts it into its own storage (this takes a while) and then shows "Game data found".
4. Close GalaxyVision completely and open it again to play. The first start prepares shaders and can take a while.

RVZ, WIA, GCZ, CISO and NKit images aren't supported. Convert them back to a plain `.iso` in Dolphin, or extract them to a folder first.

**Alternative (manual, UNVERIFIED):** copy the folder into the app's container with `xcrun devicectl device copy to --device <udid> --domain-type appDataContainer --domain-identifier <your.bundle.id> --source <extracted folder> --destination "Library/Application Support/GalaxyPad/GameData/RMGE01"`, so that `.../RMGE01/sys/main.dol` exists.

## Known limitations

- Stereoscopic 3D is beta. It aims for about 60 fps but this isn't guaranteed; the per-eye render size is a setting.
- PS VR2 Sense controller support is preliminary and untested, because I don't own them. PlayStation, Xbox and Switch Online N64 pads are tested.
- Ray surfing and Star Ball rolling are steered with the left stick.
- The in-game home menu and some overlays only draw on the flat window, so they are hidden in Stereoscopic mode.

## Credits

GalaxyVision is built on other people's work. Please keep their credit if you reuse this:

- [GalaxyPad](https://github.com/chrissotraidis/galaxypad) and [galaxypad-engine](https://github.com/chrissotraidis/galaxypad-engine) by Chris Sotraidis, the upstream project this fork is based on.
- [MacioGalaxy](https://github.com/classicrob/MacioGalaxy) by classicrob and the [Petari](https://github.com/SMGCommunity/Petari) Super Mario Galaxy decompilation by SMGCommunity and contributors.
- Apple's "Rendering a windowed game in stereo" sample, used for the Stereoscopic window's eye-selecting material (license in `visionos/Resources/Stereo-Apple-LICENSE.txt`).
- [Dolphin](https://dolphin-emu.org/): the Import button uses Dolphin's DiscIO disc reader (GPL-2.0-or-later), built from the pinned copy in `ref/ModernGekko/vendor/dolphin`.
- [Wiimms ISO Tools](https://wit.wiimm.de/) by Wiimm, the extraction tool upstream GalaxyPad documents.
- Everything listed in `CREDITS.md` and `THIRD-PARTY-NOTICES.md` (Dolphin, ModernGekko and others).
- The app icon and parts of the code were made with AI assistance; see `CREDITS.md`.
