// SPDX-License-Identifier: GPL-3.0-or-later
// GalaxyVision launcher: shown before the engine starts. Modeled on SM64-Vision's TabView launcher
// (Start / Settings tabs). Settings live in UserDefaults under the GVKey* keys, which
// GalaxyVisionSettings (ObjC) and GalaxyVisionController read.
import SwiftUI
import UIKit

@objc(GVLauncherFactory)
final class GVLauncherFactory: NSObject {
  /// - gameFound: game data exists in Application Support/GalaxyPad/GameData/RMGE01.
  /// - onPlay: called on the main thread when the player taps Play (only offered when gameFound).
  /// - onImport: unused; the launcher's Play tab imports game data itself.
  @objc static func makeViewController(gameFound: Bool,
                                       onPlay: @escaping () -> Void,
                                       onImport: @escaping () -> Void) -> UIViewController {
    GalaxyVisionSettings.registerDefaults()
    let root = LauncherView(gameFound: gameFound, onPlay: onPlay, onImport: onImport)
    return UIHostingController(rootView: root)
  }
}

/// The in-game options overlay (controller combo while playing): live settings, a save reminder.
@objc(GVOverlayFactory)
final class GVOverlayFactory: NSObject {
  /// - onDisplayChange: aspect ratio changed; apply it to the running engine.
  /// - onResume: close the overlay and unpause the game.
  /// - onQuit: stop the game and close GalaxyVision (only after the player confirms in the overlay).
  @objc static func makeViewController(onDisplayChange: @escaping () -> Void,
                                       onResume: @escaping () -> Void,
                                       onQuit: @escaping () -> Void) -> UIViewController {
    GalaxyVisionSettings.registerDefaults()
    let host = UIHostingController(rootView: InGameOverlayView(onDisplayChange: onDisplayChange, onResume: onResume, onQuit: onQuit))
    host.view.backgroundColor = .clear
    return host
  }
}

struct InGameOverlayView: View {
  let onDisplayChange: () -> Void
  let onResume: () -> Void
  let onQuit: () -> Void

  var body: some View {
    ZStack {
      Color.black.opacity(0.45).ignoresSafeArea()
      VStack(spacing: 0) {
        HStack {
          Text("GalaxyVision options").font(.title2.bold())
          Spacer()
          Button { onResume() } label: { Label("Resume game", systemImage: "play.fill") }
            .buttonStyle(.borderedProminent)
        }
        .padding([.horizontal, .top], 20)
        .padding(.bottom, 8)
        TabView {
          Tab("Controls", systemImage: "gamecontroller") { ControlsTab() }
          Tab("Graphics", systemImage: "paintbrush") { GraphicsTab(inGame: true, onDisplayChange: onDisplayChange) }
          Tab("Audio", systemImage: "speaker.wave.2") { AudioTab(inGame: true) }
          Tab("Saving", systemImage: "square.and.arrow.down") { SavingTab(onQuit: onQuit) }
        }
      }
      .frame(maxWidth: 900, maxHeight: 640)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
      .padding(24)
    }
  }
}

private struct SavingTab: View {
  let onQuit: () -> Void
  @State private var confirmQuit = false

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Label("Closing the window does not save.", systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
          Text("The game only saves through its own save screens. To save and leave: Resume, press Pause, then choose \u{201C}Save your progress and quit\u{201D}. The game also saves by itself after story events and when you collect a Power Star.")
        } header: {
          Text("Saving")
        } footer: {
          Text("Open this screen from the game's pause menu: pause, then press R1 (PlayStation) / RB (Xbox). On the N64 pad, pause and hold Start + Capture for half a second.")
        }
        Section {
          Button(role: .destructive) { confirmQuit = true } label: {
            Label("Quit GalaxyVision\u{2026}", systemImage: "power")
          }
        } header: {
          Text("Back to the launcher")
        } footer: {
          Text("The game cannot return to the launcher while it runs. Quitting closes GalaxyVision; open it again from Home View to see the launcher. Anything since your last save is lost.")
        }
        Section("Applies right away") {
          Text("Pointer, gyro and button settings (Controls tab), aspect ratio (Graphics tab; the aspect ratio is saved by the game and fully applies on the next start).")
        }
      }
      .navigationTitle("Saving")
      .confirmationDialog("Quit GalaxyVision without saving?", isPresented: $confirmQuit, titleVisibility: .visible) {
        Button("Quit without saving", role: .destructive) { onQuit() }
        Button("Cancel", role: .cancel) { }
      } message: {
        Text("Progress since your last save is lost. To keep it, tap Cancel, Resume, then use Pause \u{203A} Save your progress and quit.")
      }
    }
  }
}

