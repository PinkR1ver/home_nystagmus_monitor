import Foundation

/// Kinematic candidates only; mirrors Android heel/toe extrema and gap rules.
enum BodyGaitMetrics {
    struct Result {var metrics:[BodyMotionMetric];var events:[BodyMotionEvent];var series:[BodyMotionSeries]}
    static func analyze(t:[Double],hz:Double,leg:Double,series:[String:BodyMotionSeries])->Result {
        let n=t.count
        func data(_ key:String)->[Double?] {series[key]?.values ?? Array(repeating:nil,count:n)}
        var candidates:[(i:Int,side:Int)]=[];var metrics:[BodyMotionMetric]=[];var events:[BodyMotionEvent]=[];var output:[BodyMotionSeries]=[]
        func add(_ key:String,_ label:String,_ unit:String,_ group:String,_ value:Double?,_ reason:String?=nil,_ count:Int=0) {
            metrics.append(BodyMotionMetric(key:key,label:label,unit:unit,group:group,value:value?.isFinite == true ? value:nil,reason:value == nil ? reason ?? "有效数据不足":nil,n:count))
        }
        for side in 0...1 {
            let a=data("heel_y_"+(side == 0 ? "l":"r"));var last = -100000;let radius=max(2,Int(hz*0.15))
            if n>2*radius {for i in radius..<(n-radius) {
                let window=Array(a[(i-radius)...(i+radius)]);guard window.allSatisfy({$0 != nil}),let value=a[i] else{continue}
                let values=window.compactMap{$0}
                if value == values.max() && value-values.min()!>0.015*leg && Double(i-last)>hz*0.4 {candidates.append((i,side));last=i}
            }}
        }
        let sorted=candidates.sorted{$0.i<$1.i}
        var contact=Array(repeating:[Double?](repeating:nil,count:n),count:2)
        var stance=Array(repeating:[Double](),count:2);var swing=stance;var percentages=stance
        for side in 0...1 {
            let s=side == 0 ? "l":"r";let own=sorted.filter{$0.side == side}.map(\.i);let toe=data("toe_y_"+s);let heel=data("heel_y_"+s)
            for(start,end)in zip(own,own.dropFirst()) {
                let dt=t[end]-t[start]
                guard (0.4...6).contains(dt),(start...end).allSatisfy({toe[$0] != nil && heel[$0] != nil}) else{continue}
                let lo=start+max(1,Int((Double(end-start)*0.15).rounded()));let hi=end-max(1,Int((Double(end-start)*0.1).rounded()))
                if lo<hi {
                    let off=(lo...hi).min(by:{toe[$0]!<toe[$1]!})!
                    let prominence=max(toe[start]!,toe[end]!)-toe[off]!
                    if off>lo && off<hi && prominence>0.04*leg {
                        for i in start..<end {contact[side][i]=i<off ? 1:0}
                        stance[side].append(t[off]-t[start]);swing[side].append(t[end]-t[off]);percentages[side].append(100*(t[off]-t[start])/dt)
                        events.append(BodyMotionEvent(label:"\(side == 0 ? "左":"右")脚候选离地",startS:t[off],endS:t[off],metrics:[
                            BodyMotionMetric(key:"stance",label:"本周期支撑时间估计",unit:"s",group:"逐步",value:t[off]-t[start]),
                            BodyMotionMetric(key:"swing",label:"本周期摆动时间估计",unit:"s",group:"逐步",value:t[end]-t[off]),
                            BodyMotionMetric(key:"pitch_off",label:"离地足俯仰角",unit:"°",group:"逐步",value:data("pitch_"+s)[off])]))
                    }
                }
            }
            output.append(BodyMotionSeries(key:"contact_"+s,label:"\(side == 0 ? "左":"右")足运动学支撑估计（1支撑/0摆动）",unit:"状态",values:contact[side]))
        }
        var times:[Double]=[];var lengths=Array(repeating:[Double](),count:2);var stepTimes=lengths;var strideTimes=lengths
        let left=data("heel_y_l");let right=data("heel_y_r")
        for(index,candidate)in sorted.enumerated() {
            let i=candidate.i;let side=candidate.side;let s=side == 0 ? "l":"r";let other=side == 0 ? "r":"l"
            let a=data("heel_y_"+s)[i];let b=data("heel_y_"+other)[i];let length=a != nil && b != nil ? (a!-b!)/leg:nil
            let prev=index>0 ? sorted[index-1]:nil
            let complete=prev != nil && prev!.side != side && (0.2...3).contains(t[i]-t[prev!.i]) && (prev!.i...i).allSatisfy{left[$0] != nil && right[$0] != nil}
            if complete {times.append(t[i]-t[prev!.i]);stepTimes[side].append(times.last!);if let length,length>0 {lengths[side].append(length)}}
            let prevSame=sorted.prefix(index).last{$0.side == side}
            if let prevSame,index>=2,sorted[index-2].i == prevSame.i,sorted[index-2].side == prevSame.side,complete {strideTimes[side].append(t[i]-t[prevSame.i])}
            events.append(BodyMotionEvent(label:"\(side == 0 ? "左":"右")脚候选初始接触",startS:t[i],endS:t[i],metrics:[
                BodyMotionMetric(key:"step_length",label:"归一化步长",unit:"腿长倍数",group:"逐步",value:complete ? length:nil,reason:complete ? nil:"仅连续交替步有效"),
                BodyMotionMetric(key:"step_time",label:"步时间",unit:"s",group:"逐步",value:complete ? t[i]-t[prev!.i]:nil,reason:complete ? nil:"无完整前一步"),
                BodyMotionMetric(key:"fpa",label:"足朝向角（身体前方参考）",unit:"°",group:"逐步",value:data("fpa_"+s)[i])]))
        }
        add("steps","候选步数","步","步态节律",Double(sorted.count))
        add("cadence","有效步间隔推算步频","步/min","步态节律",times.count>=2 ? 60/BodyMotionMath.average(times)!:nil,nil,times.count)
        func stats(_ key:String,_ label:String,_ unit:String,_ a:[Double]) {
            let st=BodyNumbers.stats(a)
            add(key,label,unit,"步态节律",st.mean,nil,st.n);add(key+"_sd",label+" SD",unit,"逐步变异性",st.sd,nil,st.n);add(key+"_cv",label+" CV","%","逐步变异性",st.cvPercent,nil,st.n)
        }
        for side in 0...1 {
            let s=side == 0 ? "l":"r";let name=side == 0 ? "左":"右"
            stats("step_"+s,name+"归一化步长","腿长倍数",lengths[side]);stats("time_"+s,name+"步时间","s",stepTimes[side]);stats("stride_time_"+s,name+"跨步时间","s",strideTimes[side])
            stats("stance_"+s,name+"支撑时间估计","s",stance[side]);stats("swing_"+s,name+"摆动时间估计","s",swing[side])
            stats("stance_percent_"+s,name+"支撑期占比估计","%",percentages[side]);stats("swing_percent_"+s,name+"摆动期占比估计","%",percentages[side].map{100-$0})
            let a=data("heel_y_"+s).compactMap{$0}
            add("excursion_"+s,name+"足前后摆动幅度","腿长倍数","步态空间",Double(a.count)>=0.9*Double(n) && !a.isEmpty ? (a.max()!-a.min()!)/leg:nil)
        }
        let l=BodyMotionMath.average(lengths[0]);let r=BodyMotionMath.average(lengths[1])
        add("stride","估计跨步长（左右均值之和）","腿长倍数","步态空间",l != nil && r != nil ? l!+r!:nil)
        add("length_si","步长不对称指数","%","左右对称性",l != nil && r != nil && l!+r!>1e-8 ? 200*abs(l!-r!)/(l!+r!):nil)
        let overlap=t.indices.filter{contact[0][$0] != nil && contact[1][$0] != nil}
        add("double","双支撑占比估计","%","接触时相",Double(overlap.count)>=hz ? 100*Double(overlap.filter{contact[0][$0] == 1 && contact[1][$0] == 1}.count)/Double(overlap.count):nil,"需要双侧完整周期重叠",overlap.count)
        add("clearance","足尖地面净空","m","步态空间",nil,"需要地面参考；已有前足相对双踝高度曲线不能当作地面净空")
        add("speed","绝对步速","m/s","步态空间",nil,"未恢复地面坐标及全局轨迹")
        return Result(metrics:metrics,events:events,series:output)
    }
}
