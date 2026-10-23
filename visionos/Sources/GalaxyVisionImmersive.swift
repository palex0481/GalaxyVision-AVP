// SPDX-License-Identifier: GPL-3.0-or-later
// Immersive space (beta): a big flat game screen floating in an outer-space environment.
//
// A SwiftUI ImmersiveSpace (RealityKit, full immersion) is activated from the UIKit/SDL app through visionOS 26's
// scene bridging (UIHostingSceneDelegate + UISceneSessionActivationRequest). The space holds
//   - a star sphere (a procedurally painted 4096x2048 sky: stars, a Milky Way band, nebulae, a distant galaxy),
//   - drifting star bits (a RealityKit particle emitter),
//   - the game screen: the same GVStereoRenderer screen entity as the Stereoscopic window, i.e. the engine's eye
//     IOSurfaces blitted into two LowLevelTextures and shown by the NativeStereo ShaderGraph material.
// "Screen depth (3D)" off: the engine draws each step once (depth 0 = mono) and both eyes see the same picture.
// On: the engine draws both eyes and the screen shows real stereo depth.
// The SDL game window keeps running (it paces the engine and hosts the options overlay), shrunk to a small panel
// while the space is open and enlarged again while the options are up.
import SwiftUI
import RealityKit
import UIKit

final class GVImmersiveModel: ObservableObject {
  @Published var isOpen = false
}

@objc(GVImmersive)
final class GVImmersive: NSObject {
  static let spaceID = "galaxyvision-immersive"
  static let model = GVImmersiveModel()
  nonisolated(unsafe) static var dismissAction: (() -> Void)?
  nonisolated(unsafe) static var errorHandler: ((String) -> Void)?
  nonisolated(unsafe) private static var savedSize: CGSize?
  nonisolated(unsafe) private static var overlayUp = false

  @objc static var isOpen: Bool { model.isOpen }

  /// Asks visionOS to open the space. `onError` runs on the main thread if it cannot (or the screen cannot start).
  @objc(openWithErrorHandler:) static func open(onError: @escaping (String) -> Void) {
    errorHandler = onError
    guard let request = UISceneSessionActivationRequest(hostingDelegateClass: GVImmersiveSceneDelegate.self, id: spaceID) else {
      onError("the immersive space request could not be created.")
      return
    }
    UIApplication.shared.activateSceneSession(for: request) { error in
      DispatchQueue.main.async { onError("the immersive space could not be opened (\(error.localizedDescription)).") }
    }
  }

  @objc static func close() {
    if let dismissAction { dismissAction(); return }
    for session in UIApplication.shared.openSessions where session.role.rawValue == "UISceneSessionRoleImmersiveSpaceApplication" {
      UIApplication.shared.requestSceneSessionDestruction(session, options: nil, errorHandler: nil)
    }
  }

  /// The options overlay is up (the window must be big enough for it) or gone.
  @objc static func setOverlay(_ up: Bool) {
    overlayUp = up
    applyWindowSize()
  }

  static func spaceStateChanged() { applyWindowSize() }

  /// While the space is open the game window is a small control panel; it is full size for the options and when closed.
  private static func applyWindowSize() {
    guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
    let compact = model.isOpen && !overlayUp
    if compact {
      if savedSize == nil { savedSize = scene.effectiveGeometry.coordinateSpace.bounds.size }
      scene.requestGeometryUpdate(.Vision(size: CGSize(width: 560, height: 340))) { _ in }
    } else if let size = savedSize {
      savedSize = nil
      scene.requestGeometryUpdate(.Vision(size: size)) { _ in }
    }
  }

  /// The renderer or the space failed after it opened.
  static func fail(_ message: String) {
    let handler = errorHandler
    DispatchQueue.main.async {
      close()
      handler?(message)
    }
  }
}

@objc(GVImmersiveSceneDelegate)
final class GVImmersiveSceneDelegate: UIResponder, UIHostingSceneDelegate {
  static var rootScene: some SwiftUI.Scene {
    ImmersiveSpace(id: GVImmersive.spaceID) {
      GVImmersiveView()
    }
    .immersionStyle(selection: .constant(.full), in: .full)
  }
}

/// The small game-window content while the immersive mode is selected (a subview over the flat picture, not a UIWindow).
@objc(GVImmersivePanelFactory)
final class GVImmersivePanelFactory: NSObject {
  @objc static func makeViewController(onEnter: @escaping () -> Void, onFlat: @escaping () -> Void) -> UIViewController {
    let host = UIHostingController(rootView: GVImmersivePanel(onEnter: onEnter, onFlat: onFlat))
    host.view.backgroundColor = .black
    return host
  }
}