/// Stereoscopic window tuning: eye separation and convergence (applied live while playing).
struct StereoSettingsSection: View {
  var inGame: Bool
  var onChange: (() -> Void)? = nil
  @AppStorage(GVKeyStereoDepth) private var depth = 1.0
  @AppStorage(GVKeyStereoConvergence) private var convergence = 1200.0
  @AppStorage(GVKeyStereoResolution) private var resolution = 720
  @AppStorage(GVKeyStereoSharp) private var sharp = true

  var body: some View {
    Section {
      Picker("Stereo resolution", selection: $resolution) {
        Text("Low (960\u{00D7}540)").tag(540)
        Text("Medium (1280\u{00D7}720)").tag(720)
        Text("Balanced (1600\u{00D7}900)").tag(900)
        Text("High (1920\u{00D7}1080)").tag(1080)
      }
      Toggle("Sharp upscaling (MetalFX)", isOn: $sharp)
      VStack(alignment: .leading) {
        Text("Depth (eye separation): \(depth, specifier: "%.2f")x")
        Slider(value: $depth, in: 0...2, step: 0.05)
      }
      VStack(alignment: .leading) {
        Text("Convergence (screen plane distance): \(Int(convergence))")
        Slider(value: $convergence, in: 400...3000, step: 50)
      }
      Button("Reset depth and convergence") { depth = 1.0; convergence = 1200.0 }
    } header: {
      Text("Stereoscopic window (beta)")
    } footer: {
      Text("Stereo resolution is the size the game is drawn at for each eye (it is drawn twice, so a lower size runs faster and smoother; High looks sharpest and runs slowest). Sharp upscaling (MetalFX) draws at Low, Medium or Balanced and enlarges the picture to the full eye size with Apple\u{2019}s upscaler, so it looks crisper than a plain stretch for about the same speed; it does nothing at High, and the plain stretch is used if it can\u{2019}t start. Depth 0 is flat; higher separates the eyes more. Convergence is how far from the camera, in game units, things appear at the screen's surface: nearer values push more of the scene behind the window, farther values bring it out of it. The game HUD stays on the screen plane. Settings apply live from the options screen. If the stereo view cannot start, the flat window is used and a message says why; the trace is in Library/Caches/galaxyvision-trace.log.")
    }
    .onChange(of: depth) { _, _ in onChange?() }
    .onChange(of: convergence) { _, _ in onChange?() }
    .onChange(of: resolution) { _, _ in onChange?() }
    .onChange(of: sharp) { _, _ in onChange?() }
  }
}

struct LauncherView: View {
  let gameFound: Bool
  let onPlay: () -> Void
  let onImport: () -> Void

  var body: some View {
    TabView {
      Tab("Play", systemImage: "play.circle.fill") {
        PlayTab(gameFound: gameFound, onPlay: onPlay, onImport: onImport)
      }
      Tab("View", systemImage: "rectangle.on.rectangle") {
        ViewModeTab()
      }
      Tab("Controls", systemImage: "gamecontroller") {
        ControlsTab()
      }
      Tab("Graphics", systemImage: "paintbrush") {
        GraphicsTab()
      }
      Tab("Audio", systemImage: "speaker.wave.2") {
        AudioTab()
      }
    }
  }
}

// MARK: - Play

private struct PlayTab: View {
  let gameFound: Bool
  let onPlay: () -> Void
  let onImport: () -> Void
  @State private var started = false
  @State private var showPicker = false
  @State private var importing = false
  @State private var importMessage: String?
  @State private var importFailed = false
  @State private var importProgress: Double?
  @State private var imported = GVGameImporter.haveGame

