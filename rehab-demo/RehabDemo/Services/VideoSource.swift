import AVFoundation
import UIKit

/// Reads video frames from a file URL; publishes the current frame as UIImage
/// and forwards CMSampleBuffer to the signal-capture callback.
@MainActor
final class VideoSource: ObservableObject {
  @Published var currentImage: UIImage?
  @Published var isPlaying = false
  @Published var progress: Double = 0
  @Published var isLoaded = false

  var onFrame: ((CMSampleBuffer) -> Void)?

  private var reader: AVAssetReader?
  private var output: AVAssetReaderTrackOutput?
  private var timer: Timer?
  private var frameIndex = 0
  private var totalFrames = 0
  private var fps: Float = 30
  private var sourceURL: URL?
  private let imageContext = CIContext(options: [.cacheIntermediates: false])

  func load(url: URL) {
    stop()
    sourceURL = url
    Task { [weak self] in
      await self?.prepareReader(url: url)
    }
  }

  private func prepareReader(url: URL) async {
    let asset = AVURLAsset(url: url)
    guard
      let track = try? await asset.loadTracks(withMediaType: .video).first,
      let nominalFrameRate = try? await track.load(.nominalFrameRate),
      let duration = try? await asset.load(.duration)
    else { return }
    fps = nominalFrameRate > 0 ? nominalFrameRate : 30
    totalFrames = Int(CMTimeGetSeconds(duration) * Float64(fps))

    let settings: [String: Any] = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]
    output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)

    reader = try? AVAssetReader(asset: asset)
    guard let reader, let output else { return }
    guard reader.canAdd(output) else { return }
    reader.add(output)
    reader.startReading()
    isLoaded = true
    frameIndex = 0
    progress = 0
    readNext()
  }

  func play() {
    if progress >= 0.999, let sourceURL {
      reader?.cancelReading()
      reader = nil
      output = nil
      Task { [weak self] in
        guard let self else { return }
        await self.prepareReader(url: sourceURL)
        self.startPlaybackTimer()
      }
      return
    }
    guard isLoaded else { return }
    startPlaybackTimer()
  }

  private func startPlaybackTimer() {
    isPlaying = true
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: 1.0 / Double(fps), repeats: true) {
      [weak self] _ in
      Task { @MainActor in
        self?.readNext()
      }
    }
  }

  func pause() {
    isPlaying = false
    timer?.invalidate()
    timer = nil
  }

  func stop() {
    pause()
    reader?.cancelReading()
    reader = nil
    output = nil
    isLoaded = false
    currentImage = nil
    progress = 0
    sourceURL = nil
  }

  private func readNext() {
    guard let output, let sbuf = output.copyNextSampleBuffer() else {
      pause()
      return
    }
    onFrame?(sbuf)
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sbuf) else { return }
    let ci = CIImage(cvPixelBuffer: pixelBuffer)
    guard let cg = imageContext.createCGImage(ci, from: ci.extent) else { return }
    DispatchQueue.main.async {
      self.currentImage = UIImage(cgImage: cg)
      self.frameIndex += 1
      if self.totalFrames > 0 {
        self.progress = Double(self.frameIndex) / Double(self.totalFrames)
      }
    }
  }
}
