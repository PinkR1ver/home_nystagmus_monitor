import Foundation

/// Direct port of Android's 14-segment model and ankle-reference tensor projection.
struct BodySegmentModel {
    var config: BodySegmentConfig
    struct Result {
        var signals: [BodySignal]
        var legLength: Double
        var basis: [BodyVector]
        var warnings: [String]
        var channels: [[String: Double?]]
    }
    private struct Segment {
        var kind: String
        var a: BodyVector
        var b: BodyVector
        var axes: [BodyVector]
    }
    private func frame(_ zHint: BodyVector, _ xHint: BodyVector, _ yHint: BodyVector) throws -> [BodyVector] {
        let z = try zHint.unit()
        let projected = xHint-z*xHint.dot(z)
        let x = try (projected.norm > 1e-8 ? projected : yHint.cross(z)).unit()
        return [x,try z.cross(x).unit(),z]
    }
    private func segments(_ p: [BodyVector]) throws -> [Segment] {
        let shoulders=(p[11]+p[12])*0.5; let hips=(p[23]+p[24])*0.5
        let torso=try frame(shoulders-hips,p[24]-p[23],BodyVector(0,0,1))
        let right=torso[0]; let forward=torso[1]; let head=(p[7]+p[8])*0.5
        var out = [Segment(kind: "HeadNeck", a: shoulders, b: head, axes: try frame(head-shoulders,p[8]-p[7],forward)),
                   Segment(kind: "Trunk", a: shoulders, b: hips, axes: try frame(shoulders-hips,p[12]-p[11],forward))]
        for side in 0...1 {
            let ends: [(String,BodyVector,BodyVector)] = [
                ("Upperarm",p[11+side],p[13+side]),("Forearm",p[13+side],p[15+side]),
                ("Hand",p[15+side],(p[17+side]+p[19+side])*0.5),("Thigh",p[23+side],p[25+side]),
                ("Shank",p[25+side],p[27+side]),("Foot",p[27+side],p[31+side])]
            for (kind,a,b) in ends {
                let axes: [BodyVector]
                if kind == "Foot" {
                    let y=try (b-a).unit(); let x=try (right-y*right.dot(y)).unit()
                    axes=[x,y,try x.cross(y).unit()]
                } else { axes=try frame(a-b,right,forward) }
                out.append(Segment(kind: kind,a: a,b: b,axes: axes))
            }
        }
        return out
    }
    func compute(_ frames: [BodyPoseFrame], subject: BodySubject) throws -> Result {
        guard (5...300).contains(subject.massKg), (50...250).contains(subject.heightCm), let params=config.profiles[subject.profile] else {
            throw BodyAnalysisError.unavailable("请选择有效的身高、体重和体段参数组")
        }
        let required=[7,8,11,12,13,14,15,16,17,18,19,20,23,24,25,26,27,28,31,32]
        let core=[11,12,23,24,25,26,27,28]
        func valid(_ f: BodyPoseFrame) -> Bool {
            f.personCount == 1 && f.points.count == 33 && f.scores.count == 33 && required.allSatisfy { f.points[$0].finite } && core.allSatisfy { f.scores[$0] >= 0.3 }
        }
        let usable=frames.filter(valid)
        guard usable.count >= 40 else { throw BodyAnalysisError.unavailable("可用全身关键点不足，请确保只有一人、头脚完整入镜") }
        let knee=usable.map { f -> Double in
            let angles=[BodyNumbers.angle(f.points[23],f.points[25],f.points[27]),BodyNumbers.angle(f.points[24],f.points[26],f.points[28])].compactMap { $0 }
            return angles.isEmpty ? .nan : angles.reduce(0,+)/Double(angles.count)
        }
        guard let cutoff=BodyNumbers.percentile(knee,0.2) else { throw BodyAnalysisError.unavailable("无法建立伸膝参考") }
        let candidates=zip(usable,knee).filter { $0.1 <= cutoff }.map { $0.0 }
        func avg(_ v: [BodyVector]) -> BodyVector { v.reduce(BodyVector(0,0,0),+) * (1/Double(v.count)) }
        let z=try avg(candidates.map { ($0.points[11]+$0.points[12])*0.5-($0.points[27]+$0.points[28])*0.5 }).unit()
        let xr=avg(candidates.map { $0.points[24]-$0.points[23] })
        let x=try (xr-z*xr.dot(z)).unit(); let y=try z.cross(x).unit(); let basis=[x,y,z]
        let all=usable.compactMap { try? segments($0.points) }
        guard all.count >= 20 else { throw BodyAnalysisError.unavailable("体段长度无法稳定估计，请重新拍摄") }
        var lengths: [String:Double] = [:]
        for kind in params.keys {
            lengths[kind]=config.fixed_inertia_lengths_m[kind] ?? BodyNumbers.median(all.flatMap { $0.filter { $0.kind == kind }.map { ($0.b-$0.a).norm } })
        }
        guard let thigh=lengths["Thigh"], let shank=lengths["Shank"] else { throw BodyAnalysisError.unavailable("缺少下肢长度参数") }
        var signals: [BodySignal]=[]; var channels: [[String:Double?]]=[]
        for f in frames {
            var signal=BodySignal(timeS: Double(f.timeMs)/1000,quality: 0)
            var detail: [String:Double?]=[:]
            if valid(f) {
                do {
                    let p=f.points; let seg=try segments(p); let ankle=(p[27]+p[28])*0.5
                    let hip=(p[23]+p[24])*0.5; let shoulder=(p[11]+p[12])*0.5; let trunk=shoulder-hip
                    var com=BodyVector(0,0,0); var inertia=0.0; var mass=0.0
                    func projectedInertia(_ segment: Segment, _ axis: BodyVector, _ origin: BodyVector) throws -> Double {
                        guard let par=params[segment.kind], let length=lengths[segment.kind], par.gyration_xyz.count == 3 else { throw BodyAnalysisError.unavailable("体段参数不完整") }
                        let center=segment.a+(segment.b-segment.a)*par.com_fraction; let d=center-origin
                        let intrinsic=(0..<3).reduce(0.0) { $0 + length*length*pow(par.gyration_xyz[$1],2)*pow(axis.dot(segment.axes[$1]),2) }
                        return par.mass_fraction*(intrinsic+d.dot(d)-pow(d.dot(axis),2))
                    }
                    for segment in seg {
                        guard let par=params[segment.kind] else { throw BodyAnalysisError.unavailable("体段参数不完整") }
                        let center=segment.a+(segment.b-segment.a)*par.com_fraction
                        com=com+center*par.mass_fraction; mass+=par.mass_fraction
                        inertia += try projectedInertia(segment,x,ankle)
                    }
                    guard abs(mass-1) < 1e-6 else { throw BodyAnalysisError.unavailable("体段质量比例无效") }
                    for (name,point) in [("com",com),("pelvis",hip),("shoulder",shoulder),("head",(p[7]+p[8])*0.5)] {
                        for (i,axis) in basis.enumerated() { detail["\(name)_\(["x","y","z"][i])"]=(point-ankle).dot(axis) }
                    }
                    detail["trunk_side"]=atan2(trunk.dot(x),trunk.dot(z))*180 / .pi
                    for (reference,origin) in [("ankle",ankle),("com",com)] {
                        for (i,axis) in basis.enumerated() {
                            detail["inertia_\(reference)_\(["x","y","z"][i])"] = try seg.reduce(0.0) { try $0+projectedInertia($1,axis,origin) }
                        }
                    }
                    signal=BodySignal(timeS: Double(f.timeMs)/1000,inertia: inertia,pelvisZ: (hip-ankle).dot(z),comZ: (com-ankle).dot(z),
                        kneeL: BodyNumbers.angle(p[23],p[25],p[27]),kneeR: BodyNumbers.angle(p[24],p[26],p[28]),
                        hipL: BodyNumbers.angle(p[23]+trunk,p[23],p[25]),hipR: BodyNumbers.angle(p[24]+trunk,p[24],p[26]),
                        trunk: atan2(trunk.dot(y),trunk.dot(z))*180 / .pi,quality: required.map { f.scores[$0] }.min() ?? 0)
                } catch { detail=[:] }
            }
            signals.append(signal); channels.append(detail)
        }
        var warnings=["单目模型尺度、重力方向未标定；位移相对逐帧踝中点。","自动选择较伸膝帧建立站姿参考；未验证真实站姿。髋角为躯干—大腿代理角。"]
        if Double(signals.filter { $0.quality < 0.5 }.count) > 0.2*Double(signals.count) { warnings.append("部分体段置信度较低，CoM/惯量可能受手部等点位误差影响。") }
        if frames.contains(where: { $0.personCount > 1 }) { warnings.append("检测到多人：对应帧已排除，未跨缺口拼接动作。") }
        return Result(signals: signals,legLength: thigh+shank,basis: basis,warnings: warnings,channels: channels)
    }
}