struct GVImmersivePanel: View {
  @ObservedObject private var model = GVImmersive.model
  let onEnter: () -> Void
  let onFlat: () -> Void

  var body: some View {
    VStack(spacing: 14) {
      Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(.white)
      Text("Immersive space (beta)").font(.title3.bold()).foregroundStyle(.white)
      if model.isOpen {
        Text("The game is on the big screen in space. Pause and press R1 / RB for the options; this window grows back for them.")
          .font(.footnote).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.8))
        Button("Exit immersive space") { GVImmersive.close() }
          .buttonStyle(.borderedProminent)
      } else {
        Text("The immersive space is closed. The game keeps running.")
          .font(.footnote).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.8))
        HStack {
          Button("Enter immersive space") { onEnter() }.buttonStyle(.borderedProminent)
          Button("Use the flat window") { onFlat() }
        }
      }
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.black)
  }
}

struct GVImmersiveView: View {
  @StateObject private var renderer = GVStereoRenderer()
  @AppStorage(GVKeyImmersiveSize) private var size = 6.0
  @AppStorage(GVKeyImmersiveDistance) private var distance = 3.5
  @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
  @State private var world = Entity()
  @State private var started = false

  var body: some View {
    RealityView { content in
      content.add(world)
      world.addChild(renderer.screen)
      renderer.screen.addChild(GVSpaceScene.bezel())
      world.addChild(GVSpaceScene.starBits())
      place()
    } update: { _ in
      place()
    }
    .task { await buildSky() }
    .task {
      do {
        try await renderer.prepare()
        try Task.checkCancellation()
        renderer.start()
      } catch is CancellationError {
        renderer.stop()
      } catch {
        renderer.stop()
        GVImmersive.fail(error.localizedDescription)
      }
    }
    .onChange(of: renderer.errorMessage) { _, message in
      if let message { GVImmersive.fail(message) }
    }
    .onAppear {
      GVImmersive.dismissAction = { Task { await dismissImmersiveSpace() } }
      GVImmersive.model.isOpen = true
      GVImmersive.spaceStateChanged()
    }
    .onDisappear {
      renderer.stop()
      GVImmersive.dismissAction = nil
      GVImmersive.model.isOpen = false
      GVImmersive.spaceStateChanged()
    }
  }

  /// The screen is straight ahead at eye height; `size` is its width in metres, `distance` how far away.
  private func place() {
    renderer.fit(width: Float(size), height: Float(size))
    renderer.screen.position = SIMD3<Float>(0, 1.5, -Float(distance))
  }

  private func buildSky() async {
    guard let image = await Task.detached(priority: .userInitiated, operation: { GVSpaceSky.makeImage() }).value else { return }
    guard let texture = try? await TextureResource(image: image, options: .init(semantic: .color)) else { return }
    var material = UnlitMaterial()
    material.color = .init(tint: .white, texture: .init(texture))
    material.faceCulling = .none
    let sky = ModelEntity(mesh: .generateSphere(radius: 100), materials: [material])
    world.addChild(sky)
  }
}

enum GVSpaceScene {
  /// A thin black frame behind the picture, a child of the screen (its units are the screen's).
  static func bezel() -> Entity {
    var material = UnlitMaterial(color: .black)
    material.faceCulling = .none
    let bezel = ModelEntity(mesh: .generatePlane(width: 1.025, height: 0.5625 * 1.04), materials: [material])
    bezel.position = SIMD3<Float>(0, 0, -0.0015)
    return bezel
  }

  /// Slowly drifting specks in the air around the player.
  static func starBits() -> Entity {
    let entity = Entity()
    entity.position = SIMD3<Float>(0, 1.5, 0)
    var emitter = ParticleEmitterComponent()
    emitter.emitterShape = .box
    emitter.emitterShapeSize = SIMD3<Float>(14, 7, 14)
    emitter.birthLocation = .volume
    emitter.speed = 0.03
    emitter.speedVariation = 0.02
    emitter.mainEmitter.birthRate = 35
    emitter.mainEmitter.lifeSpan = 30
    emitter.mainEmitter.size = 0.012
    emitter.mainEmitter.sizeVariation = 0.006
    emitter.mainEmitter.color = .constant(.single(.init(red: 0.85, green: 0.9, blue: 1.0, alpha: 0.8)))
    emitter.mainEmitter.blendMode = .additive
    emitter.mainEmitter.isLightingEnabled = false
    entity.components.set(emitter)
    return entity
  }
}

