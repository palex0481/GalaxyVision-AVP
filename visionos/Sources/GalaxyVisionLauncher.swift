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
          Text("Open this screen any time with the Options button at the top right of the game, or hold Options + Create (PlayStation) or Start + Capture (N64 pad) for half a second.")
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
        Section("Applies on next start") {
          Text("Supersampling. Quit GalaxyVision after saving and open it again to change it.")
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
          Text("The first start prepares shaders and can take a while. Settings apply when you press Play. In game, tap the Options button at the top right (or hold Options + Create, or Start + Capture on the N64 pad) for the options screen. Closing the window does not save: use Pause > Save your progress and quit.")
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
          comingSoon("Stereoscopic window", "Real depth per eye, same framing as the flat window.")
          comingSoon("Immersive", "The game around you in an immersive space.")
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
          layoutRow("L3 / R1 / R3", "Recenter pointer")
          layoutRow("Options", "Pause (Plus)")
          layoutRow("Create / Share", "Minus")
          layoutRow("N64 pad", "A/B jump, Z crouch, L camera, R spin, C buttons nudge the pointer, C-down shoots, Capture recenters (hold Capture + C-down to nudge down), Start pauses")
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

private struct GraphicsTab: View {
  /// Shown over the running game: aspect ratio and smooth motion apply right away.
  var inGame = false
  var onDisplayChange: (() -> Void)? = nil
  @AppStorage(GVKeyRenderScale) private var renderScale = 0.0
  @AppStorage(GVKeyAspect) private var aspect = -1
  @AppStorage(GVKeySmoothMotion) private var smoothMotion = false

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Picker("Supersampling", selection: $renderScale) {
            Text("Off").tag(0.0)
            Text("2x").tag(2.0)
            Text("3x").tag(3.0)
          }
        } header: {
          Text("Supersampling")
        } footer: {
          Text("Supersampling renders the game at a multiple of its own frame size for smoother edges. Higher values cost performance.\(inGame ? " Applies on the next start." : "")")
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
      }
      .navigationTitle("Graphics")
      .onChange(of: aspect) { _, _ in if inGame { onDisplayChange?() } }
      .onChange(of: smoothMotion) { _, _ in if inGame { onDisplayChange?() } }
    }
  }
}
