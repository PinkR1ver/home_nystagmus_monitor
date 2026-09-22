import Foundation

struct BodyDetectorConfig: Codable {
    var version: Double
    var sampling_hz: Int
    var smoothing_s: Double
    var normalization_percentiles: [Double]
    var minimum_relative_inertia_range: Double
    var minimum_inertia_signal_noise_ratio: Double
    var low_state_max: Double
    var high_state_min: Double
    var stability_window_s: Double
    var stable_range_fraction: Double
    var stable_range_noise_multiplier: Double
    var stable_range_cap: Double
    var stable_speed_fraction_of_peak: Double
    var minimum_stable_hold_s: Double
    var transition_duration_s: [Double]
    var partial_excursion_min: Double
    var endpoint_window_s: Double
    var minimum_feature_coverage: Double
    var landmark_score_min: Double
    var pelvis_rise_min_leg: Double
    var pelvis_rise_reject_below_leg: Double
    var knee_extension_min_deg: Double
    var hip_extension_min_deg: Double
    var extension_reject_below_deg: Double
    var seated_knee_min_deg: Double
    var seated_hip_min_deg: Double
    var standing_knee_max_deg: Double
    var standing_hip_max_deg: Double
    var upper_body_rise_support_leg: Double
    var trunk_excursion_support_deg: Double
}

