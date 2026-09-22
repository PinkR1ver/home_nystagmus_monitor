import Foundation

@main struct BodyAnalysisSmoke {
    struct Fixture: Decodable { var leg: Double; var signals: [BodySignal]; var rises: [[Double]] }
    static func main() throws {
        let root=URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("iphone-app")
        let config=try JSONDecoder().decode(BodyDetectorConfig.self,from: Data(contentsOf: root.appendingPathComponent("HomeNystagmusMonitoriOS/Resources/sts_detection_v1.json")))
        let segments=try JSONDecoder().decode(BodySegmentConfig.self,from: Data(contentsOf: root.appendingPathComponent("HomeNystagmusMonitoriOS/Resources/mediapipe_segment_model_v1.json")))
        let fixture=try JSONDecoder().decode(Fixture.self,from: Data(contentsOf: root.appendingPathComponent("tests/fixtures/t03_signal_fixture.json")))
        let analyzer=BodyStsAnalyzer(config: config)
        let result=try analyzer.analyze(fixture.signals,leg: fixture.leg)
        let rises=result.events.filter { $0.direction == "rise" && $0.status == "accepted" }
        precondition(rises.count == 5)
        for (event,expected) in zip(rises,fixture.rises) {
            precondition(abs(event.startS-expected[0]) <= 0.050001)
            precondition(abs(event.endS-expected[1]) <= 0.050001)
        }
        precondition(abs(result.stats["riseDuration"]!.cvPercent!-10.3540574)<1e-5)
        precondition(result.stats["seatedDwell"]?.n == 4)
        let quadratic=(0...30).map { Double($0*$0) }
        let smoothed=analyzer.smooth(quadratic)
        for (a,b) in zip(quadratic,smoothed) { precondition(abs(a-b!)<1e-8) }
        var gap=quadratic.map(Optional.some);gap[15]=nil
        precondition(analyzer.smooth(gap)[15] == nil)
        var p=Array(repeating: BodyVector(0,0,0),count:33)
        for side in 0...1 {
            let sign=side == 0 ? -1.0 : 1.0
            p[7+side]=BodyVector(sign*0.07,1.65,0)
            p[11+side]=BodyVector(sign*0.2,1.4,0);p[13+side]=BodyVector(sign*0.28,1.2,0)
            p[15+side]=BodyVector(sign*0.32,1,0);p[17+side]=BodyVector(sign*0.34,0.94,0.01);p[19+side]=BodyVector(sign*0.33,0.94,0.02)
            p[23+side]=BodyVector(sign*0.13,0.95,0);p[25+side]=BodyVector(sign*0.13,0.5,0)
            p[27+side]=BodyVector(sign*0.13,0.1,0);p[31+side]=BodyVector(sign*0.13,0.04,0.2)
        }
        let frames=(0..<60).map { BodyPoseFrame(timeMs:$0*50,points:p,scores:Array(repeating:1,count:33),personCount:1) }
        let shifted=frames.map { f -> BodyPoseFrame in var f=f;f.points=f.points.map { $0+BodyVector(3,7,2) };return f }
        let model=BodySegmentModel(config:segments)
        let a=try model.compute(frames,subject:BodySubject())
        let b=try model.compute(shifted,subject:BodySubject(massKg:90))
        precondition(abs(a.legLength-0.85)<1e-8)
        precondition(abs(a.signals[0].inertia!-b.signals[0].inertia!)<1e-8)
        precondition(abs(a.signals[0].comZ!-b.signals[0].comZ!)<1e-8)
        precondition(a.signals[0].inertia!>0)
        var missing=frames;missing[25].personCount=2
        let excluded=try model.compute(missing,subject:BodySubject())
        precondition(excluded.signals[25].inertia == nil && excluded.channels[25].isEmpty)
        print("PASS: Android t03 five-rise golden boundaries/CV; SG quadratic/gap preservation; body translation/mass invariance; multi-person exclusion")
    }
}
