import CoreGraphics
import CoreImage
import Foundation

enum FaceCropGeometry {
  /// Returns a square, normalized, top-left-origin face crop inferred from
  /// third-party YOLO pose landmarks. No Apple face-landmark model is used.
  static func faceRect(for detection: PoseDetection) -> CGRect? {
    guard let nose = detection.point(named: "nose"),
      let leftEye = detection.point(named: "left_eye"),
      let rightEye = detection.point(named: "right_eye")
    else {
      return nil
    }

    let eyeDistance = hypot(rightEye.x - leftEye.x, rightEye.y - leftEye.y)
    guard eyeDistance > 0.008 else { return nil }

    let eyeMidX = (leftEye.x + rightEye.x) / 2
    let eyeMidY = (leftEye.y + rightEye.y) / 2
    let earSpan: Double
    if let leftEar = detection.point(named: "left_ear"),
      let rightEar = detection.point(named: "right_ear")
    {
      earSpan = hypot(rightEar.x - leftEar.x, rightEar.y - leftEar.y)
    } else {
      earSpan = eyeDistance * 2.25
    }

    let side = min(max(max(eyeDistance * 3.8, earSpan * 1.42), 0.12), 0.54)
    let centerX = (eyeMidX + nose.x) / 2
    let centerY = eyeMidY + side * 0.16
    return clampedSquare(
      CGRect(
        x: centerX - side / 2,
        y: centerY - side / 2,
        width: side,
        height: side
      )
    )
  }

  /// Returns one eye crop in normalized, top-left-origin coordinates.
  static func eyeRect(for detection: PoseDetection) -> CGRect? {
    guard let leftEye = detection.point(named: "left_eye"),
      let rightEye = detection.point(named: "right_eye")
    else {
      return nil
    }

    let eyeDistance = hypot(rightEye.x - leftEye.x, rightEye.y - leftEye.y)
    guard eyeDistance > 0.008 else { return nil }

    let target = leftEye.confidence >= rightEye.confidence ? leftEye : rightEye
    let width = min(max(eyeDistance * 0.92, 0.025), 0.18)
    let height = width * 0.60
    return CGRect(
      x: min(max(target.x - width / 2, 0), 1 - width),
      y: min(max(target.y - height / 2, 0), 1 - height),
      width: width,
      height: height
    )
  }

  static func crop(
    pixelBuffer: CVPixelBuffer,
    normalizedTopLeftRect rect: CGRect,
    context: CIContext
  ) -> (image: CGImage, sourceSize: CGSize)? {
    let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
    let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
    let pixelRect = CGRect(
      x: rect.minX * width,
      y: rect.minY * height,
      width: rect.width * width,
      height: rect.height * height
    ).integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))

    guard pixelRect.width >= 2, pixelRect.height >= 2 else { return nil }
    let source = CIImage(cvPixelBuffer: pixelBuffer)
    // CIImage uses a bottom-left origin; convert the top-left crop.
    let ciRect = CGRect(
      x: pixelRect.minX,
      y: height - pixelRect.maxY,
      width: pixelRect.width,
      height: pixelRect.height
    )
    guard let image = context.createCGImage(source, from: ciRect) else { return nil }
    return (image, pixelRect.size)
  }

  private static func clampedSquare(_ rect: CGRect) -> CGRect {
    let side = min(rect.width, 1)
    return CGRect(
      x: min(max(rect.midX - side / 2, 0), 1 - side),
      y: min(max(rect.midY - side / 2, 0), 1 - side),
      width: side,
      height: side
    )
  }
}
