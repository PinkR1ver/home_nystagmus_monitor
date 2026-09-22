import Foundation
import CoreGraphics

/// Top-left origin in the upright, unmirrored video image (same convention as Android).
struct EyeRegion: Codable, Equatable {
    var x: Double = 0.2
    var y: Double = 0.35
    var width: Double = 0.6
    var height: Double = 0.3
    var isValid: Bool {
        [x, y, width, height].allSatisfy(\.isFinite) && x >= 0 && y >= 0 && width > 0 && height > 0 && x + width <= 1.00001 && y + height <= 1.00001
    }
    func pixelRect(width imageWidth: Int, height imageHeight: Int) -> CGRect? {
        guard isValid, imageWidth > 0, imageHeight > 0 else { return nil }
        let left = min(imageWidth - 1, Int(x * Double(imageWidth)))
        let top = min(imageHeight - 1, Int(y * Double(imageHeight)))
        return CGRect(x: left, y: top, width: max(1, min(imageWidth - left, Int(width * Double(imageWidth)))), height: max(1, min(imageHeight - top, Int(height * Double(imageHeight)))))
    }
    var normalizedRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}