  var body: some View {
    ScrollView {
      VStack(spacing: 20) {
        Text("GalaxyVision").font(.largeTitle)
        if gameFound {
          Label("Game data found", systemImage: "checkmark.seal.fill")
            .foregroundStyle(.green)
          Button {
            guard !started else { return }
            started = true
            onPlay()
          } label: {
            Label(started ? "Starting…" : "Play", systemImage: "play.fill")
              .frame(minWidth: 200)
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.extraLarge)
          .disabled(started)
          Text("The first start prepares shaders and can take a while. Settings apply when you press Play. In game, pause and press R1 / RB on the controller (N64 pad: hold Start + Capture) for the options screen. Closing the window does not save: use Pause > Save your progress and quit.")
            .font(.footnote).foregroundStyle(.secondary)
        } else if imported {
          Label("Game data found", systemImage: "checkmark.seal.fill")
            .foregroundStyle(.green)
          Text("Game data imported. Close GalaxyVision completely and open it again to play.")
            .font(.callout).multilineTextAlignment(.center)
        } else {
          Label("No game data found", systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
          Text("Put your Super Mario Galaxy (RMGE01) game data in Files on this device, then press Import and pick it: a disc image (.iso from CleanRip, decrypted .iso, or .wbfs), or an extracted folder containing sys/ and files/.")
            .font(.callout).multilineTextAlignment(.center)
          if importing {
            if let importProgress {
              ProgressView("Extracting disc image…", value: importProgress)
                .frame(maxWidth: 360)
            } else {
              ProgressView("Copying game data…")
            }
          } else {
            Button("Import game data…") { showPicker = true }
              .buttonStyle(.bordered)
          }
          Button { } label: { Label("Play", systemImage: "play.fill").frame(minWidth: 200) }
            .buttonStyle(.borderedProminent).controlSize(.extraLarge).disabled(true)
        }
        if let importMessage {
          Text(importMessage)
            .font(.callout).multilineTextAlignment(.center)
            .foregroundStyle(importFailed ? .red : .green)
        }
      }
      .padding(32)
      .frame(maxWidth: .infinity)
    }
    .fileImporter(isPresented: $showPicker, allowedContentTypes: [.folder, .item]) { result in
      switch result {
      case .failure(let error):
        importFailed = true
        importMessage = "Couldn't open the picker: \(error.localizedDescription)"
      case .success(let url):
        importing = true
        importMessage = nil
        importProgress = nil
        DispatchQueue.global(qos: .userInitiated).async {
          var last = -1.0
          let outcome = GVGameImporter.importGame(from: url) { f in
            guard f - last >= 0.01 || f >= 1 else { return }
            last = f
            DispatchQueue.main.async { importProgress = f }
          }
          DispatchQueue.main.async {
            importing = false
            importProgress = nil
            switch outcome {
            case .success:
              importFailed = false
              importMessage = "Import finished."
              imported = GVGameImporter.haveGame
            case .failure(let error):
              importFailed = true
              importMessage = error.message
            }
          }
        }
      }
    }
  }
}

struct GVImportError: Error { let message: String }

/// Copies an extracted RMGE01 disc folder (sys/main.dol + files/) into
/// Application Support/GalaxyPad/GameData/RMGE01, the path main.mm checks at launch.
enum GVGameImporter {
  static var gameDir: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("GalaxyPad/GameData/RMGE01", isDirectory: true)
  }
  static var haveGame: Bool {
    FileManager.default.fileExists(atPath: gameDir.appendingPathComponent("sys/main.dol").path)
  }

  private static func isGameRoot(_ url: URL) -> Bool {
    let fm = FileManager.default
    var dir: ObjCBool = false
    return fm.fileExists(atPath: url.appendingPathComponent("sys/main.dol").path)
      && fm.fileExists(atPath: url.appendingPathComponent("files").path, isDirectory: &dir) && dir.boolValue
  }

