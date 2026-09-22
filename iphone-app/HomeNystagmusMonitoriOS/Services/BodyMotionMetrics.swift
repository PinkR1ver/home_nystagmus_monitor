import Foundation

struct BodyMotionMetric:Codable {
    var key:String;var label:String;var unit:String;var group:String;var value:Double?;var reason:String?;var n:Int=0
}
struct BodyMotionSeries:Codable {var key:String;var label:String;var unit:String;var values:[Double?]}
struct BodyMotionEvent:Codable {var label:String;var startS:Double;var endS:Double;var metrics:[BodyMotionMetric]}
struct BodyMotionReport:Codable {var mode:String;var metrics:[BodyMotionMetric];var series:[BodyMotionSeries];var events:[BodyMotionEvent];var notes:[String];var version="motion-v1"}

enum BodyMotionMath {
    static func average(_ a:[Double])->Double? {a.isEmpty ? nil : a.reduce(0,+)/Double(a.count)}
    static func smooth(_ a:[Double?])->[Double?] {
        a.indices.map {i in let w=a[max(0,i-2)..<min(a.count,i+3)];return a[i] == nil || w.contains(where:{$0 == nil}) ? nil : average(w.compactMap{$0})}
    }
    static func derivative(_ a:[Double?],_ t:[Double])->[Double?] {
        a.indices.map {i in
            guard i>0,i<a.count-1,a[i] != nil,let before=a[i-1],let after=a[i+1],t[i+1]>t[i-1] else{return nil}
            return (after-before)/(t[i+1]-t[i-1])
        }
    }
    static func rms(_ a:[Double],center:Bool=false)->Double? {
        guard !a.isEmpty else{return nil};let mean=center ? average(a)! : 0
        return sqrt(a.reduce(0){$0+pow($1-mean,2)}/Double(a.count))
    }
    static func sampleEntropy(_ a:[Double],m:Int=2)->Double? {
        guard let sd=BodyNumbers.stats(a,cv:false).sd,sd>=1e-10,a.count>=100 else{return nil}
        let r=0.2*sd;var b=0;var c=0
        for i in 0..<(a.count-m) {
            for j in (i+1)..<(a.count-m) {
                if (0..<m).allSatisfy({abs(a[i+$0]-a[j+$0])<=r}) {b+=1;if abs(a[i+m]-a[j+m])<=r {c+=1}}
            }
        }
        return b == 0 || c == 0 ? nil : -log(Double(c)/Double(b))
    }
    static func lyapunov(_ a:[Double],hz:Double)->Double? {
        let lag=max(1,Int((hz*0.2).rounded()));let future=max(2,Int((hz*0.5).rounded()));let limit=a.count-2*lag-future
        guard limit>=100,(rms(a,center:true) ?? 0)>=1e-8 else{return nil}
        var logs=Array(repeating:[Double](),count:future+1)
        func distance(_ i:Int,_ j:Int)->Double {sqrt((0...2).reduce(0){$0+pow(a[i+$1*lag]-a[j+$1*lag],2)})}
        for i in stride(from:0,to:limit,by:3) {
            var best:Int?;var nearest=Double.infinity
            for j in 0..<limit where Double(abs(i-j))>hz {let d=distance(i,j);if d>1e-10 && d<nearest {nearest=d;best=j}}
            if let best {for k in 0...future {let d=distance(i+k,best+k);if d>1e-10 {logs[k].append(log(d))}}}
        }
        guard logs.allSatisfy({$0.count>=20}) else{return nil}
        let x=(0...future).map{Double($0)/hz};let y=logs.map{average($0)!};let xm=average(x)!;let ym=average(y)!
        return x.indices.reduce(0){$0+(x[$1]-xm)*(y[$1]-ym)}/x.reduce(0){$0+pow($1-xm,2)}
    }
}
struct BodyMotionMetrics {
    typealias Math = BodyMotionMath
    static let stsLabels=["riseDuration":"起立时长","descentDuration":"坐下时长","cycleDuration":"坐站坐循环时长","standingDwell":"站立停留","seatedDwell":"坐位间隔","kneeLeftRom":"左膝ROM","kneeRightRom":"右膝ROM","hipLeftRom":"左髋代理ROM","hipRightRom":"右髋代理ROM","pelvisRiseCm":"骨盆抬升","comRiseCm":"CoM抬升","trunkRom":"躯干ROM","trunkMax":"最大躯干前倾","kneeAsymmetry":"膝左右差MAE","hipAsymmetry":"髋左右差MAE"]
    static func stsUnit(_ key:String)->String {key.contains("Duration") || key.contains("Dwell") ? "s" : key.hasSuffix("Cm") ? "模型 cm" : "°"}
    func analyze(mode:String,frames:[BodyPoseFrame],body:BodySegmentModel.Result,duration:Double,coverage:Double,sts:BodyStsAnalyzer.Result?)->BodyMotionReport {
        let t=frames.map{Double($0.timeMs)/1000};let n=t.count;let hz=n>1 ? 1/(t[1]-t[0]) : 20
        var metrics:[BodyMotionMetric]=[];var events:[BodyMotionEvent]=[];var series:[String:BodyMotionSeries]=[:];var order:[String]=[]
        func add(_ key:String,_ label:String,_ unit:String,_ group:String,_ value:Double?,_ reason:String?=nil,_ count:Int=0) {
            let finite=value?.isFinite == true ? value : nil
            metrics.append(BodyMotionMetric(key:key,label:label,unit:unit,group:group,value:finite,reason:finite == nil ? reason ?? "有效数据不足" : nil,n:count))
        }
        func put(_ key:String,_ label:String,_ unit:String,_ values:[Double?],smooth:Bool=true) {
            if series[key] == nil {order.append(key)}
            series[key]=BodyMotionSeries(key:key,label:label,unit:unit,values:smooth ? Math.smooth(values) : values)
        }
        func data(_ key:String)->[Double?] {series[key]?.values ?? Array(repeating:nil,count:n)}
        for (key,label) in [("com","CoM"),("pelvis","骨盆"),("shoulder","肩中点"),("head","头部")] {
            for axis in ["x","y","z"] {put(key+"_"+axis,label+" "+axis+"方向","模型 m",body.channels.map{$0[key+"_"+axis] ?? nil})}
        }
        for ref in ["ankle","com"] {for axis in ["x","y","z"] {let key="inertia_\(ref)_\(axis)";put(key,"\(ref == "ankle" ? "双踝":"CoM")参考 I\(axis)\(axis) / M","m²",body.channels.map{$0[key] ?? nil})}}
        for (key,label,path) in [("knee_l","左膝屈曲",\BodySignal.kneeL),("knee_r","右膝屈曲",\.kneeR),("hip_l","左髋代理角",\.hipL),("hip_r","右髋代理角",\.hipR),("trunk","躯干前倾",\.trunk)] {put(key,label,"°",body.signals.map{$0[keyPath:path]})}
        put("trunk_side","躯干侧倾","°",body.channels.map{$0["trunk_side"] ?? nil})
        let basis=body.basis;let leg=body.legLength
        func point(_ i:Int,_ j:Int)->BodyVector? {let f=frames[i];return f.personCount == 1 && f.points.count == 33 && f.scores.count == 33 && f.scores[j]>=0.5 && f.points[j].finite ? f.points[j] : nil}
        func local(_ i:Int,_ j:Int)->BodyVector? {
            guard let p=point(i,j),let l=point(i,27),let r=point(i,28) else{return nil}
            let v=p-(l+r)*0.5;return BodyVector(v.dot(basis[0]),v.dot(basis[1]),v.dot(basis[2]))
        }
        for side in 0...1 {
            let suffix=side == 0 ? "l":"r";let name=side == 0 ? "左":"右"
            func foot(_ i:Int)->BodyVector? {guard let toe=local(i,31+side),let heel=local(i,29+side) else{return nil};return toe-heel}
            put("fpa_"+suffix,name+"足朝向角（身体前方参考）","°",t.indices.map {i in guard let v=foot(i),hypot(v.x,v.y)>=0.04 else{return nil};return atan2(v.x,v.y)*180 / .pi * (side == 0 ? -1:1)})
            put("pitch_"+suffix,name+"足俯仰角","°",t.indices.map{foot($0).map{atan2($0.z,hypot($0.x,$0.y))*180 / .pi}})
            put("shank_"+suffix,name+"胫骨前倾角","°",t.indices.map{i in guard let k=local(i,25+side),let a=local(i,27+side) else{return nil};return atan2(k.y-a.y,k.z-a.z)*180 / .pi})
            put("ankle_"+suffix,name+"踝几何夹角","°",t.indices.map{i in guard let k=point(i,25+side),let a=point(i,27+side),let toe=point(i,31+side) else{return nil};return BodyNumbers.angle(k,a,toe).map{180-$0}})
            put("heel_y_"+suffix,name+"足跟相对双踝前后位移","模型 m",t.indices.map{local($0,29+side)?.y})
            put("toe_z_"+suffix,name+"前足相对双踝高度","模型 m",t.indices.map{local($0,31+side)?.z})
            put("heel_x_"+suffix,name+"足跟横向位置","模型 m",t.indices.map{local($0,29+side)?.x})
            put("toe_y_"+suffix,name+"前足相对双踝前后位移","模型 m",t.indices.map{local($0,31+side)?.y})
        }
        let lx=data("heel_x_l");let rx=data("heel_x_r")
        put("step_width","双足跟横向间距","腿长倍数",t.indices.map{i in guard let l=lx[i],let r=rx[i] else{return nil};return abs(r-l)/leg})
        for (key,label) in [("pelvis_tilt","骨盆侧倾"),("pelvis_rotation","骨盆水平旋转")] {
            put(key,label,"°",t.indices.map{i in guard let l=local(i,23),let r=local(i,24) else{return nil};let v=r-l;return (key.hasSuffix("tilt") ? atan2(v.z,v.x):atan2(v.y,v.x))*180 / .pi})
        }
        for key in ["com_x","com_y","com_z","pelvis_z","knee_l","knee_r","hip_l","hip_r"] {
            let source=series[key]!;put(key+"_velocity",source.label+"速度",source.unit == "°" ? "°/s":"模型 m/s",Math.derivative(source.values,t),smooth:false)
        }
        for key in order {
            let s=series[key]!;let a=s.values.compactMap{$0};let ok=Double(a.count)>=0.9*Double(n)
            let values:[(String,String,Double?)]=[("_mean","均值",Math.average(a)),("_sd","标准差",BodyNumbers.stats(a,cv:false).sd),("_min","最小值",a.min()),("_max","最大值",a.max()),("_rom","范围 ROM",a.isEmpty ? nil : a.max()!-a.min()!)]
            for (suffix,label,v) in values {add(s.key+suffix,s.label+label,s.unit,"全段运动学",ok ? v:nil,"有效覆盖不足 90%",a.count)}
        }
        add("duration","视频时长","s","数据质量",duration);add("coverage","全身有效帧","%","数据质量",coverage*100,nil,n)
        add("multi","多人帧数","帧","数据质量",Double(frames.filter{$0.personCount>1}.count));add("leg","估计腿长","模型 m","数据质量",leg)
        for (joint,label) in [("hip","髋"),("knee","膝"),("ankle","踝")] {
            let a=data(joint+"_l");let b=data(joint+"_r");let dif=a.indices.compactMap{i->Double? in guard let x=a[i],let y=b[i] else{return nil};return abs(x-y)}
            add(joint+"_mae",label+"左右角度差 MAE","°","左右对称性",Double(dif.count)>=0.9*Double(n) ? Math.average(dif):nil,nil,dif.count)
        }
        if mode == "standing" {
            for axis in ["x","y"] {
                let a=data("com_"+axis);let v=Math.derivative(a,t);let valid=a.compactMap{$0};let ok=Double(valid.count)>=0.9*Double(n)
                put("velocity_"+axis,"CoM "+axis+" 速度","模型 m/s",v,smooth:false)
                add("rmsd_"+axis,"CoM \(axis) RMSD","模型 m","静站摇摆",ok ? Math.rms(valid,center:true):nil)
                add("velocity_rms_"+axis,"CoM \(axis) 速度 RMS","模型 m/s","静站摇摆",ok ? Math.rms(v.compactMap{$0}):nil)
                add("velocity_sd_"+axis,"CoM \(axis) 速度 RMSD","模型 m/s","静站摇摆",ok ? Math.rms(v.compactMap{$0},center:true):nil)
                let window=Int((hz*10).rounded());var blocks:[Double]=[]
                if window>0 {for start in stride(from:0,to:n,by:window) where start+window<=n {let part=Array(a[start..<start+window]);if part.allSatisfy({$0 != nil}),let rms=Math.rms(part.compactMap{$0},center:true){blocks.append(rms)}}}
                add("block_rmsd_\(axis)_cv","CoM \(axis) 每10秒RMSD变异系数","%","分段一致性",BodyNumbers.stats(blocks).cvPercent,"需至少两个完整10秒窗口",blocks.count)
                let continuous=a.allSatisfy{$0 != nil} && duration>=30;let step=max(1,Int((hz/10).rounded()))
                let sampled=continuous ? stride(from:0,to:n,by:step).map{a[$0]!}:[]
                add("entropy_"+axis,"CoM \(axis) 样本熵","无量纲","探索性稳定性",continuous ? Math.sampleEntropy(sampled):nil,"需至少30秒连续数据；常量或匹配不足也不输出")
                add("lyap_"+axis,"CoM \(axis) 短时发散率","1/s","探索性稳定性",continuous ? Math.lyapunov(sampled,hz:hz/Double(step)):nil,"需至少30秒连续非恒定数据")
            }
            let x=data("com_x");let y=data("com_y");let pairs=t.indices.filter{x[$0] != nil && y[$0] != nil}
            if Double(pairs.count)>=0.9*Double(n),pairs.count>1 {
                let mx=Math.average(pairs.map{x[$0]!})!;let my=Math.average(pairs.map{y[$0]!})!;let divisor=Double(pairs.count-1)
                let xx=pairs.reduce(0){$0+pow(x[$1]!-mx,2)}/divisor;let yy=pairs.reduce(0){$0+pow(y[$1]!-my,2)}/divisor
                let xy=pairs.reduce(0){$0+(x[$1]!-mx)*(y[$1]!-my)}/divisor
                add("ellipse","CoM 95%协方差椭圆面积","模型 m²","静站摇摆",Double.pi*5.991*sqrt(max(0,xx*yy-xy*xy)))
                add("rmsd_plane","CoM 平面 RMSD","模型 m","静站摇摆",sqrt(pairs.reduce(0){$0+pow(x[$1]!-mx,2)+pow(y[$1]!-my,2)}/Double(pairs.count)))
            }
            let speeds=t.indices.dropFirst().compactMap{i->Double? in guard let x1=x[i],let y1=y[i],let x0=x[i-1],let y0=y[i-1] else{return nil};return hypot(x1-x0,y1-y0)/(t[i]-t[i-1])}
            let continuous=x.allSatisfy{$0 != nil} && y.allSatisfy{$0 != nil}
            add("path","CoM 平面轨迹长度","模型 m","静站摇摆",continuous ? speeds.reduce(0,+)/hz:nil,"存在缺失，不能报告完整轨迹长度")
            add("speed_mean","CoM 平均平面速度","模型 m/s","静站摇摆",continuous ? Math.average(speeds):nil)
            add("speed_peak","CoM 峰值平面速度","模型 m/s","静站摇摆",continuous ? speeds.max():nil)
            add("support_margin","CoM 到真实支撑边缘距离","m","支撑区域",nil,"未标定地面与足宽；关节点不能确定真实接触边界")
        }
        if mode == "gait" {
            let gait=BodyGaitMetrics.analyze(t:t,hz:hz,leg:leg,series:series)
            metrics += gait.metrics;events += gait.events
            for s in gait.series {put(s.key,s.label,s.unit,s.values,smooth:false)}
        }
        if mode == "sts",let sts {
            for key in sts.stats.keys.sorted() {
                let stat=sts.stats[key]!;let label=Self.stsLabels[key] ?? key;let unit=Self.stsUnit(key)
                add(key,label,unit,"STS 汇总",stat.mean,nil,stat.n);add(key+"_sd",label+" SD",unit,"重复一致性",stat.sd,nil,stat.n)
                add(key+"_cv",label+" CV","%","重复一致性",stat.cvPercent,"重复不足或该参数不适用CV",stat.n)
            }
            for e in sts.events {
                var items=e.metrics.keys.sorted().map {key in BodyMotionMetric(key:key,label:Self.stsLabels[key] ?? key,unit:Self.stsUnit(key),group:"逐次",value:e.metrics[key] ?? nil)}
                for key in order {
                    let s=series[key]!;let a=Array(s.values[e.start...e.end]);let v=a.compactMap{$0};let ok=Double(v.count)>=0.9*Double(a.count)
                    let first=a.first ?? nil;let last=a.last ?? nil;let delta=first != nil && last != nil ? last!-first! : nil
                    let fields:[(String,String,Double?)]=[("rom","ROM",v.isEmpty ? nil:v.max()!-v.min()!),("peak","最大值",v.max()),("min","最小值",v.min()),("start","起点值",first),("end","终点值",last),("delta","终点减起点",delta)]
                    for(suffix,label,value)in fields {items.append(BodyMotionMetric(key:key+suffix,label:s.label+label,unit:s.unit,group:"逐次",value:ok ? value:nil,reason:ok ? nil:"有效覆盖不足90%"))}
                }
                events.append(BodyMotionEvent(label:"\(e.direction == "rise" ? "起立":"坐下") · \(e.status) · \(e.reason)",startS:e.startS,endS:e.endS,metrics:items))
            }
            for key in ["knee_l","knee_r","hip_l","hip_r","trunk","pelvis_z","com_z"] {
                let waves=sts.events.filter{$0.direction == "rise" && $0.status == "accepted"}.compactMap {e->[Double]? in
                    let a=Array(data(key)[e.start...e.end]);guard a.count>=2,a.allSatisfy({$0 != nil}) else{return nil}
                    return (0...100).map {j in let u=Double(j*(a.count-1))/100;let lo=Int(floor(u));let hi=Int(ceil(u));return a[lo]!+(a[hi]!-a[lo]!)*(u-Double(lo))}
                }
                var errors:[Double]=[];var correlations:[Double]=[];var aligned:[Double]=[]
                for i in waves.indices {for j in (i+1)..<waves.count {
                    let a=waves[i];let b=waves[j];let count=Double(a.count)
                    errors.append(sqrt(a.indices.reduce(0){$0+pow(a[$1]-b[$1],2)}/count))
                    aligned.append(sqrt(a.indices.reduce(0){$0+pow((a[$1]-a[0])-(b[$1]-b[0]),2)}/count))
                    let am=Math.average(a)!;let bm=Math.average(b)!;let den=sqrt(a.reduce(0){$0+pow($1-am,2)}*b.reduce(0){$0+pow($1-bm,2)})
                    if den>1e-10 {correlations.append(a.indices.reduce(0){$0+(a[$1]-am)*(b[$1]-bm)}/den)}
                }}
                let scale=BodyNumbers.median(waves.map{$0.max()!-$0.min()!});let source=series[key]!
                add(key+"_wave_r",source.label+"波形相关系数","r","波形一致性",Math.average(correlations),nil,waves.count)
                add(key+"_wave_rmse",source.label+"波形RMSE",source.unit,"波形一致性",Math.average(errors),nil,waves.count)
                add(key+"_wave_nrmse",source.label+"起点对齐NRMSE","%","波形一致性",!aligned.isEmpty && scale != nil && scale!>1e-8 ? 100*Math.average(aligned)!/scale! : nil,nil,waves.count)
                let phases=waves.map {a in Double(a.indices.max(by:{a[$0]<a[$1]})!) }
                add(key+"_peak_phase_sd",source.label+"最大值相位SD","%周期","波形一致性",BodyNumbers.stats(phases,cv:false).sd,nil,waves.count)
            }
        }
        for(key,label)in [("vdi_velocity","VDI-XcoM速度项"),("vdi_momentum","VDI-XcoM角动量项"),("vdi_margin","VDI-XcoM支撑裕度")] {add(key,label,"m","研究扩展",nil,"参考高度、全局速度与支撑模型尚未验证；暂不输出该项")}
        return BodyMotionReport(mode:mode,metrics:metrics,series:order.compactMap{series[$0]},events:events.sorted{$0.startS<$1.startS},notes:[
            "坐标 x向人体右、y向身体前、z向上，来自固定自动站姿参考，未用重力或地面标定。",
            "CoM/足部位移相对逐帧双踝中点；静站仅描述相对摇摆，不代表实验室绝对CoM或CoP。",
            "模型米制长度未经标定；归一化长度使用本次估计腿长。足朝向以身体前方为参考，仅直线向前行走时近似足偏角。",
            "五点移动平均不跨缺失；速度用中央差分。熵 m=2、r=0.2SD；发散率为3维嵌入、0.2秒延迟、0–0.5秒拟合，约10Hz评估。",
            "候选步事件基于足跟前后极值；未证实承重。高阶稳定性指标为探索值，不进行正常/异常诊断。"])
    }
}
