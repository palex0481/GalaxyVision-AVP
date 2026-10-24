# Installing GalaxyVision on Apple Vision Pro

GalaxyVision is a native visionOS port of Super Mario Galaxy, built on [GalaxyPad](https://github.com/chrissotraidis/galaxypad) by Chris Sotraidis (MacioGalaxy and the Petari decompilation). It is not an emulator.

## Requirements

- A Mac with Apple silicon and Xcode with the visionOS SDK (built with Xcode 27.1; the lowest working version is untested)
- Apple Vision Pro on visionOS 26 or later, with Developer Mode on, paired with your Mac
- An Apple ID signed in to Xcode (built with a paid developer account; a free account is untested, and its apps need re-signing every 7 days)
- Your own copy of Super Mario Galaxy on Wii: the **USA disc, game ID RMGE01, revision 0**
- Homebrew tools: `brew install cmake ninja xcodegen python`
- About 3 GB of free space, network access during the first build, and patience: the first engine build can take a long time
- A game controller. A PlayStation DualSense is recommended (tested, with gyro aiming for Star Bits). DualShock 4, Xbox and the Switch Online N64 pad also work. PS VR2 Sense support is experimental and untested.

## Game files

You need to supply your own game files. This repository contains none.

1. Dump your own disc as a normal `.iso` with [CleanRip](https://wiibrew.org/wiki/CleanRip) on a homebrewed Wii. An extracted folder (with `sys/main.dol` and `files/`) or a decrypted `.iso` also works. `.wbfs` should work but is untested. RVZ, WIA, GCZ, CISO and NKit images are not supported.
2. Put it where the Vision Pro's Files app can see it, for example iCloud Drive, or AirDrop it from your Mac.
3. After installing (below), open GalaxyVision, press **Import game data…** on the Play tab, and pick the ISO or folder. Only RMGE01 revision 0 is accepted, and the app shows "Game data found" when it's ready.
4. Quit GalaxyVision completely and open it again to play.

## Build

Start from a checkout of this repository with its submodules. If you cloned without them, run:

```sh
git submodule update --init --recursive
```

1. Build the game engine for the headset:

   ```sh
   scripts/build-visionos-engine.sh
   ```

   If Xcode is not in `/Applications`, set `DEVELOPER_DIR` first, for example `export DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer`.

2. Set your signing details in `visionos/project.yml`: change `bundleIdPrefix` and `PRODUCT_BUNDLE_IDENTIFIER` to your own (for example `com.yourname.galaxyvision`), and set `DEVELOPMENT_TEAM` to your 10-character team ID (Xcode > Settings > Accounts).

3. Generate the Xcode project:

   ```sh
   cd visionos
   xcodegen generate
   ```

## Install on Apple Vision Pro

1. Open `visionos/GalaxyVision.xcodeproj`, choose the **GalaxyVision** scheme, and pick your Vision Pro as the destination.
2. Press Run. The simulator isn't supported.
3. On first launch, if visionOS asks, trust your developer profile in Settings > General > VPN & Device Management. The first game start prepares shaders and can take a while.

## Controls and known issues

- The launcher's Controls tab lists every button. The left stick moves Mario and also steers Ray surfing and Star Ball rolling.
- View modes: a flat window at 1440p, or a stereoscopic 3D window (beta, about 60 fps at 1080p per eye).
- If you started in Stereoscopic mode, you can switch between 3D and 2D mid-game from the in-game options (Graphics tab).
- In stereoscopic mode the in-game home menu and some overlays are hidden.
- PS VR2 Sense controller support is untested.
- This is a hobby project and isn't in active development.