  /// The picked folder itself, or a child such as RMGE01 / DATA / P-RMGE (one or two levels down).
  private static func findGameRoot(in url: URL) -> URL? {
    if isGameRoot(url) { return url }
    let fm = FileManager.default
    let kids = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
    for kid in kids where isGameRoot(kid) { return kid }
    for kid in kids {
      let grand = (try? fm.contentsOfDirectory(at: kid, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
      for g in grand where isGameRoot(g) { return g }
    }
    return nil
  }

  /// Moves a finished staging folder into place, replacing any old copy only now.
  private static func install(_ staging: URL) throws {
    let fm = FileManager.default
    if fm.fileExists(atPath: gameDir.path) {
      _ = try fm.replaceItemAt(gameDir, withItemAt: staging)
    } else {
      try fm.moveItem(at: staging, to: gameDir)
    }
  }

  private static func importISO(_ iso: URL, progress: @escaping (Double) -> Void) -> Result<Void, GVImportError> {
    let fm = FileManager.default
    let parent = gameDir.deletingLastPathComponent()
    let staging = parent.appendingPathComponent("RMGE01.importing", isDirectory: true)
    do {
      try fm.createDirectory(at: parent, withIntermediateDirectories: true)
      if fm.fileExists(atPath: staging.path) { try fm.removeItem(at: staging) }
      try extractDisc(iso, to: staging, progress: progress)
      guard isGameRoot(staging) else { throw GVImportError(message: "The extraction didn't produce sys/main.dol and files/. Nothing was changed.") }
      try install(staging)
      return .success(())
    } catch let e as GVImportError {
      try? fm.removeItem(at: staging)
      return .failure(e)
    } catch {
      try? fm.removeItem(at: staging)
      return .failure(GVImportError(message: "Extracting failed: \(error.localizedDescription). Your previous game data (if any) was kept."))
    }
  }

  /// Dolphin DiscIO first (normal encrypted CleanRip ISOs, decrypted ISOs, WBFS); if DiscIO
  /// can't open the file as a Wii disc, fall back to the built-in decrypted-ISO reader.
  private static func extractDisc(_ iso: URL, to staging: URL, progress: @escaping (Double) -> Void) throws {
    final class Box { let f: (Double) -> Void; init(_ f: @escaping (Double) -> Void) { self.f = f } }
    if GVDiscIOCanOpen(iso.path) != 0 {
      let box = Unmanaged.passRetained(Box(progress))
      defer { box.release() }
      var err = [CChar](repeating: 0, count: 256)
      let rc = GVDiscIOExtract(iso.path, staging.path, { ctx, f in
        Unmanaged<Box>.fromOpaque(ctx!).takeUnretainedValue().f(f)
      }, nil, box.toOpaque(), &err, err.count)
      if rc == 0 { return }
      try? FileManager.default.removeItem(at: staging)
      throw GVImportError(message: "\(String(cString: err)) Your previous game data (if any) was kept.")
    }
    try GVISOExtractor.extract(iso: iso, to: staging, progress: progress)
  }

  static func importGame(from picked: URL, progress: @escaping (Double) -> Void) -> Result<Void, GVImportError> {
    let scoped = picked.startAccessingSecurityScopedResource()
    defer { if scoped { picked.stopAccessingSecurityScopedResource() } }
    let ext = picked.pathExtension.lowercased()
    if ext == "iso" || ext == "wbfs" { return importISO(picked, progress: progress) }
    if ["rvz", "gcz", "wia", "ciso", "nkit"].contains(ext) {
      return .failure(GVImportError(message: ".\(ext) files aren't supported. Use a CleanRip .iso or a .wbfs, or extract the disc to a folder with sys/ and files/ (for example with Dolphin: right-click the game > Properties > Filesystem > Extract Entire Disc), then pick that."))
    }
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: picked.path, isDirectory: &isDir), isDir.boolValue else {
      return .failure(GVImportError(message: "That file isn't supported. Pick a .iso or .wbfs disc image, or the extracted game folder that contains sys/ and files/."))
    }
    guard let root = findGameRoot(in: picked) else {
      return .failure(GVImportError(message: "That folder doesn't look like extracted game data. It needs sys/main.dol and a files/ folder (or a RMGE01 or DATA folder that has them)."))
    }
    if let id = try? Data(contentsOf: root.appendingPathComponent("sys/boot.bin"), options: .mappedIfSafe).prefix(6),
       let s = String(data: id, encoding: .ascii), s.count == 6, !s.hasPrefix("RMGE01") {
      return .failure(GVImportError(message: "This disc is \(s), not the USA Super Mario Galaxy (RMGE01)."))
    }
    let fm = FileManager.default
    let parent = gameDir.deletingLastPathComponent()
    let staging = parent.appendingPathComponent("RMGE01.importing", isDirectory: true)
    do {
      try fm.createDirectory(at: parent, withIntermediateDirectories: true)
      if fm.fileExists(atPath: staging.path) { try fm.removeItem(at: staging) }
      try fm.copyItem(at: root, to: staging)
      guard isGameRoot(staging) else {
        try? fm.removeItem(at: staging)
        return .failure(GVImportError(message: "The copy didn't finish correctly. Nothing was changed; try again."))
      }
      if fm.fileExists(atPath: gameDir.path) {
        _ = try fm.replaceItemAt(gameDir, withItemAt: staging)
      } else {
        try fm.moveItem(at: staging, to: gameDir)
      }
      return .success(())
    } catch {
      try? fm.removeItem(at: staging)
      return .failure(GVImportError(message: "Copying failed: \(error.localizedDescription). Your previous game data (if any) was kept."))
    }
  }
}

// MARK: - View mode

private struct ViewModeTab: View {
  @AppStorage(GVKeyViewMode) private var viewMode = "flat"

