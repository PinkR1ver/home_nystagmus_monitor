import AVFoundation
import Foundation
import UIKit

/// Coordinates three weighted third-party pipelines:
/// - YOLO11n Pose for the body, lifted into 3D by calibrated dual-rear depth.
/// - FCQ MobileNetV3 for head yaw/pitch/roll.
/// - The existing SwinUNet ONNX model for eye-gaze direction.
final class DualSignalCapture: ObservableObject {
  @Published private(set) var latestSignals: SignalFrame?
  @Published private(set) var depthPreviewImage: UIImage?
  @Published private(set) var modelStatus = "正在载入三模型"
  @Published private(set) var processingStatus = "等待人物进入画面"
  @Published private(set) var performanceText = "等待性能样本"
  @Published private(set) var recordedSampleCount = 0
  @Published private(set) var lastRecordingURL: URL?
  @Published private(set) var modelError: String?

  private enum Pipeline: Hashable {
    case body
    case head
    case gaze
    case depthPreview
  }

  private let bodyEstimator: YOLOPoseEstimator?
  private let headEstimator: HeadPoseEstimator?
  private let gazeEstimator = ONNXGazeEstimator()
  private let bodyQueue = DispatchQueue(
    label: "rehab.model.body",
    qos: .userInteractive
  )
  private let headQueue = DispatchQueue(
    label: "rehab.model.head",
    qos: .userInitiated
  )
  private let gazeQueue = DispatchQueue(
    label: "rehab.model.gaze",
    qos: .userInitiated
  )
  private let depthQueue = DispatchQueue(
    label: "rehab.depth.preview",
    qos: .utility
  )
  private let stateQueue = DispatchQueue(label: "rehab.model.state")

  private var latestBody: PoseDetection?
  private var latestProjectedLandmarks: [BodyLandmarkPoint] = []
  private var latestHead: HeadPoseEstimate?
  private var latestGaze: GazeEstimate?
  private var latestDepthCoverage = 0.0
  private var latestMedianDepth: Double?
  private var hasStereoDepth = false
  private var busy: Set<Pipeline> = []
  private var lastRun: [Pipeline: CFTimeInterval] = [:]
  private var latencyMilliseconds: [Pipeline: Double] = [:]
  private var lastPerformanceLog = 0.0
  private var lastBodyAttemptLog = 0.0
  private var isRecording = false
  private var recordingStartedAt: Date?
  private var recordedSamples: [RecordedSignalSample] = []
  private var lastRecordedAt: Date?

  init() {
    var loadedBody: YOLOPoseEstimator?
    var loadedHead: HeadPoseEstimator?
    var errors: [String] = []
    do {
      loadedBody = try YOLOPoseEstimator()
    } catch {
      errors.append(error.localizedDescription)
    }
    do {
      loadedHead = try HeadPoseEstimator()
    } catch {
      errors.append(error.localizedDescription)
    }

    bodyEstimator = loadedBody
    headEstimator = loadedHead
    if errors.isEmpty {
      modelStatus = "YOLO · FCQ · SwinUNet"
    } else {
      modelStatus = "部分模型不可用"
      modelError = errors.joined(separator: "；")
    }
  }

