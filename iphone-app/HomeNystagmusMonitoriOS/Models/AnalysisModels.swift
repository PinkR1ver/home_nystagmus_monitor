import CoreGraphics
import Foundation

enum CaptureSource: String, Codable, Equatable {
    case camera = "Camera capture"
    case importedVideo = "Imported video"
}

enum NystagmusFinding: String, Codable, Equatable {
    case detected = "Nystagmus signal detected"
    case notDetected = "No clear nystagmus signal"
    case inconclusive = "Needs another capture"

    var shortLabel: String {
        switch self {
        case .detected:
            return "Detected"
        case .notDetected:
            return "Clear"
        case .inconclusive:
            return "Retake"
        }
    }
}

struct GazeSample: Identifiable, Codable, Equatable {
    var id = UUID()
    let time: Double
    let horizontal: Double
    let vertical: Double
}

struct SignalPattern: Identifiable, Codable, Equatable {
    var id = UUID()
    let startTime: Double
    let peakTime: Double
    let endTime: Double
    let amplitude: Double
    let fastPhaseFirst: Bool
}

struct AxisSignalSummary: Codable, Equatable {
    let title: String
    let present: Bool
    let directionLabel: String
    let patternCount: Int
    let spv: Double
    let cvPercent: Double
    let amplitude: Double
    let frequencyHz: Double
    let samples: [Double]
    let patterns: [SignalPattern]
}

struct EyeEvidenceFrame: Identifiable, Codable, Equatable {
    var id = UUID()
    let timeSeconds: Double
    let sourceFrameURL: URL
    let cropFrameURL: URL
    let normalizedCropRect: CGRect
    let roiModeLabel: String
}

struct AnalysisResult: Codable, Equatable {
    let source: CaptureSource
    let fileName: String
    let durationSeconds: Double
    let finding: NystagmusFinding
    let confidence: Double
    let beatFrequencyHz: Double
    let peakVelocity: Double
    let qualityScore: Double
    let modelName: String
    let summary: String
    let samples: [GazeSample]
    let horizontalAxis: AxisSignalSummary
    let verticalAxis: AxisSignalSummary
    let processingSteps: [String]
    let eyePreviewFrameURLs: [URL]
    let eyeEvidenceFrames: [EyeEvidenceFrame]
    let evidenceVideoURL: URL?
    var rawSamples: [EyeRawSample]? = nil
    var unavailableReason: String? = nil
    var fixedRegion: EyeRegion? = nil

    var durationText: String {
        let seconds = Int(durationSeconds.rounded())
        return "\(seconds)s"
    }

    var confidencePercent: Int {
        Int((confidence * 100).rounded())
    }

    var qualityPercent: Int {
        Int((qualityScore * 100).rounded())
    }
}
