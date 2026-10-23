// SPDX-License-Identifier: GPL-3.0-or-later
// GalaxyVision "Stereoscopic window" (BETA): shows the engine's two eye images as a stereo screen.
//
// The engine renders the game twice per frame (left / right eye, Game/System/Stereo.cpp) into two rings of
// 1920x1080 IOSurfaces (Dawn shared texture memory). Here each IOSurface is wrapped as an MTLTexture and the
// newest finished slot of each eye is blitted into a RealityKit LowLevelTexture. A ShaderGraph material
// with the camera-index switch shows the left texture to the left eye and the right to the right eye,
// on a 16:9 plane that fits the window (the same approach as SM64-Vision's 3D Window).
//
// The eye-selecting material (NativeStereo.usda) follows Apple's RenderingAWindowedGameInStereo sample.
// See Stereo-Apple-LICENSE.txt in the app resources.
import SwiftUI
import RealityKit
import Metal
import QuartzCore
import IOSurface

@MainActor
final class GVStereoRenderer: NSObject, ObservableObject {
  @Published var errorMessage: String?
  let screen = ModelEntity()
  private static let width = 1920
  private static let height = 1080
  private static let slots = 4
  private static let aspect: Float = 9.0 / 16.0
  private var device: MTLDevice?
  private var queue: MTLCommandQueue?
  private var colors: [LowLevelTexture] = []
  private var eyes: [[MTLTexture]] = []  // [eye][slot]
  private var lastSequence: [UInt64] = [0, 0]
  private var pending: MTLCommandBuffer?
  private var displayLink: CADisplayLink?
  private var prepared = false
  private var shown = false
  private var frames = 0

  func prepare() async throws {
    guard !prepared else { return }
    guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
      throw Self.failure("Metal is unavailable.")
    }
    self.device = queue.device
    self.queue = queue
    // The engine's IOSurfaces as sRGB textures: the engine writes display (gamma-encoded) values, and
    // the sRGB LowLevelTexture / material decode them the same way, so no conversion is needed.
    for eye in 0..<2 {
      var textures: [MTLTexture] = []
      for slot in 0..<Self.slots {
        guard let surface = GVStereoEngine.surface(forEye: eye, slot: slot) else {
          throw Self.failure("The engine's eye image \(eye)/\(slot) is missing.")
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
          pixelFormat: .bgra8Unorm_srgb, width: Self.width, height: Self.height, mipmapped: false)
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor, iosurface: surface, plane: 0) else {
          throw Self.failure("Metal could not wrap the engine's eye image \(eye)/\(slot).")
        }
        textures.append(texture)
      }
      eyes.append(textures)
      colors.append(try LowLevelTexture(descriptor: .init(
        pixelFormat: .bgra8Unorm_srgb, width: Self.width, height: Self.height,
        depth: 1, mipmapLevelCount: 1, textureUsage: [.shaderRead, .renderTarget])))
    }
    var material = try await ShaderGraphMaterial(named: "/Root/Material", from: "NativeStereo", in: .main)
    try material.setParameter(name: "leftEye", value: .textureResource(try await TextureResource(from: colors[0])))
    try material.setParameter(name: "rightEye", value: .textureResource(try await TextureResource(from: colors[1])))
    screen.model = ModelComponent(mesh: .generatePlane(width: 1, height: Self.aspect), materials: [material])
    screen.isEnabled = false  // never show uninitialized texture contents
    prepared = true
  }

  /// Keep the game's 16:9 framing; extra window space is letterboxed.
  func fit(width: Float, height: Float) {
    let fit = max(0.001, min(width, height / Self.aspect))
    screen.scale = SIMD3<Float>(repeating: fit)
  }

  func start() {
    guard prepared, displayLink == nil else { return }
    let link = CADisplayLink(target: self, selector: #selector(tick))
    link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 90, preferred: 60)
    link.add(to: .main, forMode: .common)
    displayLink = link
  }

  func stop() {
    displayLink?.invalidate()
    displayLink = nil
    pending?.waitUntilCompleted()
    pending = nil
  }

  @objc private func tick() {
    if let pending, pending.status != .completed && pending.status != .error { return }
    if let pending, pending.status == .error {
      errorMessage = pending.error?.localizedDescription ?? "The stereo copy failed."
      stop()
      return
    }
    guard GVStereoEngine.status == 1, let queue else { return }
    // Both eyes are copied together once the right eye (rendered last) has a new frame, so the pair
    // belongs to the same game frame.
    var rightSequence: UInt64 = 0
    let rightSlot = GVStereoEngine.latestSlot(forEye: 1, sequence: &rightSequence)
    guard rightSlot >= 0, rightSequence != lastSequence[1] else { return }
    var leftSequence: UInt64 = 0
    let leftSlot = GVStereoEngine.latestSlot(forEye: 0, sequence: &leftSequence)
    guard leftSlot >= 0, let commandBuffer = queue.makeCommandBuffer() else { return }
    lastSequence = [leftSequence, rightSequence]
    let slots = [leftSlot, rightSlot]
    for eye in 0..<2 {
      let destination = colors[eye].replace(using: commandBuffer)
      guard let blit = commandBuffer.makeBlitCommandEncoder() else { continue }
      blit.copy(from: eyes[eye][slots[eye]], to: destination)
      blit.endEncoding()
    }
    commandBuffer.commit()
    pending = commandBuffer
    frames += 1
    if !shown {
      shown = true
      screen.isEnabled = true
    }
  }

  private static func failure(_ message: String) -> NSError {
    NSError(domain: "GalaxyVisionStereo", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }
}

struct GVStereoView: View {
  @StateObject private var renderer = GVStereoRenderer()
  @Environment(\.physicalMetrics) private var physicalMetrics
  let onError: (String) -> Void

  var body: some View {
    GeometryReader3D { geometry in
      let w = Float(physicalMetrics.convert(geometry.size.width, to: .meters))
      let h = Float(physicalMetrics.convert(geometry.size.height, to: .meters))
      RealityView { content in
        content.add(renderer.screen)
        renderer.fit(width: w, height: h)
      } update: { _ in
        renderer.fit(width: w, height: h)
      }
      .background(.black)
    }
    .background(.black)
    .task {
      do {
        try await renderer.prepare()
        try Task.checkCancellation()
        renderer.start()
      } catch is CancellationError {
        renderer.stop()
      } catch {
        renderer.stop()
        onError(error.localizedDescription)
      }
    }
    .onChange(of: renderer.errorMessage) { _, message in
      if let message { onError(message) }
    }
    .onDisappear { renderer.stop() }
  }
}

@objc(GVStereoFactory)
final class GVStereoFactory: NSObject {
  /// The stereo screen, to be added as a child of the game window's view controller.
  @objc static func makeViewController(onError: @escaping (String) -> Void) -> UIViewController {
    let host = UIHostingController(rootView: GVStereoView(onError: onError))
    host.view.backgroundColor = .black
    return host
  }
}
