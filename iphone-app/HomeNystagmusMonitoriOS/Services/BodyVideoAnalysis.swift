import Foundation
import AVFoundation

struct BodyAnalysisReport: Codable {
    var version = "apple-motion-v1"
    var model = "MediaPipe Pose Heavy / CPU"
    var motion: BodyMotionReport?
    var mode: String
    var subject: BodySubject
    var durationS: Double
    var validCoverage: Double
    var analysisHz = 20
    var events: [BodyEvent]
    var stats: [String: BodyStats]
    var signals: [BodySignal]
    var warnings: [String]
    var bodyBasis: [BodyVector]
    var legLengthM: Double
}
struct BodyVideoAnalysis {
    struct Output { var report: BodyAnalysisReport; var frames: [BodyPoseFrame] }
    func analyze(video: URL, subject: BodySubject, mode: String) async throws -> Output {
        func config<T: Decodable>(_ name: String, type: T.Type) throws -> T {
            guard let path=Bundle.main.url(forResource:name,withExtension:"json") else { throw BodyAnalysisError.unavailable("缺少分析参数文件") }
            return try JSONDecoder().decode(type,from:Data(contentsOf:path))
        }
        let segmentConfig=try config("mediapipe_segment_model_v1",type:BodySegmentConfig.self)
        let detectorConfig=try config("sts_detection_v1",type:BodyDetectorConfig.self)
        let duration=try await AVURLAsset(url:video).load(.duration).seconds
        let detector=try BodyPoseDetector()
        let frames=try await detector.video(video,gait:mode == "gait") { _ in }
        try Task.checkCancellation()
        let body=try BodySegmentModel(config:segmentConfig).compute(frames,subject:subject)
        let sts=mode == "sts" ? try BodyStsAnalyzer(config:detectorConfig).analyze(body.signals,leg:body.legLength) : nil
        let coverage=Double(body.signals.filter { $0.inertia != nil }.count)/Double(body.signals.count)
        var warnings=body.warnings+(sts?.warnings ?? [])
        warnings.append("解码按 20 Hz 请求最近视频帧，时间不是逐帧精确 PTS；不用于高精度事件计时。")
        if coverage < 0.8 { warnings.append("有效全身数据低于 80%，请优先改善取景后重拍。") }
        return Output(report:BodyAnalysisReport(motion:BodyMotionMetrics().analyze(mode:mode,frames:frames,body:body,duration:duration,coverage:coverage,sts:sts),mode:mode,subject:subject,durationS:duration,validCoverage:coverage,events:sts?.events ?? [],stats:sts?.stats ?? [:],signals:sts?.signals ?? body.signals,warnings:warnings,bodyBasis:body.basis,legLengthM:body.legLength),frames:frames)
    }
}