  func processStereoFrame(
    _ sampleBuffer: CMSampleBuffer,
    depthData: AVDepthData
  ) {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
      return
    }
    processBody(pixelBuffer: pixelBuffer, depthData: depthData)
    processAuxiliary(pixelBuffer: pixelBuffer)
    processDepthPreview(depthData)
  }

  func processSingleFrame(_ sampleBuffer: CMSampleBuffer) {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
      return
    }
    processBody(pixelBuffer: pixelBuffer, depthData: nil)
    processAuxiliary(pixelBuffer: pixelBuffer)
  }

  func startRecording() {
    stateQueue.async {
      self.recordedSamples.removeAll(keepingCapacity: true)
      self.recordingStartedAt = Date()
      self.lastRecordedAt = nil
      self.isRecording = true
      DispatchQueue.main.async {
        self.recordedSampleCount = 0
        self.lastRecordingURL = nil
      }
    }
  }

  func stopRecording(
    completion: @escaping (Result<URL, Error>) -> Void
  ) {
    stateQueue.async {
      self.isRecording = false
      let session = RecordedSignalSession(
        startedAt: self.recordingStartedAt ?? Date(),
        endedAt: Date(),
        models: "YOLO11n Pose + FCQ Head Pose + SwinUNet Gaze",
        samples: self.recordedSamples
      )

      do {
        let url = try self.write(session)
        DispatchQueue.main.async {
          self.lastRecordingURL = url
          completion(.success(url))
        }
      } catch {
        DispatchQueue.main.async {
          completion(.failure(error))
        }
      }
    }
  }

  private func processBody(
    pixelBuffer: CVPixelBuffer,
    depthData: AVDepthData?
  ) {
    guard let bodyEstimator, claim(.body, maximumFPS: 10) else { return }
    bodyQueue.async { [weak self] in
      guard let self else { return }
      let startedAt = CACurrentMediaTime()
      let result = try? bodyEstimator.predict(pixelBuffer: pixelBuffer)
      let projection = result.flatMap { detection in
        depthData.map {
          StereoDepthProjector.project(
            detection: detection,
            depthData: $0
          )
        }
      }

      self.stateQueue.async {
        self.latestBody = result
        self.latestProjectedLandmarks =
          projection?.landmarks ?? result?.landmarks ?? []
        self.latestDepthCoverage = projection?.coverage ?? 0
        self.latestMedianDepth = projection?.medianDepthMeters
        self.hasStereoDepth = projection != nil
        self.latencyMilliseconds[.body] =
          (CACurrentMediaTime() - startedAt) * 1_000
        let now = CACurrentMediaTime()
        if now - self.lastBodyAttemptLog >= 1 {
          self.lastBodyAttemptLog = now
          print(
            "[RehabBody] detected=\(result != nil) latency=\(Int((self.latencyMilliseconds[.body] ?? 0).rounded()))ms"
          )
        }
        if result == nil {
          self.latestHead = nil
          self.latestGaze = nil
        }
        self.busy.remove(.body)
        self.publishSignals()
      }
    }
  }

  private func processAuxiliary(pixelBuffer: CVPixelBuffer) {
    let detection = stateQueue.sync { latestBody }
    guard let detection,
      let faceRect = FaceCropGeometry.faceRect(for: detection)
    else {
      return
    }

    if let headEstimator, claim(.head, maximumFPS: 10) {
      headQueue.async { [weak self] in
        guard let self else { return }
        let startedAt = CACurrentMediaTime()
        let result = try? headEstimator.predict(
          pixelBuffer: pixelBuffer,
          faceRectTopLeft: faceRect
        )
        self.stateQueue.async {
          self.latestHead = result
          self.latencyMilliseconds[.head] =
            (CACurrentMediaTime() - startedAt) * 1_000
          self.busy.remove(.head)
          self.publishSignals()
        }
      }
    }

    if claim(.gaze, maximumFPS: 20) {
      gazeQueue.async { [weak self] in
        guard let self else { return }
        let startedAt = CACurrentMediaTime()
        let result: GazeEstimate?
        do {
          result = try self.gazeEstimator.predict(
            pixelBuffer: pixelBuffer,
            detection: detection
          )
        } catch {
          result = nil
          DispatchQueue.main.async {
            self.modelError = error.localizedDescription
          }
        }
        self.stateQueue.async {
          self.latestGaze = result
          self.latencyMilliseconds[.gaze] =
            (CACurrentMediaTime() - startedAt) * 1_000
          self.busy.remove(.gaze)
          self.publishSignals()
        }
      }
    }
  }

  private func processDepthPreview(_ depthData: AVDepthData) {
    guard claim(.depthPreview, maximumFPS: 6) else { return }
    depthQueue.async { [weak self] in
      guard let self else { return }
      let image = StereoDepthProjector.previewImage(from: depthData)
      self.stateQueue.async {
        self.busy.remove(.depthPreview)
      }
      if let image {
        DispatchQueue.main.async {
          self.depthPreviewImage = image
        }
      }
    }
  }

  private func claim(_ pipeline: Pipeline, maximumFPS: Double) -> Bool {
    stateQueue.sync {
      guard !busy.contains(pipeline) else { return false }
      let now = CACurrentMediaTime()
      guard now - (lastRun[pipeline] ?? 0) >= 1 / maximumFPS else {
        return false
      }
      busy.insert(pipeline)
      lastRun[pipeline] = now
      return true
    }
  }

  private func publishSignals() {
    guard let body = latestBody else {
      DispatchQueue.main.async {
        self.latestSignals = nil
        self.processingStatus = "等待人物进入画面"
      }
      return
    }

    let centerOffset = centerDisplacement(from: body)
    let signal = SignalFrame(
      timestamp: Date(),
      bodyLandmarks: latestProjectedLandmarks,
      headYaw: latestHead?.yaw,
      headPitch: latestHead?.pitch,
      headRoll: latestHead?.roll,
      eyeOpenness: latestGaze?.quality,
      gazeDirectionX: latestGaze?.yaw,
      gazeDirectionY: latestGaze?.pitch,
      comDisplacement: centerOffset,
      personConfidence: body.confidence,
      stereoDepthCoverage: latestDepthCoverage,
      medianBodyDepthMeters: latestMedianDepth,
      hasStereoBodySignal: hasStereoDepth && latestDepthCoverage >= 0.25,
      headPoseQuality: latestHead?.quality,
      gazeQuality: latestGaze?.quality,
      modelName: "YOLO11n Pose + FCQ Head Pose + SwinUNet Gaze"
    )
    recordIfNeeded(signal)

    let status: String
    if latestGaze == nil {
      status = "人体/头动就绪 · 眼部像素不足或正在推理"
    } else if !hasStereoDepth {
      status = "三模型就绪 · 当前无立体深度"
    } else {
      status = "立体人体 + 头动 + 眼动"
    }
    let performance = [
      latencyLabel("人体", pipeline: .body),
      latencyLabel("头动", pipeline: .head),
      latencyLabel("眼动", pipeline: .gaze),
    ].compactMap { $0 }.joined(separator: " · ")
    let now = CACurrentMediaTime()
    if now - lastPerformanceLog >= 1 {
      lastPerformanceLog = now
      print(
        "[RehabPerf] \(status) | \(performance) | depthCoverage=\(Int(latestDepthCoverage * 100))% gazeQuality=\(Int((latestGaze?.quality ?? 0) * 100))%"
      )
    }

    DispatchQueue.main.async {
      self.latestSignals = signal
      self.processingStatus = status
      self.performanceText =
        performance.isEmpty ? "等待性能样本" : performance
    }
  }

  private func latencyLabel(
    _ name: String,
    pipeline: Pipeline
  ) -> String? {
    guard let value = latencyMilliseconds[pipeline] else { return nil }
    return "\(name) \(Int(value.rounded()))ms"
  }

  private func recordIfNeeded(_ signal: SignalFrame) {
    guard isRecording else { return }
    if let lastRecordedAt,
      signal.timestamp.timeIntervalSince(lastRecordedAt) < 1 / 30
    {
      return
    }
    lastRecordedAt = signal.timestamp
    recordedSamples.append(RecordedSignalSample(signal: signal))
    let count = recordedSamples.count
    DispatchQueue.main.async {
      self.recordedSampleCount = count
    }
  }

  private func write(_ session: RecordedSignalSession) throws -> URL {
    let directory = FileManager.default.urls(
      for: .documentDirectory,
      in: .userDomainMask
    )[0].appendingPathComponent("RehabSessions", isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    let formatter = ISO8601DateFormatter()
    let safeDate = formatter.string(from: session.startedAt)
      .replacingOccurrences(of: ":", with: "-")
    let url = directory.appendingPathComponent(
      "rehab-\(safeDate).json"
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(session).write(to: url, options: .atomic)
    return url
  }

  private func centerDisplacement(from detection: PoseDetection) -> Double? {
    guard let leftHip = detection.point(named: "left_hip"),
      let rightHip = detection.point(named: "right_hip")
    else {
      return nil
    }
    let centerX = (leftHip.x + rightHip.x) / 2
    let centerY = (leftHip.y + rightHip.y) / 2
    return hypot(centerX - 0.5, centerY - 0.55)
  }
}

private struct RecordedSignalSession: Codable {
  let startedAt: Date
  let endedAt: Date
  let models: String
  let samples: [RecordedSignalSample]
}

private struct RecordedSignalSample: Codable {
  let timestamp: Date
  let headYaw: Double?
  let headPitch: Double?
  let headRoll: Double?
  let gazeYaw: Double?
  let gazePitch: Double?
  let headQuality: Double?
  let gazeQuality: Double?
  let depthCoverage: Double
  let medianBodyDepthMeters: Double?
  let landmarks: [RecordedLandmark]

  init(signal: SignalFrame) {
    timestamp = signal.timestamp
    headYaw = signal.headYaw
    headPitch = signal.headPitch
    headRoll = signal.headRoll
    gazeYaw = signal.gazeDirectionX
    gazePitch = signal.gazeDirectionY
    headQuality = signal.headPoseQuality
    gazeQuality = signal.gazeQuality
    depthCoverage = signal.stereoDepthCoverage
    medianBodyDepthMeters = signal.medianBodyDepthMeters
    landmarks = signal.bodyLandmarks.map(RecordedLandmark.init)
  }
}

private struct RecordedLandmark: Codable {
  let name: String
  let x: Double
  let y: Double
  let confidence: Double
  let cameraX: Double?
  let cameraY: Double?
  let cameraZ: Double?

  init(point: BodyLandmarkPoint) {
    name = point.identifier
    x = point.x
    y = point.y
    confidence = point.confidence
    cameraX = point.cameraX
    cameraY = point.cameraY
    cameraZ = point.cameraZ
  }
}