  var body: some View {
    NavigationStack {
      Form {
        Section("View mode") {
          Button { viewMode = "flat" } label: {
            HStack {
              VStack(alignment: .leading) {
                Text("Flat window")
                Text("The game on a floating virtual screen.").font(.caption).foregroundStyle(.secondary)
              }
              Spacer()
              if viewMode == "flat" { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint) }
            }
          }
          Button { viewMode = "stereo" } label: {
            HStack {
              VStack(alignment: .leading) {
                HStack(spacing: 6) {
                  Text("Stereoscopic window")
                  Text("BETA").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.orange.opacity(0.85), in: Capsule())
                }
                Text("Real depth per eye in the window, same 16:9 framing as the flat window.").font(.caption).foregroundStyle(.secondary)
              }
              Spacer()
              if viewMode == "stereo" { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint) }
            }
          }
        }
        if viewMode == "stereo" {
          StereoSettingsSection(inGame: false)
        }
      }
      .navigationTitle("View")
    }
  }

  private func comingSoon(_ title: String, _ detail: String) -> some View {
    HStack {
      VStack(alignment: .leading) {
        Text(title)
        Text(detail).font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      Text("Coming soon").font(.caption).foregroundStyle(.secondary)
    }
    .opacity(0.5)
  }
}

// MARK: - Controls

private struct ControlsTab: View {
  @AppStorage(GVKeyPointerSensitivity) private var sensitivity = 1.0
  @AppStorage(GVKeyPointerMode) private var pointerMode = 0
  @AppStorage(GVKeyGyroAim) private var gyroAim = false
  @AppStorage(GVKeyGyroInvertX) private var invertX = false
  @AppStorage(GVKeyGyroInvertY) private var invertY = false
  @AppStorage(GVKeyBButtonJumps) private var bJumps = true

