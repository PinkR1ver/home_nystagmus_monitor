import Foundation
@main struct MotionMetricsSmoke {
    static func fixture(_ seconds:Int,_ walking:Bool)->([BodyPoseFrame],BodySegmentModel.Result) {
        let frames=(0..<seconds*20).map{i->BodyPoseFrame in
            var p=Array(repeating:BodyVector(0,0,1),count:33)
            for s in 0...1 {
                let side=s == 0 ? -1.0:1.0;let y=walking ? 0.22*cos(2 * .pi * Double(i)/24 + .pi * Double(s)):0
                p[23+s]=BodyVector(side*0.1,0,0.9);p[25+s]=BodyVector(side*0.1,y*0.5,0.5)
                p[27+s]=BodyVector(side*0.1,y,0.08);p[29+s]=BodyVector(side*0.1,y-0.04,0.02)
                p[31+s]=BodyVector(side*0.1+0.015*side,y+0.16,0.02)
            }
            return BodyPoseFrame(timeMs:i*50,points:p,scores:Array(repeating:1,count:33),personCount:1)
        }
        let signals=frames.map{BodySignal(timeS:Double($0.timeMs)/1000,inertia:0.6,pelvisZ:0.9,comZ:1,kneeL:0,kneeR:0,hipL:0,hipR:0,trunk:0,quality:1)}
        let channels=frames.indices.map{i->[String:Double?] in ["com_x":0.01*sin(2 * .pi * Double(i)/80),"com_y":0.02*cos(2 * .pi * Double(i)/80),"com_z":1,"pelvis_z":0.9]}
        return(frames,BodySegmentModel.Result(signals:signals,legLength:0.9,basis:[BodyVector(1,0,0),BodyVector(0,1,0),BodyVector(0,0,1)],warnings:[],channels:channels))
    }
    static func report(_ mode:String,_ seconds:Int=35,_ walking:Bool=false)->BodyMotionReport {
        let (f,b)=fixture(seconds,walking)
        return BodyMotionMetrics().analyze(mode:mode,frames:f,body:b,duration:Double(seconds),coverage:1,sts:nil)
    }
    static func main()throws {
        let standing=report("standing")
        func value(_ r:BodyMotionReport,_ key:String)->Double? {r.metrics.first{$0.key == key}?.value}
        precondition(abs(value(standing,"rmsd_x")!-0.01/sqrt(2))<0.0003)
        precondition(value(standing,"ellipse")!>0)
        precondition(value(standing,"fpa_l_mean")!>0)
        precondition(abs(value(standing,"fpa_l_mean")!-value(standing,"fpa_r_mean")!)<1e-8)
        precondition(Set(standing.metrics.map(\.key)).count == standing.metrics.count)
        _=try JSONEncoder().encode(standing)
        let still=report("gait",8)
        precondition(value(still,"steps") == 0 && value(still,"cadence") == nil && value(still,"double") == nil)
        let walking=report("gait",15,true)
        precondition(abs(value(walking,"cadence")!-100)<2)
        precondition(walking.events.contains{$0.label.contains("离地")})
        precondition(value(walking,"step_l")!>0)
        let short=report("standing",4)
        precondition(value(short,"entropy_x") == nil && value(short,"lyap_y") == nil)
        precondition(BodyMotionMath.sampleEntropy(Array(repeating:1,count:300)) == nil)
        precondition(BodyMotionMath.lyapunov(Array(repeating:1,count:300),hz:10) == nil)
        let t=(0...10).map{Double($0)*0.05};var a=t.map{Optional(2*$0)};a[5]=nil
        let v=BodyMotionMath.derivative(a,t)
        precondition(abs(v[2]!-2)<1e-10 && v[4] == nil && v[5] == nil && v[6] == nil)
        let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("iphone-app")
        struct Fixture:Decodable {var leg:Double;var signals:[BodySignal]}
        let f=try JSONDecoder().decode(Fixture.self,from:Data(contentsOf:root.appendingPathComponent("tests/fixtures/t03_signal_fixture.json")))
        let config=try JSONDecoder().decode(BodyDetectorConfig.self,from:Data(contentsOf:root.appendingPathComponent("HomeNystagmusMonitoriOS/Resources/sts_detection_v1.json")))
        let sts=try BodyStsAnalyzer(config:config).analyze(f.signals,leg:f.leg)
        let frames=f.signals.map{BodyPoseFrame(timeMs:Int(($0.timeS*1000).rounded()),points:Array(repeating:BodyVector(0,0,0),count:33),scores:Array(repeating:0,count:33),personCount:1)}
        let body=BodySegmentModel.Result(signals:f.signals,legLength:f.leg,basis:[BodyVector(1,0,0),BodyVector(0,1,0),BodyVector(0,0,1)],warnings:[],channels:f.signals.map{["com_z":$0.comZ,"pelvis_z":$0.pelvisZ]})
        let r=BodyMotionMetrics().analyze(mode:"sts",frames:frames,body:body,duration:31.3,coverage:1,sts:sts)
        precondition(abs(value(r,"riseDuration_cv")!-10.3540574)<1e-5)
        precondition(value(r,"knee_l_wave_rmse") != nil && r.events.first!.metrics.count>20)
        _=try JSONEncoder().encode(r)
        print("PASS: Android motion fixtures — standing sway/ellipse, symmetric foot angles, alternating 100 steps/min, no false stationary steps, nonlinear gates, missing-gap derivatives, STS per-event and waveform metrics")
    }
}