// MARK: - The sky

private struct GVRandom: RandomNumberGenerator {
  var state: UInt64
  mutating func next() -> UInt64 {
    state &+= 0x9E3779B97F4A7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
    z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
    return z ^ (z >> 31)
  }
  mutating func unit() -> Double { Double.random(in: 0..<1, using: &self) }
  mutating func gauss() -> Double {
    let u = max(unit(), 1e-9), v = unit()
    return (-2 * log(u)).squareRoot() * cos(2 * .pi * v)
  }
}

enum GVSpaceSky {
  /// An equirectangular sky, painted with additive blending on near-black. Deterministic (seeded).
  static func makeImage(width: Int = 4096, height: Int = 2048) -> CGImage? {
    guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    let W = Double(width), H = Double(height)
    var rng = GVRandom(state: 0x6A1A7)
    ctx.setFillColor(red: 0.004, green: 0.006, blue: 0.015, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    ctx.setBlendMode(.plusLighter)

    typealias V = SIMD3<Double>
    func norm(_ v: V) -> V { v / (v * v).sum().squareRoot() }
    func direction(azimuth: Double, elevation: Double) -> V {
      V(sin(azimuth) * cos(elevation), sin(elevation), -cos(azimuth) * cos(elevation))
    }
    // Straight ahead (-z) is the picture's centre.
    func project(_ d: V) -> (x: Double, y: Double, lat: Double) {
      let lat = asin(max(-1, min(1, d.y)))
      let lon = atan2(d.x, -d.z)
      return ((lon / (2 * .pi) + 0.5) * W, (0.5 + lat / .pi) * H, lat)
    }
    func perpendicular(_ d: V) -> (V, V) {
      let helper: V = abs(d.y) < 0.9 ? V(0, 1, 0) : V(1, 0, 0)
      let a = norm(V(d.y * helper.z - d.z * helper.y, d.z * helper.x - d.x * helper.z, d.x * helper.y - d.y * helper.x))
      let b = V(d.y * a.z - d.z * a.y, d.z * a.x - d.x * a.z, d.x * a.y - d.y * a.x)
      return (a, b)
    }
    /// A soft round blob (radius in pixels along x and y), repeated across the seam.
    func blob(_ x: Double, _ y: Double, rx: Double, ry: Double, rgb: (Double, Double, Double), alpha: Double) {
      let colors = [CGColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: alpha),
                    CGColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: alpha * 0.3),
                    CGColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 0)] as CFArray
      guard let gradient = CGGradient(colorsSpace: nil, colors: colors, locations: [0, 0.35, 1]) else { return }
      for shift in [-W, 0, W] where x + shift + rx > 0 && x + shift - rx < W {
        ctx.saveGState()
        ctx.translateBy(x: x + shift, y: y)
        ctx.scaleBy(x: rx, y: ry)
        ctx.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 1, options: [])
        ctx.restoreGState()
      }
    }
    func star(_ d: V, radius: Double, rgb: (Double, Double, Double), alpha: Double) {
      let p = project(d)
      let stretch = min(1 / max(cos(p.lat), 0.001), 6)  // equirectangular poles stretch things sideways
      ctx.setFillColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: alpha)
      for shift in [-W, 0, W] where p.x + shift + radius * stretch > 0 && p.x + shift - radius * stretch < W {
        ctx.fillEllipse(in: CGRect(x: p.x + shift - radius * stretch, y: p.y - radius, width: 2 * radius * stretch, height: 2 * radius))
      }
    }
    func starColour(_ t: Double) -> (Double, Double, Double) {
      if t < 0.25 { return (0.72, 0.82, 1.0) }        // blue-white
      if t < 0.75 { return (1.0, 0.97, 0.92) }        // white
      if t < 0.92 { return (1.0, 0.86, 0.62) }        // yellow
      return (1.0, 0.70, 0.48)                        // orange
    }
    func uniformDirection() -> V {
      let y = 2 * rng.unit() - 1, phi = 2 * Double.pi * rng.unit()
      let r = (1 - y * y).squareRoot()
      return V(r * cos(phi), y, r * sin(phi))
    }

    // Milky Way: a tilted band of faint, warm-white glow with many dim stars.
    let pole = norm(V(0.35, 0.8, 0.45))
    let (bandU, bandV) = perpendicular(pole)
    func bandDirection(spread: Double) -> V {
      let lambda = 2 * Double.pi * rng.unit(), b = rng.gauss() * spread
      return norm(bandU * (cos(lambda) * cos(b)) + bandV * (sin(lambda) * cos(b)) + pole * sin(b))
    }
    for _ in 0..<2600 {
      let p = project(bandDirection(spread: 0.13))
      let r = 18 + 55 * rng.unit()
      let warm = rng.unit()
      blob(p.x, p.y, rx: r * min(1 / max(cos(p.lat), 0.15), 4), ry: r, rgb: (0.75 + 0.2 * warm, 0.78 + 0.1 * warm, 0.9 - 0.25 * warm), alpha: 0.016 + 0.020 * rng.unit())
    }
    for _ in 0..<16000 {
      star(bandDirection(spread: 0.16), radius: 0.35 + 0.5 * rng.unit(), rgb: starColour(rng.unit()), alpha: 0.18 + 0.4 * rng.unit())
    }

    // Nebulae: clusters of large, very faint coloured blobs.
    let nebulae: [(az: Double, el: Double, rgb: (Double, Double, Double), spread: Double)] = [
      (-1.2, 0.45, (0.80, 0.20, 0.62), 0.22), (2.6, -0.18, (0.16, 0.55, 0.85), 0.20), (-2.3, 0.62, (0.95, 0.5, 0.22), 0.16),
    ]
    for n in nebulae {
      let centre = direction(azimuth: n.az, elevation: n.el)
      let (a, b) = perpendicular(centre)
      for _ in 0..<170 {
        let d = norm(centre + a * (rng.gauss() * n.spread) + b * (rng.gauss() * n.spread * 0.7))
        let p = project(d)
        let r = 25 + 110 * pow(rng.unit(), 1.5)
        let tint = 0.75 + 0.25 * rng.unit()
        blob(p.x, p.y, rx: r * 1.3, ry: r, rgb: (n.rgb.0 * tint, n.rgb.1 * tint, n.rgb.2 * tint), alpha: 0.034 + 0.050 * rng.unit())
      }
    }

    // A distant spiral galaxy: a warm core and two arms of blue-white specks, tilted and squashed.
    let galaxyCentre = direction(azimuth: 0.95, elevation: 0.33)
    let (gA, gB) = perpendicular(galaxyCentre)
    let tilt = 0.5, squash = 0.42
    func galaxyDirection(_ x: Double, _ y: Double) -> V {
      let sy = y * squash
      let rx = x * cos(tilt) - sy * sin(tilt), ry = x * sin(tilt) + sy * cos(tilt)
      return norm(galaxyCentre + gA * rx + gB * ry)
    }
    for arm in 0..<2 {
      for i in 0..<700 {
        let t = Double(i) / 700
        let radius = 0.01 + 0.085 * t
        let angle = t * 3.4 + Double(arm) * Double.pi + rng.gauss() * 0.12
        let p = project(galaxyDirection(radius * cos(angle) + rng.gauss() * 0.004, radius * sin(angle) + rng.gauss() * 0.004))
        blob(p.x, p.y, rx: 2.5 + 4 * rng.unit(), ry: 2.5 + 4 * rng.unit(), rgb: (0.65, 0.78, 1.0), alpha: 0.05 + 0.08 * (1 - t))
      }
    }
    for _ in 0..<500 {
      let p = project(galaxyDirection(rng.gauss() * 0.03, rng.gauss() * 0.03))
      blob(p.x, p.y, rx: 4 + 5 * rng.unit(), ry: 4 + 5 * rng.unit(), rgb: (1.0, 0.85, 0.6), alpha: 0.05)
    }
    let core = project(galaxyCentre)
    blob(core.x, core.y, rx: 38, ry: 38, rgb: (1.0, 0.82, 0.55), alpha: 0.35)
    blob(core.x, core.y, rx: 10, ry: 10, rgb: (1.0, 0.95, 0.85), alpha: 0.7)

    // Field stars: many faint ones, a few bright ones with a small halo.
    for _ in 0..<9000 {
      let m = pow(rng.unit(), 5.0)
      star(uniformDirection(), radius: 0.45 + 0.9 * m, rgb: starColour(rng.unit()), alpha: 0.30 + 0.7 * m.squareRoot())
    }
    for _ in 0..<140 {
      let d = uniformDirection()
      let p = project(d)
      let c = starColour(rng.unit())
      let r = 1.1 + 1.0 * rng.unit()
      blob(p.x, p.y, rx: r * 6 * min(1 / max(cos(p.lat), 0.2), 3), ry: r * 6, rgb: c, alpha: 0.16)
      star(d, radius: r, rgb: c, alpha: 1)
    }
    return ctx.makeImage()
  }
}