  var body: some View {
    NavigationStack {
      Form {
        Section("Pointer") {
          VStack(alignment: .leading) {
            Text("Sensitivity: \(sensitivity, specifier: "%.2f")x")
            Slider(value: $sensitivity, in: 0.5...2.0, step: 0.05)
          }
          Picker("Show pointer", selection: $pointerMode) {
            Text("When moved").tag(0)
            Text("Always").tag(1)
            Text("Hidden").tag(2)
          }
        }
        Section {
          Toggle("Gyro aim (PlayStation controllers)", isOn: $gyroAim)
          Toggle("Invert horizontal", isOn: $invertX).disabled(!gyroAim)
          Toggle("Invert vertical", isOn: $invertY).disabled(!gyroAim)
        } header: {
          Text("Gyro")
        } footer: {
          Text("Adds motion aiming to the right stick. Experimental: use the invert switches if the pointer moves the wrong way.")
        }
        Section {
          Toggle("Circle / N64 B jumps (Switch style)", isOn: $bJumps)
        } header: {
          Text("Buttons")
        } footer: {
          Text("On: Circle and the N64 B button act like A. Off: they act as the Wii B button, which backs out of menus and shoots Star Bits.")
        }
        Section("Layout") {
          layoutRow("Left stick", "Move; also steers Ray surfing and Star Ball rolling")
          layoutRow("X (Cross) / A", "Jump, swim, confirm, pull stars")
          layoutRow("Circle / B", bJumps ? "Jump, swim" : "Back, shoot Star Bits")
          layoutRow("Square / Triangle", "Spin, pick up, throw")
          layoutRow("R2", "Shoot Star Bits")
          layoutRow("L2", "Crouch, ground pound")
          layoutRow("L1", "Camera reset")
          layoutRow("Right stick", "Aim pointer")
          layoutRow("L3 / R3", "Recenter pointer")
          layoutRow("R1 / RB", "Open the options screen (not sent to the game)")
          layoutRow("Options", "Pause (Plus) only")
          layoutRow("Create / Share", "Minus")
          layoutRow("N64 pad", "A/B jump, Z crouch, L camera, R spin, C buttons nudge the pointer, C-down shoots, Capture recenters (hold Capture + C-down to nudge down), Start pauses, Start + Capture held opens the options screen")
          layoutRow("PS VR2 Sense", "Experimental and untested: same layout as a DualSense, split across the two controllers (R1 is the right grip, L1 the left grip)")
        }
      }
      .navigationTitle("Controls")
    }
  }

  private func layoutRow(_ button: String, _ action: String) -> some View {
    HStack(alignment: .top) {
      Text(button).foregroundStyle(.secondary)
      Spacer(minLength: 16)
      Text(action).multilineTextAlignment(.trailing)
    }
    .font(.callout)
  }
}

// MARK: - Graphics

private struct AudioTab: View {
  /// Shown over the running game: the change is heard right away on resume.
  var inGame = false
  @AppStorage(GVKeyMute) private var mute = false

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Toggle("Mute", isOn: $mute)
        } footer: {
          Text("Silences all game audio, music and sound effects. Saved, and applies right away and at every start.")
        }
      }
      .navigationTitle("Audio")
      .onChange(of: mute) { _, _ in if inGame { GalaxyVisionSettings.applyAudio() } }
    }
  }
}

private struct GraphicsTab: View {
  /// Shown over the running game: aspect ratio applies right away.
  var inGame = false
  var onDisplayChange: (() -> Void)? = nil
  @AppStorage(GVKeyAspect) private var aspect = -1
  @AppStorage(GVKeyViewMode) private var viewMode = "flat"
  @AppStorage(GVKeyShowFPS) private var showFPS = true
  @State private var flatNow = GVStereoEngine.flatOverride || !GVStereoEngine.sessionStereo

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Picker("Aspect ratio", selection: $aspect) {
            Text("Engine default").tag(-1)
            Text("4:3").tag(0)
            Text("16:9 widescreen").tag(1)
          }
        } header: {
          Text("Display")
        } footer: {
          Text("Aspect ratio is saved by the game and may need one more start to fully apply.")
        }
        Section {
          Toggle("Show FPS counter (testing)", isOn: $showFPS)
        } footer: {
          Text("A small frame-rate number in the top-right corner of the game window. In the Stereoscopic window it also shows the eye resolution. Turns on and off right away.")
        }
        if inGame {
          Section {
            Picker("View", selection: $flatNow) {
              Text("3D (Stereoscopic)").tag(false)
              Text("2D (flat)").tag(true)
            }
            .pickerStyle(.segmented)
          } header: {
            Text("View")
          } footer: {
            Text("Switches this game between the Stereoscopic window and the flat window when you resume, without restarting (from a flat start, 3D starts the Stereoscopic window, which can take a few seconds). 2D draws one picture at the window\u{2019}s native size, so it runs like the flat window. Not saved: the next start uses the View tab\u{2019}s choice.")
          }
          .onChange(of: flatNow) { _, value in
            GVStereoEngine.flatOverride = value
            // A run without stereo yet (flat start, or stereo failed): start it when the options close.
            if !value && !GVStereoEngine.sessionStereo { GVStereoEngine.requestStereoStart() }
            onDisplayChange?()
          }
          if !flatNow {
            StereoSettingsSection(inGame: true, onChange: onDisplayChange)
          }
        }
      }
      .navigationTitle("Graphics")
      .onChange(of: aspect) { _, _ in if inGame { onDisplayChange?() } }
    }
  }
}

