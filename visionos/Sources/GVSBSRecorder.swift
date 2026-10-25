// SPDX-License-Identifier: GPL-3.0-or-later
// side-by-side 3D video recorder (Stereoscopic window only).
//
// Each eye pair the stereo window shows is also blitted (GPU, same command buffer as the window's copy) into a
// 3840x1080 BGRA pixel buffer, left eye on the left, and appended to an AVAssetWriter (H.264 MP4) on a background
// queue together with the game's audio (GVAudioTap, AAC). The file goes to Documents (Files > On My Apple Vision Pro >
// GalaxyVision). After writing, a Spherical Video V2 `st3d` box (stereo mode left-right) is added to the video
// sample entry, so YouTube treats the upload as 3D side-by-side.
import AVFoundation
import CoreMedia
import CoreVideo
import Metal
import QuartzCore
import UIKit

@objc(GVSBSRecorder)
final class GVSBSRecorder: NSObject, @unchecked Sendable {
  @objc static let shared = GVSBSRecorder()
  @objc static let stateChanged = Notification.Name("GVSBSRecorderStateChanged")
  static let eyeWidth = 1920
  static let eyeHeight = 1080

  private let queue = DispatchQueue(label: "GalaxyVision.sbs-recorder")
  private let lock = NSLock()
  // Guarded by `lock` (read from the main thread and the audio thread).
  private var _recording = false
  private var _lastMessage = "Not recording."
  private var _pool: CVPixelBufferPool?
  // Writer state, only touched on `queue`.
  private var writer: AVAssetWriter?
  private var videoInput: AVAssetWriterInput?
  private var audioInput: AVAssetWriterInput?
  private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
  private var url: URL?
  private var sessionStart: CMTime?
  private var lastVideoTime = CMTime.invalid
  private var audioFormat: CMAudioFormatDescription?
  private var audioFormatKey: [UInt32] = []
  private var audioNextTime: CMTime?
  private var videoFrames = 0
  private var droppedFrames = 0
  private var audioWritable = false
  private var textureCache: CVMetalTextureCache?
  private var started = CACurrentMediaTime()

  override init() {
    super.init()
    // Finish the file when the app goes to the background (a killed app leaves an unplayable file).
    NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { [weak self] _ in
      guard let self, self.isRecording else { return }
      let task = UIApplication.shared.beginBackgroundTask(withName: "GalaxyVision recording")
      self.stop()
      self.queue.async { UIApplication.shared.endBackgroundTask(task) }
    }
  }

  @objc static let autoStartKey = "gv.sbsRecordAutoStart"

  @objc var isRecording: Bool { lock.lock(); defer { lock.unlock() }; return _recording }
  @objc var statusMessage: String { lock.lock(); defer { lock.unlock() }; return _lastMessage }

  private func setState(recording: Bool, message: String) {
    lock.lock(); _recording = recording; _lastMessage = message; lock.unlock()
    DispatchQueue.main.async { NotificationCenter.default.post(name: Self.stateChanged, object: nil) }
    fputs("GalaxyVision recorder: \(message)\n", stderr)
  }

  @objc func toggle() { isRecording ? stop() : start() }

  @objc func start() {
    queue.async { [self] in
      guard writer == nil else { return }
      guard GVStereoEngine.sessionStereo, !GVStereoEngine.flatOverride else {
        setState(recording: false, message: "Recording needs the Stereoscopic window in 3D.")
        return
      }
      do {
        try openWriter()
        setState(recording: true, message: "Recording \(url?.lastPathComponent ?? "")")
        GVAudioTap.setHandler { [weak self] data, bytes, format in
          guard let self else { return }
          let copy = Data(bytes: data, count: Int(bytes))
          let asbd = format.pointee
          let now = CACurrentMediaTime()
          self.queue.async { self.appendAudio(copy, format: asbd, hostTime: now) }
        }
      } catch {
        writer = nil
        setState(recording: false, message: "Could not start recording: \(error.localizedDescription)")
      }
    }
  }

