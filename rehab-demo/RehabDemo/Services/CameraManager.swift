import AVFoundation
import UIKit

enum CameraFeed {
  case rear
}

/// Prefers Apple's calibrated rear Dual Wide device (wide + ultrawide).
/// The two physical cameras produce a synchronized disparity/depth map that
/// can lift third-party YOLO landmarks into camera-space 3D coordinates.
final class CameraManager: NSObject, ObservableObject {
  let session = AVCaptureSession()

  @Published private(set) var isReady = false
  @Published private(set) var isDualCameraActive = false
  @Published private(set) var statusText = "正在准备双后摄"
  @Published var errorMessage: String?

  var onStereoFrame: ((CMSampleBuffer, AVDepthData) -> Void)?
  var onSingleFrame: ((CMSampleBuffer) -> Void)?

  private let videoOutput = AVCaptureVideoDataOutput()
  private let depthOutput = AVCaptureDepthDataOutput()
  private let sessionQueue = DispatchQueue(label: "rehab.camera.session")
  private var synchronizer: AVCaptureDataOutputSynchronizer?
  private var videoPort: AVCaptureInput.Port?
  private var stereoConfigured = false
  private var selectedVideoDimensions = CMVideoDimensions()
  private var selectedDepthDimensions = CMVideoDimensions()
  private weak var previewLayer: AVCaptureVideoPreviewLayer?

  override init() {
    super.init()
    requestAccessAndConfigure()
  }

  func start() {
    sessionQueue.async { [weak self] in
      guard let self, !self.session.isRunning else { return }
      self.session.startRunning()
      DispatchQueue.main.async { self.isReady = true }
    }
  }

  func stop() {
    sessionQueue.async { [weak self] in
      guard let self, self.session.isRunning else { return }
      self.session.stopRunning()
      DispatchQueue.main.async { self.isReady = false }
    }
  }

  func attachPreviewLayer(
    _ layer: AVCaptureVideoPreviewLayer,
    feed: CameraFeed
  ) {
    sessionQueue.async { [weak self, weak layer] in
      guard let self, let layer else { return }
      self.previewLayer = layer
      self.session.beginConfiguration()
      self.connectPreviewIfPossible(layer)
      self.session.commitConfiguration()
    }
  }

