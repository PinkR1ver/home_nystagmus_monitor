import SwiftUI
import Charts

struct BodyMotionReportView:View {
    let report:BodyAnalysisReport
    @State private var channel="com_z"
    private let accent=Color(red:1,green:36/255,blue:66/255)
    var body:some View {
        if let motion=report.motion {
            VStack(alignment:.leading,spacing:22) {
                Text("完整运动参数").font(.title3.bold())
                Text("距离为未标定模型尺度，所有缺失与未计算项保留原因。")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("曲线通道",selection:$channel) {
                    ForEach(motion.series,id:\.key) {s in Text(s.label).tag(s.key)}
                }.pickerStyle(.menu)
                if let selected=motion.series.first(where:{$0.key == channel}) {
                    Text(selected.label+"（"+selected.unit+"）").font(.headline)
                    Chart {
                        ForEach(Array(selected.values.enumerated()),id:\.offset) {index,value in
                            if let value,index<report.signals.count {
                                // Separate series across gaps to avoid drawing false continuous paths.
                                LineMark(x:.value("时间",report.signals[index].timeS),y:.value(selected.unit,value),series:.value("连续段",segment(selected.values,index)))
                                    .foregroundStyle(accent)
                            }
                        }
                    }.frame(height:190)
                }
                ForEach(groups(motion.metrics),id:\.self) {group in
                    DisclosureGroup(group) {
                        VStack(spacing:12) {
                            ForEach(motion.metrics.filter{$0.group == group},id:\.key) {metricRow($0)}
                        }.padding(.top,12)
                    }.padding(18).background(Color(white:0.97),in:RoundedRectangle(cornerRadius:16))
                }
                Text("逐次 / 逐步事件").font(.headline)
                if motion.events.isEmpty {Text("没有满足规则的完整事件；请查看质量信息与曲线。") .font(.subheadline).foregroundStyle(.secondary)}
                ForEach(Array(motion.events.enumerated()),id:\.offset) {_,event in
                    DisclosureGroup {
                        VStack(spacing:12) {
                            ForEach(Array(event.metrics.enumerated()),id:\.offset) {_,metric in metricRow(metric)}
                        }.padding(.top,12)
                    }label:{
                        VStack(alignment:.leading,spacing:6) {
                            Text(event.label).font(.subheadline.bold())
                            Text(String(format:"%.2f–%.2f 秒",event.startS,event.endS)).font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(18).background(Color(white:0.97),in:RoundedRectangle(cornerRadius:16))
                }
                ForEach(motion.notes,id:\.self) {Text($0).font(.caption).foregroundStyle(.secondary)}
            }.tint(accent)
        }
    }
    private func groups(_ metrics:[BodyMotionMetric])->[String] {
        var seen=Set<String>();return metrics.map(\.group).filter{seen.insert($0).inserted}
    }
    private func segment(_ values:[Double?],_ index:Int)->Int {
        var start=index
        while start>0 && values[start-1] != nil {start-=1}
        return start
    }
    private func metricRow(_ metric:BodyMotionMetric)->some View {
        VStack(alignment:.leading,spacing:5) {
            HStack(alignment:.firstTextBaseline) {
                Text(metric.label).font(.subheadline)
                Spacer(minLength:12)
                Text(metric.value.map{String(format:"%.3f",$0)} ?? "—").font(.subheadline.monospacedDigit()).foregroundStyle(metric.value == nil ? .secondary:accent)
            }
            Text(metric.value == nil ? metric.reason ?? "有效数据不足" : metric.unit+(metric.n>0 ? " · n=\(metric.n)":""))
                .font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
}
