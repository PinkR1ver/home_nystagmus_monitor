import Foundation
import AVFoundation
import UIKit
import MediaPipeTasksVision

/// Android-equivalent unmirrored world/image landmarks, CPU Heavy, 20 Hz requests.
final class BodyPoseDetector {
    private let detector: PoseLandmarker
    init() throws {
        guard let path = Bundle.main.path(forResource: "pose_landmarker_heavy", ofType: "task") else {
            throw BodyAnalysisError.unavailable("缺少身体姿态模型")
        }
        let options = PoseLandmarkerOptions()
        options.baseOptions.modelAssetPath = path
        options.baseOptions.delegate = .CPU
        options.runningMode = .video
        options.numPoses = 2
        options.minPoseDetectionConfidence = 0.5
        options.minPosePresenceConfidence = 0.5
        options.minTrackingConfidence = 0.5
        detector = try PoseLandmarker(options: options)
    }
    func detect(_ image: UIImage, timestampMs: Int) throws -> BodyPoseFrame {
        let result = try detector.detect(videoFrame: MPImage(uiImage: image), timestampInMilliseconds: timestampMs)
        guard result.worldLandmarks.count == 1, let world = result.worldLandmarks.first, let normalized = result.landmarks.first else {
            return BodyPoseFrame(timeMs: timestampMs, points: [], scores: [], personCount: result.worldLandmarks.count)
        }
        return BodyPoseFrame(timeMs: timestampMs,
            points: world.map { BodyVector(Double($0.x), Double($0.y), Double($0.z)) },
            scores: normalized.map { min($0.visibility?.doubleValue ?? 0, $0.presence?.doubleValue ?? 0) },
            personCount: 1,
            imagePoints: normalized.map { BodyVector(Double($0.x), Double($0.y), Double($0.z)) })
    }
    func video(_ url: URL, gait: Bool, onProgress: (Double) -> Void) async throws -> [BodyPoseFrame] {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, (3...120).contains(duration) else {
            throw BodyAnalysisError.unavailable("请选择 3–120 秒的视频")
        }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let side = gait ? 1280 : 960
        generator.maximumSize = CGSize(width: side, height: side)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.025, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.025, preferredTimescale: 600)
        let count = Int(ceil(duration * 20))
        var frames: [BodyPoseFrame] = []
        frames.reserveCapacity(count)
        for index in 0..<count {
            try Task.checkCancellation()
            let ms = index*50
            let frame: BodyPoseFrame = try autoreleasepool {
                guard let image = try? generator.copyCGImage(at: CMTime(value: Int64(ms), timescale: 1000), actualTime: nil) else {
                    return BodyPoseFrame(timeMs: ms, points: [], scores: [], personCount: 0)
                }
                return try detect(UIImage(cgImage: image), timestampMs: ms)
            }
            frames.append(frame)
            if index % 5 == 0 { onProgress(Double(index+1)/Double(count)) }
        }
        return frames
    }
}
