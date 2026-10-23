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
  /// - onImport: the import placeholder (document picker, not implemented yet).
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
  /// - onDisplayChange: aspect ratio / smooth motion changed; apply them to the running engine.
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
          Text("Pointer, gyro and button settings (Controls tab), aspect ratio and smooth motion (Graphics tab; the aspect ratio is saved by the game and fully applies on the next start).")
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

/// Immersive space (beta): screen size and distance (live, also while the space is open), "Screen depth (3D)".
struct ImmersiveSettingsSection: View {
  var inGame: Bool
  var onChange: (() -> Void)? = nil
  @AppStorage(GVKeyImmersiveDepth) private var depth3D = false
  @AppStorage(GVKeyImmersiveSize) private var size = 6.0
  @AppStorage(GVKeyImmersiveDistance) private var distance = 3.5
  @AppStorage(GVKeyStereoDepth) private var depth = 1.0
  @AppStorage(GVKeyStereoResolution) private var resolution = 720
  @AppStorage(GVKeyStereoSharp) private var sharp = true

  var body: some View {
    Section {
      VStack(alignment: .leading) {
        Text("Screen size (width): \(size, specifier: "%.1f") m")
        Slider(value: $size, in: 2...14, step: 0.5)
      }
      VStack(alignment: .leading) {
        Text("Screen distance: \(distance, specifier: "%.1f") m")
        Slider(value: $distance, in: 2...8, step: 0.25)
      }
      Button("Reset size and distance") { size = 6.0; distance = 3.5 }
      Toggle("Screen depth (3D)", isOn: $depth3D)
      if depth3D {
        VStack(alignment: .leading) {
          Text("Depth (eye separation): \(depth, specifier: "%.2f")x")
          Slider(value: $depth, in: 0.05...2, step: 0.05)
        }
      }
      Picker("Picture resolution", selection: $resolution) {
        Text("Low (960\u{00D7}540)").tag(540)
        Text("Medium (1280\u{00D7}720)").tag(720)
        Text("Balanced (1600\u{00D7}900)").tag(900)
        Text("High (1920\u{00D7}1080)").tag(1080)
      }
      Toggle("Sharp upscaling (MetalFX)", isOn: $sharp)
    } header: {
      Text("Immersive space (beta)")
    } footer: {
      Text("The game is a big flat screen floating in space; the screen is at eye height straight ahead. Comfort default: 6 m wide at 3.5 m. Size and distance change live (also while you play). Screen depth (3D) off draws the game once and shows the same picture to both eyes (fastest); on draws both eyes for real depth, like the Stereoscopic window. Picture resolution is the size the game is drawn at (High is sharpest and slowest); Sharp upscaling (MetalFX) enlarges Low, Medium and Balanced with Apple\u{2019}s upscaler. The game window shrinks to a small panel while you are in space and grows back when you pause and press R1 / RB for the options; its \u{201C}Exit immersive space\u{201D} button leaves the space. If the space cannot start, the flat window is used and a message says why.")
    }
    .onChange(of: depth3D) { _, _ in onChange?() }
    .onChange(of: depth) { _, _ in onChange?() }
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
    }
  }
}

// MARK: - Play

