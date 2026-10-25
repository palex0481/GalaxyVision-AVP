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
import MetalFX

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
  // Sharp upscaling (MetalFX): the same IOSurfaces as plain bgra8Unorm (the data is already display-encoded, so the
  // scaler runs in its perceptual mode on non-sRGB formats), per eye a private input of the picture's size, a
  // scaler and a private 1920x1080 output; the output is copied through an sRGB view into the LowLevelTexture.
  private var rawEyes: [[MTLTexture]] = []
  private var sharpOutputs: [MTLTexture] = []
  private var sharpOutputViews: [MTLTexture] = []
  private var sharpInputs: [MTLTexture?] = [nil, nil]
  private var sharpScalers: [MTLFXSpatialScaler?] = [nil, nil]
  private var sharpSize = (width: 0, height: 0)
  private var lastSequence: [UInt64] = [0, 0]
  private var pending: MTLCommandBuffer?
  private var displayLink: CADisplayLink?
  private var prepared = false
  private var shown = false
  private var frames = 0
  // Timing (the trace log): GPU time of the copy / scaler command buffer and how many pairs reach the display.
  private let timing = GVStereoTiming()

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
      // MetalFX needs raw (non-sRGB) views of the same memory; a failure here only disables sharp upscaling.
      var raw: [MTLTexture] = []
      for slot in 0..<Self.slots {
        guard let surface = GVStereoEngine.surface(forEye: eye, slot: slot) else { break }
        let rawDescriptor = MTLTextureDescriptor.texture2DDescriptor(
          pixelFormat: .bgra8Unorm, width: Self.width, height: Self.height, mipmapped: false)
        rawDescriptor.usage = .shaderRead
        rawDescriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: rawDescriptor, iosurface: surface, plane: 0) else { break }
        raw.append(texture)
      }
      rawEyes.append(raw)
      colors.append(try LowLevelTexture(descriptor: .init(
        pixelFormat: .bgra8Unorm_srgb, width: Self.width, height: Self.height,
        depth: 1, mipmapLevelCount: 1, textureUsage: [.shaderRead, .renderTarget])))
    }
    if !prepareSharp(device) { disableSharp("MetalFX is not available here, or its textures could not be made.") }
    var material = try await ShaderGraphMaterial(named: "/Root/Material", from: "NativeStereo", in: .main)
    try material.setParameter(name: "leftEye", value: .textureResource(try await TextureResource(from: colors[0])))
    try material.setParameter(name: "rightEye", value: .textureResource(try await TextureResource(from: colors[1])))
    screen.model = ModelComponent(mesh: .generatePlane(width: 1, height: Self.aspect), materials: [material])
    screen.isEnabled = false  // never show uninitialized texture contents
    prepared = true
  }

  /// The eye outputs for MetalFX (private bgra8Unorm, plus an sRGB view of each). False if MetalFX or the textures aren't available.
  private func prepareSharp(_ device: MTLDevice) -> Bool {
    guard MTLFXSpatialScalerDescriptor.supportsDevice(device), rawEyes.count == 2,
          rawEyes.allSatisfy({ $0.count == Self.slots }) else { return false }
    for _ in 0..<2 {
      let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm, width: Self.width, height: Self.height, mipmapped: false)
      // renderTarget and shaderWrite cover what a MetalFX scaler asks of its output (checked again when it is created).
      descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget, .pixelFormatView]
      descriptor.storageMode = .private
      guard let output = device.makeTexture(descriptor: descriptor),
            let view = output.makeTextureView(pixelFormat: .bgra8Unorm_srgb) else { return false }
      sharpOutputs.append(output)
      sharpOutputViews.append(view)
    }
    return true
  }

  private func disableSharp(_ reason: String) {
    guard !GVStereoEngine.sharpFailed else { return }
    fputs("GalaxyVision stereo: sharp upscaling (MetalFX) off: \(reason)\n", stderr)
    GVStereoEngine.sharpFailed = true
    GVStereoEngine.sharpActive = false
    GVStereoEngine.applySavedSettings()  // the engine goes back to scaling across the whole eye image
  }

  /// Makes the per-eye scalers and inputs for a picture size (once per size). False if MetalFX can't do it.
  private func configureSharp(width: Int, height: Int) -> Bool {
    if sharpSize == (width, height), sharpScalers[0] != nil, sharpScalers[1] != nil { return true }
    guard let device, sharpOutputs.count == 2 else { return false }
    let descriptor = MTLFXSpatialScalerDescriptor()
    descriptor.colorTextureFormat = .bgra8Unorm
    descriptor.outputTextureFormat = .bgra8Unorm
    descriptor.inputWidth = width
    descriptor.inputHeight = height
    descriptor.outputWidth = Self.width
    descriptor.outputHeight = Self.height
    descriptor.colorProcessingMode = .perceptual
    var scalers: [MTLFXSpatialScaler?] = [nil, nil]
    var inputs: [MTLTexture?] = [nil, nil]
    for eye in 0..<2 {
      guard let scaler = descriptor.makeSpatialScaler(device: device) else { return false }
      guard scaler.outputTextureUsage.isSubset(of: sharpOutputs[eye].usage) else { return false }
      let input = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
      input.usage = scaler.colorTextureUsage.union(.shaderRead)
      input.storageMode = .private
      guard let texture = device.makeTexture(descriptor: input) else { return false }
      scalers[eye] = scaler
      inputs[eye] = texture
    }
    sharpScalers = scalers
    sharpInputs = inputs
    sharpSize = (width, height)
    return true
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
    if UserDefaults.standard.bool(forKey: GVSBSRecorder.autoStartKey), !GVSBSRecorder.shared.isRecording {
      GVSBSRecorder.shared.start()
    }
  }

  func stop() {
    GVStereoEngine.sharpActive = false
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
    let slots = [leftSlot, rightSlot]
    // The pictures' size: the whole 1920x1080 image (plain path), or a smaller top-left rectangle when the engine
    // draws at the render size for MetalFX. Both eyes of a pair are drawn together with the same size.
    var pictureWidth = 0, pictureHeight = 0
    var otherWidth = 0, otherHeight = 0
    _ = GVStereoEngine.size(forEye: 1, slot: rightSlot, width: &pictureWidth, height: &pictureHeight)
    _ = GVStereoEngine.size(forEye: 0, slot: leftSlot, width: &otherWidth, height: &otherHeight)
    let scaled = pictureWidth < Self.width || pictureHeight < Self.height
    if scaled {
      // A picture that is not full size can only be shown through MetalFX; otherwise wait for the plain path's pictures.
      guard otherWidth == pictureWidth, otherHeight == pictureHeight,
            pictureWidth > 0, pictureHeight > 0, !GVStereoEngine.sharpFailed else {
        if GVStereoEngine.sharpFailed { lastSequence = [leftSequence, rightSequence] }
        return
      }
      if !configureSharp(width: pictureWidth, height: pictureHeight) {
        disableSharp("the scaler could not be created for \(pictureWidth)x\(pictureHeight).")
        lastSequence = [leftSequence, rightSequence]
        return
      }
    }
    lastSequence = [leftSequence, rightSequence]
    for eye in 0..<2 {
      let destination = colors[eye].replace(using: commandBuffer)
      if scaled, let scaler = sharpScalers[eye], let input = sharpInputs[eye] {
        // 1. the picture's rectangle into the scaler's private input, 2. MetalFX up to 1920x1080,
        // 3. the result (through an sRGB view) into the RealityKit texture.
        if let crop = commandBuffer.makeBlitCommandEncoder() {
          crop.copy(from: rawEyes[eye][slots[eye]], sourceSlice: 0, sourceLevel: 0,
                    sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                    sourceSize: MTLSize(width: pictureWidth, height: pictureHeight, depth: 1),
                    to: input, destinationSlice: 0, destinationLevel: 0,
                    destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
          crop.endEncoding()
        }
        scaler.colorTexture = input
        scaler.inputContentWidth = pictureWidth
        scaler.inputContentHeight = pictureHeight
        scaler.outputTexture = sharpOutputs[eye]
        scaler.encode(commandBuffer: commandBuffer)
        if let blit = commandBuffer.makeBlitCommandEncoder() {
          blit.copy(from: sharpOutputViews[eye], to: destination)
          blit.endEncoding()
        }
      } else if let blit = commandBuffer.makeBlitCommandEncoder() {
        blit.copy(from: eyes[eye][slots[eye]], to: destination)
        blit.endEncoding()
      }
    }
    // Side-by-side 3D recorder: the same pair, full size (MetalFX output when scaled, else the raw eye image).
    if GVSBSRecorder.shared.isRecording {
      if scaled, sharpOutputs.count == 2 {
        GVSBSRecorder.shared.encodeFrame(commandBuffer: commandBuffer, left: sharpOutputs[0], right: sharpOutputs[1])
      } else if !scaled, rawEyes.count == 2, rawEyes.allSatisfy({ $0.count == Self.slots }) {
        GVSBSRecorder.shared.encodeFrame(commandBuffer: commandBuffer, left: rawEyes[0][slots[0]], right: rawEyes[1][slots[1]])
      }
    }
    if GVStereoEngine.sharpActive != scaled { GVStereoEngine.sharpActive = scaled }
    let timing = self.timing
    commandBuffer.addCompletedHandler { buffer in
      timing.add(gpuMs: (buffer.gpuEndTime - buffer.gpuStartTime) * 1000.0, scaled: scaled)
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

/// GPU time of the host's copy (and MetalFX) command buffer, printed to the trace log every 120 pairs.
final class GVStereoTiming: @unchecked Sendable {
  private let lock = NSLock()
  private var total = 0.0, peak = 0.0, count = 0
  private var start = CACurrentMediaTime()

  func add(gpuMs: Double, scaled: Bool) {
    lock.lock()
    total += gpuMs
    peak = max(peak, gpuMs)
    count += 1
    guard count == 120 else { lock.unlock(); return }
    let now = CACurrentMediaTime()
    let line = String(format: "GalaxyVision stereo host: %d pairs shown in %.2f s (%.1f per second), copy%@ GPU time mean %.2f ms, max %.2f ms\n",
                      count, now - start, Double(count) / max(0.001, now - start), scaled ? "+MetalFX" : "", total / Double(count), peak)
    total = 0; peak = 0; count = 0; start = now
    lock.unlock()
    fputs(line, stderr)
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
    .overlay(alignment: .topLeading) { GVRecordBadge().padding(16) }
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

/// Red "REC" badge on the window while the side-by-side recorder runs (not part of the recorded eye images).
struct GVRecordBadge: View {
  @State private var recording = GVSBSRecorder.shared.isRecording
  var body: some View {
    Group {
      if recording {
        Label("REC", systemImage: "record.circle.fill").font(.headline).foregroundStyle(.red)
          .padding(.horizontal, 10).padding(.vertical, 6).background(.black.opacity(0.6), in: Capsule())
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: GVSBSRecorder.stateChanged)) { _ in
      recording = GVSBSRecorder.shared.isRecording
    }
  }
}
