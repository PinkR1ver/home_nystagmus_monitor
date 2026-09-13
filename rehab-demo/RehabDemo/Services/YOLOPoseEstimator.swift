import CoreML
import Foundation
import ImageIO
import Vision

/// One YOLO11 pose result in normalized, top-left-origin coordinates.
struct PoseDetection {
  let confidence: Double
  let landmarks: [BodyLandmarkPoint]

  func point(named name: String) -> BodyLandmarkPoint? {
    landmarks.first { $0.identifier == name }
  }
}

/// Runs the third-party YOLO11n-pose weights bundled with the app.
///
/// Source weights:
/// https://huggingface.co/Ultralytics/YOLO11/blob/main/yolo11n-pose.pt
final class YOLOPoseEstimator {
  static let modelDisplayName = "YOLO11n Pose"
  static let sourceRevision = "ef78744"

  private static let modelSize = 640.0
  private static let channelCount = 56
  private static let keypointNames = [
    "nose",
    "left_eye", "right_eye",
    "left_ear", "right_ear",
    "left_shoulder", "right_shoulder",
    "left_elbow", "right_elbow",
    "left_wrist", "right_wrist",
    "left_hip", "right_hip",
    "left_knee", "right_knee",
    "left_ankle", "right_ankle",
  ]

  private let visionModel: VNCoreMLModel

  init() throws {
    guard
      let modelURL =
        Bundle.main.url(forResource: "YOLO11nPose", withExtension: "mlmodelc")
        ?? Bundle.main.url(forResource: "yolo11n-pose", withExtension: "mlmodelc")
    else {
      throw EstimatorError.modelMissing
    }

    let configuration = MLModelConfiguration()
    configuration.computeUnits = .all
    let model = try MLModel(contentsOf: modelURL, configuration: configuration)
    visionModel = try VNCoreMLModel(for: model)
  }

  func predict(
    pixelBuffer: CVPixelBuffer,
    orientation: CGImagePropertyOrientation = .up
  ) throws -> PoseDetection? {
    var output: MLMultiArray?
    var requestError: Error?

    let request = VNCoreMLRequest(model: visionModel) { request, error in
      requestError = error
      output =
        request.results?
        .compactMap { $0 as? VNCoreMLFeatureValueObservation }
        .compactMap(\.featureValue.multiArrayValue)
        .first
    }
    request.imageCropAndScaleOption = .scaleFill

    let handler = VNImageRequestHandler(
      cvPixelBuffer: pixelBuffer,
      orientation: orientation,
      options: [:]
    )
    try handler.perform([request])
    if let requestError { throw requestError }
    guard let output else { return nil }
    return decode(output)
  }

  private func decode(_ array: MLMultiArray) -> PoseDetection? {
    guard array.shape.count == 3,
      array.shape[1].intValue == Self.channelCount
    else {
      return nil
    }

    let candidateCount = array.shape[2].intValue
    var bestIndex = -1
    var bestConfidence = 0.25

    for candidate in 0..<candidateCount {
      let confidence = value(array, channel: 4, candidate: candidate)
      if confidence > bestConfidence {
        bestConfidence = confidence
        bestIndex = candidate
      }
    }
    guard bestIndex >= 0 else { return nil }

    var landmarks: [BodyLandmarkPoint] = []
    for (index, name) in Self.keypointNames.enumerated() {
      let base = 5 + index * 3
      let confidence = value(array, channel: base + 2, candidate: bestIndex)
      guard confidence >= 0.20 else { continue }

      let x = value(array, channel: base, candidate: bestIndex) / Self.modelSize
      let y = value(array, channel: base + 1, candidate: bestIndex) / Self.modelSize
      landmarks.append(
        BodyLandmarkPoint(
          identifier: name,
          x: min(max(x, 0), 1),
          y: min(max(y, 0), 1),
          confidence: confidence
        )
      )
    }

    appendMidpoint(
      named: "neck",
      between: "left_shoulder",
      and: "right_shoulder",
      to: &landmarks
    )
    appendMidpoint(
      named: "root",
      between: "left_hip",
      and: "right_hip",
      to: &landmarks
    )

    return PoseDetection(confidence: bestConfidence, landmarks: landmarks)
  }

  private func value(
    _ array: MLMultiArray,
    channel: Int,
    candidate: Int
  ) -> Double {
    array[
      [
        NSNumber(value: 0),
        NSNumber(value: channel),
        NSNumber(value: candidate),
      ]
    ].doubleValue
  }

  private func appendMidpoint(
    named name: String,
    between firstName: String,
    and secondName: String,
    to landmarks: inout [BodyLandmarkPoint]
  ) {
    guard let first = landmarks.first(where: { $0.identifier == firstName }),
      let second = landmarks.first(where: { $0.identifier == secondName })
    else {
      return
    }

    landmarks.append(
      BodyLandmarkPoint(
        identifier: name,
        x: (first.x + second.x) / 2,
        y: (first.y + second.y) / 2,
        confidence: min(first.confidence, second.confidence)
      )
    )
  }

  enum EstimatorError: LocalizedError {
    case modelMissing

    var errorDescription: String? {
      switch self {
      case .modelMissing:
        "未找到 YOLO11n Pose 模型资源"
      }
    }
  }
}