  private func requestAccessAndConfigure() {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      configure()
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
        if granted {
          self?.configure()
        } else {
          self?.publishError("需要摄像头权限才能开始康复评估")
        }
      }
    default:
      publishError("请在“设置”中允许 Rehab Motion 使用摄像头")
    }
  }

  private func configure() {
    sessionQueue.async { [weak self] in
      guard let self else { return }
      if self.configureStereoDepthCamera() {
        self.finishConfiguration(stereo: true)
      } else if self.configureSingleCamera() {
        self.finishConfiguration(stereo: false)
      }
    }
  }

  /// `builtInDualWideCamera` is a calibrated virtual device backed by the
  /// physical rear wide and ultrawide cameras. AVFoundation computes disparity
  /// from both views and attaches camera calibration data.
  private func configureStereoDepthCamera() -> Bool {
    guard
      let camera = AVCaptureDevice.default(
        .builtInDualWideCamera,
        for: .video,
        position: .back
      )
    else {
      return false
    }

    session.beginConfiguration()
    defer { session.commitConfiguration() }
    clearSessionConfiguration()
    session.sessionPreset = .inputPriority

    do {
      try selectStereoFormat(for: camera)
      let input = try AVCaptureDeviceInput(device: camera)
      guard session.canAddInput(input) else { return false }
      session.addInput(input)

      configureVideoOutput()
      guard session.canAddOutput(videoOutput),
        session.canAddOutput(depthOutput)
      else {
        return false
      }
      session.addOutput(videoOutput)
      session.addOutput(depthOutput)
      depthOutput.isFilteringEnabled = true
      depthOutput.alwaysDiscardsLateDepthData = true

      if let connection = videoOutput.connection(with: .video) {
        configureConnection(connection)
        if connection.isCameraIntrinsicMatrixDeliverySupported {
          connection.isCameraIntrinsicMatrixDeliveryEnabled = true
        }
      }
      if let connection = depthOutput.connection(with: .depthData) {
        configureConnection(connection)
      }

      videoPort = input.ports.first(where: { $0.mediaType == .video })
      let synchronizer = AVCaptureDataOutputSynchronizer(
        dataOutputs: [videoOutput, depthOutput]
      )
      synchronizer.setDelegate(self, queue: sessionQueue)
      self.synchronizer = synchronizer
      return true
    } catch {
      DispatchQueue.main.async {
        self.statusText = "双后摄深度不可用，正在降级"
      }
      return false
    }
  }

  private func configureSingleCamera() -> Bool {
    guard
      let camera = AVCaptureDevice.default(
        .builtInWideAngleCamera,
        for: .video,
        position: .back
      )
    else {
      publishError("未检测到后置摄像头")
      return false
    }

    session.beginConfiguration()
    defer { session.commitConfiguration() }
    clearSessionConfiguration()
    session.sessionPreset = .high

    do {
      let input = try AVCaptureDeviceInput(device: camera)
      guard session.canAddInput(input) else {
        publishError("无法连接后置摄像头")
        return false
      }
      session.addInput(input)

      configureVideoOutput()
      videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
      guard session.canAddOutput(videoOutput) else {
        publishError("无法读取摄像头画面")
        return false
      }
      session.addOutput(videoOutput)
      if let connection = videoOutput.connection(with: .video) {
        configureConnection(connection)
      }
      videoPort = input.ports.first(where: { $0.mediaType == .video })
      return true
    } catch {
      publishError(error.localizedDescription)
      return false
    }
  }

  private func finishConfiguration(stereo: Bool) {
    stereoConfigured = stereo
    if let previewLayer {
      connectPreviewIfPossible(previewLayer)
    }
    session.startRunning()
    print(
      "[RehabCamera] stereo=\(stereo) video=\(selectedVideoDimensions.width)x\(selectedVideoDimensions.height) depth=\(selectedDepthDimensions.width)x\(selectedDepthDimensions.height)"
    )

    DispatchQueue.main.async {
      self.isDualCameraActive = stereo
      self.isReady = true
      self.statusText =
        stereo
        ? "后置广角 + 超广角立体深度"
        : "单后摄兼容模式 · 无深度"
    }
  }

  private func configureVideoOutput() {
    videoOutput.alwaysDiscardsLateVideoFrames = true
    videoOutput.videoSettings = [
      kCVPixelBufferPixelFormatTypeKey as String:
        kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
    ]
  }

  private func configureConnection(_ connection: AVCaptureConnection) {
    if connection.isVideoRotationAngleSupported(90) {
      connection.videoRotationAngle = 90
    }
    if connection.isVideoMirroringSupported {
      connection.automaticallyAdjustsVideoMirroring = false
      connection.isVideoMirrored = false
    }
  }

  private func selectStereoFormat(for device: AVCaptureDevice) throws {
    let depthCapable = device.formats.filter { format in
      let dimensions = CMVideoFormatDescriptionGetDimensions(
        format.formatDescription
      )
      return dimensions.width > 0
        && dimensions.height > 0
        && !format.supportedDepthDataFormats.isEmpty
        && format.videoSupportedFrameRateRanges.contains {
          $0.minFrameRate <= 30 && $0.maxFrameRate >= 30
        }
    }

    let preferred = depthCapable.filter { format in
      let dimensions = CMVideoFormatDescriptionGetDimensions(
        format.formatDescription
      )
      return dimensions.width <= 1920 && dimensions.height <= 1080
    }
    let candidates = preferred.isEmpty ? depthCapable : preferred
    let targetArea = 1920 * 1080
    guard
      let format = candidates.min(by: { lhs, rhs in
        let left = CMVideoFormatDescriptionGetDimensions(lhs.formatDescription)
        let right = CMVideoFormatDescriptionGetDimensions(rhs.formatDescription)
        return
          abs(Int(left.width * left.height) - targetArea)
          < abs(Int(right.width * right.height) - targetArea)
      })
    else {
      throw CameraError.noStereoDepthFormat
    }

    let depthCandidates = format.supportedDepthDataFormats.filter {
      let subtype = CMFormatDescriptionGetMediaSubType($0.formatDescription)
      return subtype == kCVPixelFormatType_DepthFloat16
        || subtype == kCVPixelFormatType_DepthFloat32
        || subtype == kCVPixelFormatType_DisparityFloat16
        || subtype == kCVPixelFormatType_DisparityFloat32
    }
    guard
      let depthFormat = depthCandidates.max(by: { lhs, rhs in
        let left = CMVideoFormatDescriptionGetDimensions(lhs.formatDescription)
        let right = CMVideoFormatDescriptionGetDimensions(rhs.formatDescription)
        return left.width * left.height < right.width * right.height
      })
    else {
      throw CameraError.noStereoDepthFormat
    }

    try device.lockForConfiguration()
    device.activeFormat = format
    device.activeDepthDataFormat = depthFormat
    selectedVideoDimensions = CMVideoFormatDescriptionGetDimensions(
      format.formatDescription
    )
    selectedDepthDimensions = CMVideoFormatDescriptionGetDimensions(
      depthFormat.formatDescription
    )
    let duration = CMTime(value: 1, timescale: 30)
    device.activeVideoMinFrameDuration = duration
    device.activeVideoMaxFrameDuration = duration
    device.unlockForConfiguration()
  }

  private func connectPreviewIfPossible(_ layer: AVCaptureVideoPreviewLayer) {
    guard layer.connection == nil, let videoPort else { return }
    let connection = AVCaptureConnection(
      inputPort: videoPort,
      videoPreviewLayer: layer
    )
    configureConnection(connection)
    guard session.canAddConnection(connection) else { return }
    session.addConnection(connection)
  }

  private func clearSessionConfiguration() {
    synchronizer?.setDelegate(nil, queue: nil)
    synchronizer = nil
    videoOutput.setSampleBufferDelegate(nil, queue: nil)
    depthOutput.setDelegate(nil, callbackQueue: nil)
    for connection in session.connections {
      session.removeConnection(connection)
    }
    for output in session.outputs {
      session.removeOutput(output)
    }
    for input in session.inputs {
      session.removeInput(input)
    }
    videoPort = nil
  }

  private func publishError(_ message: String) {
    DispatchQueue.main.async {
      self.errorMessage = message
      self.statusText = "摄像头不可用"
    }
  }

  enum CameraError: LocalizedError {
    case noStereoDepthFormat

    var errorDescription: String? {
      "当前双后摄没有可持续运行的深度格式"
    }
  }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard !stereoConfigured else { return }
    onSingleFrame?(sampleBuffer)
  }
}

extension CameraManager: AVCaptureDataOutputSynchronizerDelegate {
  func dataOutputSynchronizer(
    _ synchronizer: AVCaptureDataOutputSynchronizer,
    didOutput synchronizedDataCollection:
      AVCaptureSynchronizedDataCollection
  ) {
    guard
      let videoData = synchronizedDataCollection.synchronizedData(
        for: videoOutput
      ) as? AVCaptureSynchronizedSampleBufferData,
      let depthData = synchronizedDataCollection.synchronizedData(
        for: depthOutput
      ) as? AVCaptureSynchronizedDepthData,
      !videoData.sampleBufferWasDropped,
      !depthData.depthDataWasDropped
    else {
      return
    }

    onStereoFrame?(videoData.sampleBuffer, depthData.depthData)
  }
}