// MARK: - Decrypted Wii ISO extraction (no keys; decrypted images only)

/// Extracts the game partition of a decrypted Wii disc image into an RMGE01 folder (sys/ + files/).
/// Supports decrypted images with the 0x400 hash header still in each 0x8000 cluster, and raw
/// unhashed partition data. Encrypted images are rejected.
enum GVISOExtractor {
  private final class Disc {
    let h: FileHandle
    init(_ h: FileHandle) { self.h = h }
    func read(_ off: UInt64, _ n: Int) throws -> Data {
      try h.seek(toOffset: off)
      let d = try h.read(upToCount: n) ?? Data()
      guard d.count == n else { throw GVImportError(message: "The disc image ended early (truncated file?).") }
      return d
    }
  }
  private static func be32(_ d: Data, _ o: Int) -> UInt32 {
    let b = d.startIndex + o
    return UInt32(d[b]) << 24 | UInt32(d[b + 1]) << 16 | UInt32(d[b + 2]) << 8 | UInt32(d[b + 3])
  }

  /// Reads `n` bytes at logical partition offset `off`.
  private struct Partition {
    let disc: Disc
    let base: UInt64
    let hashed: Bool
    func read(_ off: UInt64, _ n: Int) throws -> Data {
      if !hashed { return try disc.read(base + off, n) }
      var out = Data(capacity: n)
      var o = off
      var left = n
      while left > 0 {
        let cluster = o / 0x7C00, inner = o % 0x7C00
        let take = min(left, Int(0x7C00 - inner))
        out.append(try disc.read(base + cluster * 0x8000 + 0x400 + inner, take))
        o += UInt64(take); left -= take
      }
      return out
    }
  }

  private static func looksLikeBoot(_ d: Data) -> Bool {
    d.count >= 0x20 && be32(d, 0x18) == 0x5D1C9EA3
  }