  @objc func stop() {
    GVAudioTap.setHandler(nil)
    queue.async { [self] in
      guard let writer, let url else { return }
      let frames = videoFrames, dropped = droppedFrames
      self.writer = nil
      lock.lock(); _recording = false; _pool = nil; lock.unlock()
      guard sessionStart != nil else {
        writer.cancelWriting()
        try? FileManager.default.removeItem(at: url)
        setState(recording: false, message: "Stopped; no 3D frames arrived, nothing saved.")
        return
      }
      videoInput?.markAsFinished()
      audioInput?.markAsFinished()
      let end = lastVideoTime
      if end.isValid { writer.endSession(atSourceTime: end) }
      let done = DispatchSemaphore(value: 0)
      writer.finishWriting { done.signal() }
      done.wait()
      if writer.status == .completed {
        let tagged = Self.addStereoMetadata(url)
        setState(recording: false, message: "Saved \(url.lastPathComponent) (\(frames) frames\(dropped > 0 ? ", \(dropped) dropped" : "")\(tagged ? ", YouTube 3D tag" : ", no 3D tag")).")
      } else {
        setState(recording: false, message: "Saving failed: \(writer.error?.localizedDescription ?? "unknown error").")
      }
    }
  }

  private func openWriter() throws {
    let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
    let url = documents.appendingPathComponent("GalaxyVision 3D SBS \(formatter.string(from: Date())).mp4")
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    writer.shouldOptimizeForNetworkUse = false  // moov at the end: adding st3d later moves no sample data
    let width = Self.eyeWidth * 2, height = Self.eyeHeight
    let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: width,
      AVVideoHeightKey: height,
      AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: 45_000_000,
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
        AVVideoExpectedSourceFrameRateKey: 60,
        AVVideoMaxKeyFrameIntervalKey: 120,
        AVVideoAllowFrameReorderingKey: false,
      ] as [String: Any],
    ])
    video.expectsMediaDataInRealTime = true
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
      kCVPixelBufferWidthKey as String: width,
      kCVPixelBufferHeightKey as String: height,
      kCVPixelBufferMetalCompatibilityKey as String: true,
      kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
    ])
    guard writer.canAdd(video) else { throw Self.failure("The video track could not be added.") }
    writer.add(video)
    var audio: AVAssetWriterInput?
    if GVAudioTap.installed {
      let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 48_000,
        AVNumberOfChannelsKey: 2,
        AVEncoderBitRateKey: 256_000,
      ])
      input.expectsMediaDataInRealTime = true
      if writer.canAdd(input) { writer.add(input); audio = input }
    }
    guard writer.startWriting() else { throw writer.error ?? Self.failure("The writer did not start.") }
    self.writer = writer
    self.url = url
    videoInput = video
    audioInput = audio
    self.adaptor = adaptor
    lock.lock(); _pool = adaptor.pixelBufferPool; lock.unlock()
    sessionStart = nil
    lastVideoTime = .invalid
    audioNextTime = nil
    videoFrames = 0
    droppedFrames = 0
    started = CACurrentMediaTime()
  }

  // MARK: Video (main thread: encode the blit; writer queue: append)

  /// Adds the side-by-side copy of this eye pair to `commandBuffer`. `left` / `right` are full 1920x1080 bgra8Unorm
  /// (non-sRGB, display-encoded) eye images.
  func encodeFrame(commandBuffer: MTLCommandBuffer, left: MTLTexture, right: MTLTexture) {
    guard isRecording else { return }
    let time = CMTime(seconds: CACurrentMediaTime(), preferredTimescale: 600_000)
    lock.lock(); let pool = _pool; lock.unlock()
    guard let pool else { return }
    let device = commandBuffer.device
    if textureCache == nil { CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache) }
    guard let cache = textureCache else { return }
    var pixelBuffer: CVPixelBuffer?
    guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer) == kCVReturnSuccess, let pixelBuffer else {
      queue.async { self.droppedFrames += 1 }
      return
    }
    var cvTexture: CVMetalTexture?
    guard CVMetalTextureCacheCreateTextureFromImage(nil, cache, pixelBuffer, nil, .bgra8Unorm, Self.eyeWidth * 2, Self.eyeHeight, 0, &cvTexture) == kCVReturnSuccess,
          let cvTexture, let target = CVMetalTextureGetTexture(cvTexture) else { return }
    guard left.width >= Self.eyeWidth, left.height >= Self.eyeHeight, right.width >= Self.eyeWidth,
          right.height >= Self.eyeHeight, let blit = commandBuffer.makeBlitCommandEncoder() else { return }
    for (eye, source) in [left, right].enumerated() {
      blit.copy(from: source, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                sourceSize: MTLSize(width: Self.eyeWidth, height: Self.eyeHeight, depth: 1),
                to: target, destinationSlice: 0, destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: eye * Self.eyeWidth, y: 0, z: 0))
    }
    blit.endEncoding()
    commandBuffer.addCompletedHandler { [self] buffer in
      _ = cvTexture  // keep the Metal view of the pixel buffer alive until the GPU is done
      guard buffer.status == .completed else { return }
      queue.async { self.appendVideo(pixelBuffer, time: time) }
    }
  }

  private func appendVideo(_ pixelBuffer: CVPixelBuffer, time: CMTime) {
    guard let writer, writer.status == .writing, let videoInput, let adaptor else { return }
    if sessionStart == nil {
      writer.startSession(atSourceTime: time)
      sessionStart = time
    }
    guard lastVideoTime.isValid == false || time > lastVideoTime else { return }
    guard videoInput.isReadyForMoreMediaData, adaptor.append(pixelBuffer, withPresentationTime: time) else {
      droppedFrames += 1
      return
    }
    lastVideoTime = time
    videoFrames += 1
  }

  // MARK: Audio (writer queue)

  private func appendAudio(_ data: Data, format asbd: AudioStreamBasicDescription, hostTime: CFTimeInterval) {
    guard let writer, writer.status == .writing, let audioInput, let sessionStart else { return }
    var asbd = asbd
    let key = [asbd.mFormatID, asbd.mFormatFlags, asbd.mBytesPerFrame, asbd.mChannelsPerFrame, UInt32(asbd.mSampleRate)]
    if audioFormat == nil || key != audioFormatKey {
      var description: CMAudioFormatDescription?
      guard CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0,
                                           magicCookie: nil, extensions: nil, formatDescriptionOut: &description) == noErr,
            let description else { return }
      audioFormat = description
      audioFormatKey = key
      audioNextTime = nil
    }
    guard let audioFormat, asbd.mBytesPerFrame > 0 else { return }
    let frames = data.count / Int(asbd.mBytesPerFrame)
    guard frames > 0 else { return }
    // Continuous timeline from the sample count; re-anchored to the clock if it drifts by more than 0.1 s.
    let clock = CMTime(seconds: hostTime, preferredTimescale: CMTimeScale(asbd.mSampleRate))
    var time = audioNextTime ?? clock
    if abs((time - clock).seconds) > 0.1 { time = clock }
    audioNextTime = time + CMTime(value: CMTimeValue(frames), timescale: CMTimeScale(asbd.mSampleRate))
    guard time >= sessionStart, audioInput.isReadyForMoreMediaData else { return }
    var block: CMBlockBuffer?
    guard CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: data.count, blockAllocator: nil,
                                             customBlockSource: nil, offsetToData: 0, dataLength: data.count, flags: 0,
                                             blockBufferOut: &block) == noErr, let block else { return }
    let copied = data.withUnsafeBytes { CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: data.count) }
    guard copied == noErr else { return }
    var sample: CMSampleBuffer?
    guard CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: block, formatDescription: audioFormat,
                                                               sampleCount: frames, presentationTimeStamp: time,
                                                               packetDescriptions: nil, sampleBufferOut: &sample) == noErr,
          let sample else { return }
    audioInput.append(sample)
  }

  // MARK: YouTube 3D metadata

  /// Inserts `st3d` (Spherical Video V2: version/flags 0, stereo_mode 2 = left-right) at the end of the video sample
  /// entry (avc1) and grows every parent box. The movie box is at the end of the file (no network optimisation),
  /// so the sample data and chunk offsets do not move.
  static func addStereoMetadata(_ url: URL) -> Bool {
    // Top-level boxes, read through a file handle (mdat can be several GB; only moov is loaded).
    guard let handle = try? FileHandle(forUpdating: url) else { return false }
    defer { try? handle.close() }
    guard let fileSize = try? handle.seekToEnd() else { return false }
    var at: UInt64 = 0
    var moovAt: UInt64?, moovSize: UInt64 = 0
    while at + 8 <= fileSize {
      try? handle.seek(toOffset: at)
      guard let header = try? handle.read(upToCount: 16), header.count >= 8 else { return false }
      var size = UInt64(header[0]) << 24 | UInt64(header[1]) << 16 | UInt64(header[2]) << 8 | UInt64(header[3])
      if size == 1, header.count >= 16 { size = header[8..<16].reduce(0) { $0 << 8 | UInt64($1) } }
      if size == 0 { size = fileSize - at }
      guard size >= 8 else { return false }
      if String(bytes: header[4..<8], encoding: .ascii) == "moov" { moovAt = at; moovSize = size }
      at += size
    }
    // The movie box must be the last box so that it can grow without moving anything else.
    guard let moovAt, moovAt + moovSize == fileSize, moovSize < 64 << 20 else { return false }
    try? handle.seek(toOffset: moovAt)
    guard var bytes = try? handle.read(upToCount: Int(moovSize)), bytes.count == Int(moovSize) else { return false }
    func u32(_ at: Int) -> Int { Int(bytes[at]) << 24 | Int(bytes[at + 1]) << 16 | Int(bytes[at + 2]) << 8 | Int(bytes[at + 3]) }
    func type(_ at: Int) -> String { String(bytes: bytes[at + 4..<at + 8], encoding: .ascii) ?? "" }
    func put32(_ value: Int, _ at: Int) {
      bytes[at] = UInt8((value >> 24) & 0xff); bytes[at + 1] = UInt8((value >> 16) & 0xff)
      bytes[at + 2] = UInt8((value >> 8) & 0xff); bytes[at + 3] = UInt8(value & 0xff)
    }
    func child(_ name: String, _ start: Int, _ end: Int) -> Int? {
      var at = start
      while at + 8 <= end {
        let size = u32(at)
        guard size >= 8, at + size <= end else { return nil }
        if type(at) == name { return at }
        at += size
      }
      return nil
    }
    let moov = 0
    var cursor = 8
    var path: [Int] = []
    while let trak = child("trak", cursor, u32(moov)) {
      cursor = trak + u32(trak)
      guard let mdia = child("mdia", trak + 8, trak + u32(trak)),
            let hdlr = child("hdlr", mdia + 8, mdia + u32(mdia)),
            String(bytes: bytes[hdlr + 16..<hdlr + 20], encoding: .ascii) == "vide",
            let minf = child("minf", mdia + 8, mdia + u32(mdia)),
            let stbl = child("stbl", minf + 8, minf + u32(minf)),
            let stsd = child("stsd", stbl + 8, stbl + u32(stbl)) else { continue }
      // stsd: header 8 + version/flags 4 + entry count 4, then the sample entries (visual entry header is 86 bytes).
      guard let entry = child("avc1", stsd + 16, stsd + u32(stsd)) ?? child("hvc1", stsd + 16, stsd + u32(stsd)) else { return false }
      if child("st3d", entry + 86, entry + u32(entry)) != nil { return true }
      path = [moov, trak, mdia, minf, stbl, stsd, entry]
      break
    }
    guard let entry = path.last else { return false }
    let st3d = Data([0, 0, 0, 13, 0x73, 0x74, 0x33, 0x64, 0, 0, 0, 0, 2])
    let insertAt = entry + u32(entry)
    for box in path { put32(u32(box) + st3d.count, box) }
    bytes.insert(contentsOf: st3d, at: insertAt)
    do {
      try handle.seek(toOffset: moovAt)
      try handle.write(contentsOf: bytes)
      try handle.synchronize()
    } catch { return false }
    return true
  }

  private static func failure(_ message: String) -> NSError {
    NSError(domain: "GalaxyVisionRecorder", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }
}