struct BodyStsAnalyzer {
    let config: BodyDetectorConfig
    struct Result {
        var events: [BodyEvent]
        var stats: [String: BodyStats]
        var signals: [BodySignal]
        var warnings: [String]
    }
    func runs(_ valid: [Bool]) -> [ClosedRange<Int>] {
        var result: [ClosedRange<Int>]=[]; var start: Int?
        for i in 0...valid.count {
            if i < valid.count && valid[i] { if start == nil { start=i } }
            else if let a=start { result.append(a...(i-1)); start=nil }
        }
        return result
    }
    func smooth(_ v: [Double?]) -> [Double?] {
        var out=v
        let width=max(3,Int((config.smoothing_s*Double(config.sampling_hz)).rounded()) | 1)
        for run in runs(v.map { $0?.isFinite == true }) {
            let w=min(width,run.count % 2 == 0 ? run.count-1 : run.count)
            if w < 3 { continue }
            for i in run {
                let first=min(max(i-w/2,run.lowerBound),run.upperBound-w+1)
                var matrix=Array(repeating: Array(repeating: 0.0,count: 4),count: 3)
                for j in first..<(first+w) {
                    let x=Double(j-i); let basis=[1,x,x*x]
                    for a in 0...2 {
                        for b in 0...2 { matrix[a][b]+=basis[a]*basis[b] }
                        matrix[a][3]+=basis[a]*v[j]!
                    }
                }
                for a in 0...2 {
                    let div=matrix[a][a]
                    for k in a...3 { matrix[a][k]/=div }
                    for b in 0...2 where b != a {
                        let factor=matrix[b][a]
                        for k in a...3 { matrix[b][k]-=factor*matrix[a][k] }
                    }
                }
                out[i]=matrix[0][3]
            }
        }
        return out
    }
    func analyze(_ raw: [BodySignal], leg: Double) throws -> Result {
        guard raw.count >= 3, leg > 0 else { throw BodyAnalysisError.unavailable("分析数据不足") }
        guard zip(raw,raw.dropFirst()).allSatisfy({ abs($1.timeS-$0.timeS-1/Double(config.sampling_hz)) < 1e-5 }) else {
            throw BodyAnalysisError.unavailable("分析时间网格不均匀")
        }
        let columns: [WritableKeyPath<BodySignal,Double?>]=[\.inertia,\.pelvisZ,\.comZ,\.kneeL,\.kneeR,\.hipL,\.hipR,\.trunk]
        var s=raw
        for key in columns {
            let values=smooth(raw.map { $0[keyPath:key] })
            for i in s.indices { s[i][keyPath:key]=values[i] }
        }
        func empty(_ message: String) -> Result { Result(events: [],stats: [:],signals: s,warnings: [message]) }
        let valid=s.indices.filter { s[$0].inertia != nil && raw[$0].inertia != nil }
        if valid.count < 8 { return empty("有效惯量数据不足，未生成动作参数。") }
        let values=valid.map { s[$0].inertia! }; let low=BodyNumbers.percentile(values,0.1)!; let high=BodyNumbers.percentile(values,0.9)!; let span=high-low
        let residual=valid.map { raw[$0].inertia!-s[$0].inertia! }; let med=BodyNumbers.median(residual)!
        let noise=1.4826*BodyNumbers.median(residual.map { abs($0-med) })!
        if span <= 1e-12 || span/max(abs(high),1e-12) < config.minimum_relative_inertia_range || span < config.minimum_inertia_signal_noise_ratio*noise {
            return empty("坐站惯量差异不足：可能未完成动作、幅度较小或识别不稳；不等于没有 STS。")
        }
        let q=s.map { $0.inertia.map { ($0-low)/span } }
        var speed=[Double?](repeating: nil,count: s.count)
        let finite=runs(q.map { $0 != nil })
        for run in finite where run.count >= 3 {
            for i in run {
                let a=max(run.lowerBound,i-1); let b=min(run.upperBound,i+1)
                speed[i]=(q[b]!-q[a]!)/(s[b].timeS-s[a].timeS)
            }
        }
        let speeds=speed.compactMap { $0 }.map(abs)
        if speeds.isEmpty { return empty("数据缺口过多，无法分段。") }
        let speedLimit=max(1e-8,config.stable_speed_fraction_of_peak*BodyNumbers.percentile(speeds,0.95)!)
        let tolerance=min(config.stable_range_cap,max(config.stable_range_fraction,config.stable_range_noise_multiplier*noise/span))
        let width=max(3,Int((config.stability_window_s*Double(config.sampling_hz)).rounded()) | 1)
        let half=width/2; let hold=max(2,Int(ceil(config.minimum_stable_hold_s*Double(config.sampling_hz)-1e-8)))+1
        struct Anchor { var high: Bool; var a: Int; var b: Int }
        var events: [BodyEvent]=[]
        for run in finite {
            if run.count < width+hold { continue }
            let stable=run.map { i -> Bool in
                guard i >= run.lowerBound+half, i <= run.upperBound-half else { return false }
                let v=(i-half...i+half).map { q[$0]! }
                return v.max()!-v.min()! <= tolerance && abs(speed[i] ?? .greatestFiniteMagnitude) <= speedLimit
            }
            var anchors: [Anchor]=[]
            for high in [false,true] {
                let condition=run.enumerated().map { local,i in stable[local] && (high ? q[i]! >= config.high_state_min : q[i]! <= config.low_state_max) }
                anchors += runs(condition).filter { $0.count >= hold }.map { Anchor(high: high,a: $0.lowerBound+run.lowerBound,b: $0.upperBound+run.lowerBound) }
            }
            anchors.sort { $0.a < $1.a }
            for (left,right) in zip(anchors,anchors.dropFirst()) {
                let a=left.b; let b=right.a
                if left.high == right.high {
                    if !left.high && (a...b).map({ q[$0]! }).max()!-max(q[a]!,q[b]!) >= config.partial_excursion_min {
                        events.append(BodyEvent(direction: "partial",start: a,end: b,startS: s[a].timeS,endS: s[b].timeS,status: "review",reason: "未完成的起立尝试，请复核"))
                    }
                } else { events.append(classify(left.high ? "sit" : "rise",a,b,run,s,leg)) }
            }
            if let first=anchors.first, let last=anchors.last {
                for (a,b) in [(run.lowerBound,first.a),(last.b,run.upperBound)] where b-a >= 2 && abs(q[b]!-q[a]!) >= config.partial_excursion_min {
                    events.append(BodyEvent(direction: "partial",start: a,end: b,startS: s[a].timeS,endS: s[b].timeS,status: "review",reason: "录制边缘或缺失片段缺少稳定平台"))
                }
            }
        }
        events.sort { $0.startS < $1.startS }
        let accepted=events.filter { $0.status == "accepted" }; let up=accepted.filter { $0.direction == "rise" }
        var stats: [String:BodyStats]=[:]
        for key in Set(up.flatMap { $0.metrics.keys }) { stats[key]=BodyNumbers.stats(up.map { $0.metrics[key] ?? nil },cv: key != "trunkMax") }
        stats["descentDuration"]=BodyNumbers.stats(accepted.filter { $0.direction == "sit" }.map { $0.endS-$0.startS })
        var stand:[Double]=[]; var cycles:[Double]=[]; var seated:[Double]=[]
        for i in 0..<max(0,events.count-1) {
            let a=events[i]; let b=events[i+1]
            guard a.status == "accepted", b.status == "accepted", (a.end...b.start).allSatisfy({ s[$0].inertia != nil }) else { continue }
            if a.direction == "rise" && b.direction == "sit" { stand.append(b.startS-a.endS); cycles.append(b.endS-a.startS) }
            if i > 0, a.direction == "sit", b.direction == "rise" {
                let preceding=events[i-1]
                if preceding.direction == "rise" && preceding.status == "accepted" && (preceding.end...a.start).allSatisfy({ s[$0].inertia != nil }) { seated.append(b.startS-a.endS) }
            }
        }
        stats["standingDwell"]=BodyNumbers.stats(stand); stats["cycleDuration"]=BodyNumbers.stats(cycles); stats["seatedDwell"]=BodyNumbers.stats(seated)
        var warnings=["惯量起止点未人工核验；无法确认离座/触座，也可能将深蹲视为 STS。","CV 仅描述本段重复差异，不是临床评分或重测信度；起止点误差会影响时间 CV。"]
        if up.count != 5 { warnings.append("本段识别到 \(up.count) 次完整起立；按实际次数统计，没有补足到 5 次。") }
        if events.contains(where: { $0.status == "review" }) { warnings.append("存在需复核的候选动作，未计入完整起立次数。") }
        return Result(events: events,stats: stats,signals: s,warnings: warnings)
    }
    private func classify(_ direction: String,_ a: Int,_ b: Int,_ run: ClosedRange<Int>,_ s: [BodySignal],_ leg: Double) -> BodyEvent {
        typealias Key = KeyPath<BodySignal,Double?>
        let up=direction == "rise"; let duration=s[b].timeS-s[a].timeS
        let window=Int((config.endpoint_window_s*Double(config.sampling_hz)).rounded())
        func before(_ key: Key) -> Double? { BodyNumbers.median((max(run.lowerBound,a-window)...a).compactMap { s[$0][keyPath:key] }) }
        func after(_ key: Key) -> Double? { BodyNumbers.median((b...min(run.upperBound,b+window)).compactMap { s[$0][keyPath:key] }) }
        func delta(_ key: Key) -> Double? { guard let x=before(key),let y=after(key) else { return nil }; return y-x }
        func rom(_ key: Key) -> Double? {
            let v=(a...b).compactMap { s[$0][keyPath:key] }
            return Double(v.count) < 0.9*Double(b-a+1) ? nil : v.max()!-v.min()!
        }
        let sides: [(Key,Key)] = [(\.kneeL,\.hipL),(\.kneeR,\.hipR)].filter { k,h in
            Double((a...b).filter { s[$0][keyPath:k] != nil && s[$0][keyPath:h] != nil }.count) >= config.minimum_feature_coverage*Double(b-a+1) && [before(k),after(k),before(h),after(h)].allSatisfy { $0 != nil }
        }
        let sign=up ? 1.0 : -1.0; let height=delta(\.pelvisZ).map { $0*sign/leg }
        let extensions=sides.map { k,h in max(-delta(k)!*sign,-delta(h)!*sign) }
        let extend=sides.contains { k,h in -delta(k)!*sign >= config.knee_extension_min_deg || -delta(h)!*sign >= config.hip_extension_min_deg }
        let seated=sides.contains { k,h in (up ? before(k) : after(k))! >= config.seated_knee_min_deg || (up ? before(h) : after(h))! >= config.seated_hip_min_deg }
        let standing=sides.contains { k,h in (up ? after(k) : before(k))! <= config.standing_knee_max_deg || (up ? after(h) : before(h))! <= config.standing_hip_max_deg }
        var reasons:[String]=[]
        if !(config.transition_duration_s[0]...config.transition_duration_s[1]).contains(duration) { reasons.append("时长超出宽松范围") }
        if height == nil || height! < config.pelvis_rise_min_leg { reasons.append("骨盆位移不足") }
        if !extend { reasons.append("关节伸展证据不足") }
        if !seated || !standing { reasons.append("起止姿态证据不足") }
        let rejected=(height != nil && height! < config.pelvis_rise_reject_below_leg) || (!extensions.isEmpty && extensions.max()! < config.extension_reject_below_deg)
        let status=reasons.isEmpty ? "accepted" : rejected ? "rejected" : "review"
        func mae(_ l: Key,_ r: Key) -> Double? {
            BodyNumbers.stats((a...b).map { i -> Double? in guard let x=s[i][keyPath:l],let y=s[i][keyPath:r] else {return nil};return abs(x-y) },cv: false).mean
        }
        let metrics: [String:Double?] = [up ? "riseDuration" : "descentDuration":duration,"kneeLeftRom":rom(\.kneeL),"kneeRightRom":rom(\.kneeR),"hipLeftRom":rom(\.hipL),"hipRightRom":rom(\.hipR),"trunkRom":rom(\.trunk),"trunkMax":(a...b).compactMap { s[$0].trunk }.max(),"pelvisRiseCm":delta(\.pelvisZ).map { $0*100*sign },"comRiseCm":delta(\.comZ).map { $0*100*sign },"kneeAsymmetry":mae(\.kneeL,\.kneeR),"hipAsymmetry":mae(\.hipL,\.hipR)]
        return BodyEvent(direction: direction,start: a,end: b,startS: s[a].timeS,endS: s[b].timeS,status: status,reason: reasons.joined(separator: "；"),metrics: metrics)
    }
}