  static func extract(iso: URL, to dest: URL, progress: (Double) -> Void) throws {
    guard let h = try? FileHandle(forReadingFrom: iso) else {
      throw GVImportError(message: "Couldn't open the disc image.")
    }
    defer { try? h.close() }
    let disc = Disc(h)
    let header = try disc.read(0, 0x20)
    let id = String(data: header.prefix(6), encoding: .ascii) ?? "?"
    if be32(header, 0x18) != 0x5D1C9EA3 {
      throw GVImportError(message: "This isn't a Wii disc image (.iso). WBFS, RVZ and other compressed formats aren't supported; extract the disc to a folder instead.")
    }
    guard id == "RMGE01" else {
      throw GVImportError(message: "This disc is \(id), not the USA Super Mario Galaxy (RMGE01).")
    }
    // Partition table: 4 groups of (count, offset>>2) at 0x40000. Find the data partition (type 0).
    let groups = try disc.read(0x40000, 32)
    var partOffset: UInt64?
    for g in 0..<4 where partOffset == nil {
      let count = be32(groups, g * 8), tableOff = UInt64(be32(groups, g * 8 + 4)) << 2
      guard count > 0, count < 64 else { continue }
      let table = try disc.read(tableOff, Int(count) * 8)
      for i in 0..<Int(count) where be32(table, i * 8 + 4) == 0 {
        partOffset = UInt64(be32(table, i * 8)) << 2; break
      }
    }
    guard let p = partOffset else {
      throw GVImportError(message: "Couldn't find the game partition in this disc image (unknown layout).")
    }
    let phdr = try disc.read(p, 0x2C0)
    let dataBase = p + (UInt64(be32(phdr, 0x2B8)) << 2)
    // Decide the layout by where a valid boot.bin appears.
    let hashedBoot = try? disc.read(dataBase + 0x400, 0x440)
    let rawBoot = try? disc.read(dataBase, 0x440)
    let part: Partition
    if let b = hashedBoot, looksLikeBoot(b) {
      part = Partition(disc: disc, base: dataBase, hashed: true)
    } else if let b = rawBoot, looksLikeBoot(b) {
      part = Partition(disc: disc, base: dataBase, hashed: false)
    } else {
      throw GVImportError(message: "This disc image looks encrypted (or uses an unknown layout). Only decrypted ISOs are supported. Decrypt it or extract it to a folder, then try again.")
    }

    let fm = FileManager.default
    let sys = dest.appendingPathComponent("sys", isDirectory: true)
    let files = dest.appendingPathComponent("files", isDirectory: true)
    try fm.createDirectory(at: sys, withIntermediateDirectories: true)
    try fm.createDirectory(at: files, withIntermediateDirectories: true)

    let boot = try part.read(0, 0x440)
    let bootID = String(data: boot.prefix(6), encoding: .ascii) ?? "?"
    guard bootID == "RMGE01" else {
      throw GVImportError(message: "The game partition is \(bootID), not RMGE01.")
    }
    try boot.write(to: sys.appendingPathComponent("boot.bin"))
    try part.read(0x440, 0x2000).write(to: sys.appendingPathComponent("bi2.bin"))
    let apphdr = try part.read(0x2440, 0x20)
    let appSize = 0x20 + Int(be32(apphdr, 0x14)) + Int(be32(apphdr, 0x18))
    try part.read(0x2440, appSize).write(to: sys.appendingPathComponent("apploader.img"))
    let dolOff = UInt64(be32(boot, 0x420)) << 2
    let dolHdr = try part.read(dolOff, 0x100)
    var dolSize = 0x100
    for i in 0..<18 {
      let o = Int(be32(dolHdr, i * 4)), s = Int(be32(dolHdr, 0x90 + i * 4))
      if s > 0 { dolSize = max(dolSize, o + s) }
    }
    try part.read(dolOff, dolSize).write(to: sys.appendingPathComponent("main.dol"))
    let fstOff = UInt64(be32(boot, 0x424)) << 2, fstSize = Int(be32(boot, 0x428)) << 2
    let fst = try part.read(fstOff, fstSize)
    try fst.write(to: sys.appendingPathComponent("fst.bin"))

    // FST: 12-byte entries; root's size field is the entry count; names follow the entries.
    let count = Int(be32(fst, 8))
    guard count > 0, count * 12 <= fst.count else {
      throw GVImportError(message: "The disc's file table is damaged (unknown layout).")
    }
    let names = count * 12
    func name(_ i: Int) -> String {
      let start = fst.startIndex + names + Int(be32(fst, i * 12) & 0xFFFFFF)
      var end = start
      while end < fst.endIndex && fst[end] != 0 { end += 1 }
      return String(data: fst[start..<end], encoding: .utf8) ?? String(decoding: fst[start..<end], as: UTF8.self)
    }
    var total: UInt64 = 0
    for i in 1..<count where fst[fst.startIndex + i * 12] == 0 { total += UInt64(be32(fst, i * 12 + 8)) }
    var done: UInt64 = 0
    // Stack of (directory URL, end index).
    var stack: [(URL, Int)] = [(files, count)]
    var i = 1
    while i < count {
      while let top = stack.last, i >= top.1 { stack.removeLast() }
      let dir = stack.last?.0 ?? files
      let n = name(i)
      guard !n.isEmpty, n != ".", n != "..", !n.contains("/") else {
        throw GVImportError(message: "The disc's file table has a bad name (unknown layout).")
      }
      if fst[fst.startIndex + i * 12] != 0 {
        let sub = dir.appendingPathComponent(n, isDirectory: true)
        try fm.createDirectory(at: sub, withIntermediateDirectories: true)
        stack.append((sub, Int(be32(fst, i * 12 + 8))))
      } else {
        let off = UInt64(be32(fst, i * 12 + 4)) << 2
        let size = UInt64(be32(fst, i * 12 + 8))
        let url = dir.appendingPathComponent(n)
        fm.createFile(atPath: url.path, contents: nil)
        let out = try FileHandle(forWritingTo: url)
        var pos: UInt64 = 0
        while pos < size {
          let chunk = Int(min(UInt64(4 << 20), size - pos))
          try autoreleasepool { try out.write(contentsOf: try part.read(off + pos, chunk)) }
          pos += UInt64(chunk); done += UInt64(chunk)
          if total > 0 { progress(Double(done) / Double(total)) }
        }
        try out.close()
      }
      i += 1
    }
  }
}
