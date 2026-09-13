import CoreML
import Foundation
import ImageIO
import Vision

struct HeadPoseEstimate {
  let yaw: Double
  let pitch: Double
  let roll: Double
  let quality: Double
  let blurRisk: Double
  let occlusionRisk: Double
  let exposureRisk: Double
}

/// Runs the third-party Face Capture Quality MobileNetV3 weights from
/// Hugging Face. Vision is used only as the Core ML execution/cropping layer.
final class HeadPoseEstimator {
  static let modelDisplayName = "FCQ Head Pose"

  private let visionModel: VNCoreMLModel

  init() throws {
    guard
      let modelURL =
        Bundle.main.url(forResource: "HeadPose", withExtension: "mlmodelc")
        ?? Bundle.main.url(
          forResource: "FaceCaptureQuality",
          withExtension: "mlmodelc"
        )
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
    faceRectTopLeft: CGRect
  ) throws -> HeadPoseEstimate? {
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
    request.regionOfInterest = CGRect(
      x: faceRectTopLeft.minX,
      y: 1 - faceRectTopLeft.maxY,
      width: faceRectTopLeft.width,
      height: faceRectTopLeft.height
    )

    try VNImageRequestHandler(
      cvPixelBuffer: pixelBuffer,
      orientation: .up,
      options: [:]
    ).perform([request])
    if let requestError { throw requestError }
    guard let output, output.count >= 7 else { return nil }

    return HeadPoseEstimate(
      yaw: output[0].doubleValue,
      pitch: output[1].doubleValue,
      roll: output[2].doubleValue,
      quality: output[3].doubleValue,
      blurRisk: output[4].doubleValue,
      occlusionRisk: output[5].doubleValue,
      exposureRisk: output[6].doubleValue
    )
  }

  enum EstimatorError: LocalizedError {
    case modelMissing

    var errorDescription: String? {
      "未找到第三方头动模型资源"
    }
  }
}