private struct PlayTab: View {
  let gameFound: Bool
  let onPlay: () -> Void
  let onImport: () -> Void
  @State private var started = false

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
        } else {
          Label("No game data found", systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
          Text("Place an extracted Super Mario Galaxy (RMGE01) folder in Application Support/GalaxyPad/GameData/RMGE01 (sys/main.dol must exist), or use Import (placeholder, not implemented yet).")
            .font(.callout).multilineTextAlignment(.center)
          Button("Import game data…", action: onImport)
            .buttonStyle(.bordered)
          Button { } label: { Label("Play", systemImage: "play.fill").frame(minWidth: 200) }
            .buttonStyle(.borderedProminent).controlSize(.extraLarge).disabled(true)
        }
      }
      .padding(32)
      .frame(maxWidth: .infinity)
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
          Button { viewMode = "immersive" } label: {
            HStack {
              VStack(alignment: .leading) {
                HStack(spacing: 6) {
                  Text("Immersive space")
                  Text("BETA").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.orange.opacity(0.85), in: Capsule())
                }
                Text("A big screen floating in outer space: stars, a nebula, a distant galaxy.").font(.caption).foregroundStyle(.secondary)
              }
              Spacer()
              if viewMode == "immersive" { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint) }
            }
          }
          comingSoon("Immersive 3D", "The game\u{2019}s world around you in 3D, like SM64-Vision\u{2019}s immersive mode.")
        }
        if viewMode == "stereo" {
          StereoSettingsSection(inGame: false)
        } else if viewMode == "immersive" {
          ImmersiveSettingsSection(inGame: false)
        } else {
          AmbientGlowSection()
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
          layoutRow("Left stick", "Move")
          layoutRow("Cross / A", "Jump, swim, confirm, pull stars")
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

// MARK: - Ambient glow

/// A soft glow of the picture's edge colours around the flat window (like a TV backlight). Changes apply right away,
/// also while playing. The glow lives inside the window, so the picture is drawn a little smaller while it is on.
private struct AmbientGlowSection: View {
  @AppStorage(GVKeyAmbientGlow) private var glow = false
  @AppStorage(GVKeyGlowStrength) private var strength = 0.7
  @AppStorage(GVKeyGlowSize) private var size = 0.5

  var body: some View {
    Section {
      Toggle("Ambient glow", isOn: $glow)
      if glow {
        VStack(alignment: .leading) {
          Text("Glow strength")
          Slider(value: $strength, in: 0.1...1.0)
        }
        VStack(alignment: .leading) {
          Text("Glow size")
          Slider(value: $size, in: 0.0...1.0)
        }
      }
    } header: {
      Text("Ambient glow")
    } footer: {
      Text("A soft glow around the game window that follows the colours at the picture\u{2019}s edges. The window can\u{2019}t draw outside itself, so while it is on the picture is shown a little smaller, with the glow in the border. Off keeps the window exactly as it is. Flat window only. Turns on and off right away.")
    }
  }
}

// MARK: - Graphics

private struct GraphicsTab: View {
  /// Shown over the running game: aspect ratio and smooth motion apply right away.
  var inGame = false
  var onDisplayChange: (() -> Void)? = nil
  @AppStorage(GVKeyRenderScale) private var renderScale = 0.0
  @AppStorage(GVKeyAspect) private var aspect = -1
  @AppStorage(GVKeySmoothMotion) private var smoothMotion = false
  @AppStorage(GVKeyViewMode) private var viewMode = "flat"
  @AppStorage(GVKeyShowFPS) private var showFPS = true

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Picker("Supersampling", selection: $renderScale) {
            Text("Off (native, default)").tag(0.0)
            Text("3x game size (near native)").tag(3.0)
            Text("2x game size (lower, faster)").tag(2.0)
          }
        } header: {
          Text("Supersampling")
        } footer: {
          Text("Off draws at the headset window's native 2560x1440 and is the sharpest. 3x renders at about 2432x1368 (just under native) and 2x at about 1625x1216, which is softer but lighter. Nothing above native is offered because it breaks the picture's size and aspect. Applies on the next start.")
        }
        Section {
          Picker("Aspect ratio", selection: $aspect) {
            Text("Engine default").tag(-1)
            Text("4:3").tag(0)
            Text("16:9 widescreen").tag(1)
          }
          Toggle("Smooth motion", isOn: $smoothMotion)
        } header: {
          Text("Display")
        } footer: {
          Text("Aspect ratio is saved by the game and may need one more start to fully apply. Smooth motion only does something on 120 Hz displays, so it probably has no effect in a headset.")
        }
        Section {
          Toggle("Show FPS counter (testing)", isOn: $showFPS)
        } footer: {
          Text("A small frame-rate number in the top-right corner of the game window. In the Stereoscopic window it also shows the eye resolution. Turns on and off right away.")
        }
        if inGame && viewMode == "stereo" {
          StereoSettingsSection(inGame: true, onChange: onDisplayChange)
        }
        if inGame && viewMode == "immersive" {
          ImmersiveSettingsSection(inGame: true, onChange: onDisplayChange)
        }
        if inGame && viewMode == "flat" {
          AmbientGlowSection()
        }
      }
      .navigationTitle("Graphics")
      .onChange(of: aspect) { _, _ in if inGame { onDisplayChange?() } }
      .onChange(of: smoothMotion) { _, _ in if inGame { onDisplayChange?() } }
    }
  }
}
