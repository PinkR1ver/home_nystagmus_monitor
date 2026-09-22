import CoreGraphics
import CoreImage
import Darwin
import Foundation
import OnnxRuntimeBindings

struct GazeEstimate {
  let yaw: Double
  let pitch: Double
  let quality: Double
  let sourcePixelSize: CGSize
}

/// Reuses the project's bundled SwinUNet gaze weights through ONNX Runtime.
/// The face/eye ROI comes from YOLO pose landmarks, not Apple face landmarks.
final class ONNXGazeEstimator {
  static let modelDisplayName = "SwinUNet Gaze"

  private let inputName = "input"
  private let outputName = "output"
  private let inputWidth = 60
  private let inputHeight = 36
  private let channelCount = 3
  private let imageContext = CIContext(options: [.cacheIntermediates: false])

  private var environment: ORTEnv?
  private var session: ORTSession?

  func predict(
    pixelBuffer: CVPixelBuffer,
    detection: PoseDetection
  ) throws -> GazeEstimate? {
    guard let rect = FaceCropGeometry.eyeRect(for: detection),
      let crop = FaceCropGeometry.crop(
        pixelBuffer: pixelBuffer,
        normalizedTopLeftRect: rect,
        context: imageContext
      )
    else {
      return nil
    }

    let horizontalQuality = min(1, crop.sourceSize.width / CGFloat(inputWidth))
    let verticalQuality = min(1, crop.sourceSize.height / CGFloat(inputHeight))
    let quality = Double(horizontalQuality * verticalQuality)
    // Upscaling a tiny full-body eye crop produces plausible-looking but
    // clinically meaningless gaze values. Reject it explicitly.
    guard quality >= 0.22 else { return nil }

    let values = try makeInputTensor(from: crop.image)
    let data = values.withUnsafeBufferPointer { buffer in
      NSMutableData(
        bytes: buffer.baseAddress,
        length: values.count * MemoryLayout<Float>.size
      )
    }
    let tensor = try ORTValue(
      tensorData: data,
      elementType: .float,
      shape: [
        1,
        NSNumber(value: channelCount),
        NSNumber(value: inputHeight),
        NSNumber(value: inputWidth),
      ]
    )
    let outputs = try activeSession().run(
      withInputs: [inputName: tensor],
      outputNames: Set([outputName]),
      runOptions: nil
    )
    guard let result = outputs[outputName] else { return nil }
    let tensorData = try result.tensorData()
    let count = tensorData.length / MemoryLayout<Float>.size
    guard count >= 3 else { return nil }

    let base = tensorData.bytes.bindMemory(to: Float.self, capacity: count)
    let x = Double(base[0])
    let y = Double(base[1])
    let z = Double(base[2])
    let norm = max(sqrt(x * x + y * y + z * z), 1.0e-8)
    let normalizedX = x / norm
    let normalizedY = y / norm
    let normalizedZ = z / norm
    // SwinUNet uses the MPIIGaze camera convention: forward gaze points
    // toward negative Z. Keep this conversion identical to the existing
    // iPhone analysis pipeline so a forward-looking eye is near 0°, not 180°.
    let pitch = asin(min(max(-normalizedY, -1), 1)) * 180 / .pi
    let yaw = atan2(-normalizedX, -normalizedZ) * 180 / .pi

    return GazeEstimate(
      yaw: yaw,
      pitch: pitch,
      quality: quality,
      sourcePixelSize: crop.sourceSize
    )
  }

  private func activeSession() throws -> ORTSession {
    if let session { return session }
    guard
      let modelURL = Bundle.main.url(
        forResource: "swinunet_web",
        withExtension: "onnx"
      )
    else {
      throw EstimatorError.modelMissing
    }

    let environment = try ORTEnv(loggingLevel: .warning)
    let options = try ORTSessionOptions()
    try options.setGraphOptimizationLevel(.all)
    try options.setIntraOpNumThreads(2)
    let session = try ORTSession(
      env: environment,
      modelPath: modelURL.path,
      sessionOptions: options
    )
    self.environment = environment
    self.session = session
    return session
  }

  private func makeInputTensor(from image: CGImage) throws -> [Float] {
    let bytesPerPixel = 4
    let bytesPerRow = inputWidth * bytesPerPixel
    var pixels = [UInt8](
      repeating: 0,
      count: inputWidth * inputHeight * bytesPerPixel
    )
    guard
      let context = CGContext(
        data: &pixels,
        width: inputWidth,
        height: inputHeight,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else {
      throw EstimatorError.invalidImage
    }

    context.interpolationQuality = .medium
    context.draw(
      image,
      in: CGRect(x: 0, y: 0, width: inputWidth, height: inputHeight)
    )

    var tensor = [Float](
      repeating: 0,
      count: channelCount * inputHeight * inputWidth
    )
    let planeSize = inputHeight * inputWidth
    for y in 0..<inputHeight {
      for x in 0..<inputWidth {
        let pixelOffset = (y * inputWidth + x) * bytesPerPixel
        let tensorOffset = y * inputWidth + x
        tensor[tensorOffset] = Float(pixels[pixelOffset]) / 255
        tensor[planeSize + tensorOffset] =
          Float(pixels[pixelOffset + 1]) / 255
        tensor[planeSize * 2 + tensorOffset] =
          Float(pixels[pixelOffset + 2]) / 255
      }
    }
    return tensor
  }

  enum EstimatorError: LocalizedError {
    case modelMissing
    case invalidImage

    var errorDescription: String? {
      switch self {
      case .modelMissing:
        "未找到现有 SwinUNet 眼动模型"
      case .invalidImage:
        "无法生成眼动模型输入"
      }
    }
  }
}
