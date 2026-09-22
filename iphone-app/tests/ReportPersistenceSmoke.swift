import Foundation

@main struct ReportPersistenceSmoke {
    static func main() throws {
        let axis = AxisSignalSummary(title: "Horizontal", present: false, directionLabel: "none", patternCount: 0, spv: 0, cvPercent: 0, amplitude: 0, frequencyHz: 0, samples: [0, 1, 0], patterns: [])
        let evidence = EyeEvidenceFrame(timeSeconds: 0, sourceFrameURL: URL(fileURLWithPath: "/tmp/source.jpg"), cropFrameURL: URL(fileURLWithPath: "/tmp/crop.jpg"), normalizedCropRect: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4), roiModeLabel: "test")
        let report = AnalysisResult(source: .camera, fileName: "test.mov", durationSeconds: 3, finding: .inconclusive, confidence: 0.2, beatFrequencyHz: 0, peakVelocity: 0, qualityScore: 0.2, modelName: "test", summary: "无法分析仍是有效结果", samples: [GazeSample(time: 0, horizontal: 1, vertical: 2)], horizontalAxis: axis, verticalAxis: axis, processingSteps: [], eyePreviewFrameURLs: [], eyeEvidenceFrames: [evidence], evidenceVideoURL: nil)
        let decoded = try JSONDecoder().decode(AnalysisResult.self, from: JSONEncoder().encode(report))
        precondition(decoded == report, "Report data and sample/evidence IDs must survive persistence")
        precondition(decoded.finding == .inconclusive)
        print("PASS: complete report, inconclusive outcome and stable IDs round-trip")
    }
}
