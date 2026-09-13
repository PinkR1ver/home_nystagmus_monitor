import AVFoundation
import CoreGraphics
import UIKit
import simd

struct StereoProjection {
  let landmarks: [BodyLandmarkPoint]
  let coverage: Double
  let medianDepthMeters: Double?
  let accuracyIsAbsolute: Bool
}

enum StereoDepthProjector {
  static func project(
    detection: PoseDetection,
    depthData: AVDepthData
  ) -> StereoProjection {
    let converted = depthData.converting(
      toDepthDataType: kCVPixelFormatType_DepthFloat32
    )
    let map = converted.depthDataMap
    let calibration = converted.cameraCalibrationData
    let width = CVPixelBufferGetWidth(map)
    let height = CVPixelBufferGetHeight(map)

    CVPixelBufferLockBaseAddress(map, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
    guard let baseAddress = CVPixelBufferGetBaseAddress(map) else {
      return StereoProjection(
        landmarks: detection.landmarks,
        coverage: 0,
        medianDepthMeters: nil,
        accuracyIsAbsolute: false
      )
    }

    let rowStride =
      CVPixelBufferGetBytesPerRow(map) / MemoryLayout<Float>.stride
    let floats = baseAddress.assumingMemoryBound(to: Float.self)
    var depths: [Double] = []
    var projected: [BodyLandmarkPoint] = []
    projected.reserveCapacity(detection.landmarks.count)

    for point in detection.landmarks {
      let u = min(max(Int(point.x * Double(width - 1)), 0), width - 1)
      let v = min(max(Int(point.y * Double(height - 1)), 0), height - 1)
      let depth = medianDepth(
        aroundX: u,
        y: v,
        width: width,
        height: height,
        rowStride: rowStride,
        values: floats
      )

      var cameraX: Double?
      var cameraY: Double?
      if let depth, let calibration {
        let matrix = calibration.intrinsicMatrix
        let reference = calibration.intrinsicMatrixReferenceDimensions
        let scaleX = Double(width) / max(Double(reference.width), 1)
        let scaleY = Double(height) / max(Double(reference.height), 1)
        let fx = Double(matrix.columns.0.x) * scaleX
        let fy = Double(matrix.columns.1.y) * scaleY
        let cx = Double(matrix.columns.2.x) * scaleX
        let cy = Double(matrix.columns.2.y) * scaleY
        if fx > 0, fy > 0 {
          cameraX = (Double(u) - cx) / fx * depth
          cameraY = (Double(v) - cy) / fy * depth
        }
      }

      if let depth { depths.append(depth) }
      projected.append(
        BodyLandmarkPoint(
          identifier: point.identifier,
          x: point.x,
          y: point.y,
          confidence: point.confidence,
          cameraX: cameraX,
          cameraY: cameraY,
          cameraZ: depth
        )
      )
    }

    let coverage =
      detection.landmarks.isEmpty
      ? 0
      : Double(depths.count) / Double(detection.landmarks.count)
    return StereoProjection(
      landmarks: projected,
      coverage: coverage,
      medianDepthMeters: median(depths),
      accuracyIsAbsolute: converted.depthDataAccuracy == .absolute
    )
  }

  static func previewImage(from depthData: AVDepthData) -> UIImage? {
    let converted = depthData.converting(
      toDepthDataType: kCVPixelFormatType_DepthFloat32
    )
    let map = converted.depthDataMap
    let width = CVPixelBufferGetWidth(map)
    let height = CVPixelBufferGetHeight(map)
    CVPixelBufferLockBaseAddress(map, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
    guard let baseAddress = CVPixelBufferGetBaseAddress(map) else { return nil }

    let rowStride =
      CVPixelBufferGetBytesPerRow(map) / MemoryLayout<Float>.stride
    let values = baseAddress.assumingMemoryBound(to: Float.self)
    var valid: [Float] = []
    valid.reserveCapacity(width * height / 8)
    for y in stride(from: 0, to: height, by: 3) {
      for x in stride(from: 0, to: width, by: 3) {
        let value = values[y * rowStride + x]
        if value.isFinite, value > 0, value < 15 {
          valid.append(value)
        }
      }
    }
    guard valid.count > 24 else { return nil }
    valid.sort()
    let near = valid[Int(Double(valid.count - 1) * 0.08)]
    let far = valid[Int(Double(valid.count - 1) * 0.92)]
    let span = max(far - near, 0.05)

    var rgba = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
      for x in 0..<width {
        let depth = values[y * rowStride + x]
        let offset = (y * width + x) * 4
        guard depth.isFinite, depth > 0, depth < 15 else {
          rgba[offset + 3] = 255
          continue
        }
        let normalized = min(max((depth - near) / span, 0), 1)
        let hue = CGFloat((1 - normalized) * 0.48)
        let color = UIColor(
          hue: hue,
          saturation: 0.88,
          brightness: 0.96,
          alpha: 1
        )
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: nil)
        rgba[offset] = UInt8(red * 255)
        rgba[offset + 1] = UInt8(green * 255)
        rgba[offset + 2] = UInt8(blue * 255)
        rgba[offset + 3] = 255
      }
    }

    let data = Data(rgba) as CFData
    guard
      let provider = CGDataProvider(data: data),
      let image = CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(
          rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
        ),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
      )
    else {
      return nil
    }
    return UIImage(cgImage: image)
  }

  private static func medianDepth(
    aroundX x: Int,
    y: Int,
    width: Int,
    height: Int,
    rowStride: Int,
    values: UnsafePointer<Float>
  ) -> Double? {
    var samples: [Double] = []
    for offsetY in -2...2 {
      for offsetX in -2...2 {
        let px = min(max(x + offsetX, 0), width - 1)
        let py = min(max(y + offsetY, 0), height - 1)
        let value = values[py * rowStride + px]
        if value.isFinite, value > 0.08, value < 15 {
          samples.append(Double(value))
        }
      }
    }
    return median(samples)
  }

  private static func median(_ values: [Double]) -> Double? {
    guard !values.isEmpty else { return nil }
    let sorted = values.sorted()
    if sorted.count.isMultiple(of: 2) {
      let upper = sorted.count / 2
      return (sorted[upper - 1] + sorted[upper]) / 2
    }
    return sorted[sorted.count / 2]
  }
}
