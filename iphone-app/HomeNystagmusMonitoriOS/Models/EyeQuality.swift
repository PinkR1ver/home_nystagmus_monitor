import Foundation

struct EyeRawSample:Codable,Equatable {
    var timeMs:Int
    var yawDeg:Double?
    var pitchDeg:Double?
}
enum EyeQuality {
    static func unavailable(_ samples:[EyeRawSample],hz:Int=30)->String? {
        if samples.count<hz*3 {return "有效视频不足 3 秒，请重新录制"}
        let valid=samples.map{$0.yawDeg?.isFinite == true && $0.pitchDeg?.isFinite == true}
        if Double(valid.filter{$0}.count)/Double(valid.count)<0.8 {return "可用眼部图像不足 80%，请检查选区、照明并重新录制"}
        var run=0;var longest=0
        for value in valid {run=value ? 0:run+1;longest=max(longest,run)}
        return longest>hz/3 ? "眼部图像连续缺失超过约 0.33 秒，无法可靠判断快慢相":nil
    }
    static func usable(gray:[Double],width:Int,height:Int)->Bool {
        guard width>=60,height>=36,!gray.isEmpty else{return false}
        let mean=gray.reduce(0,+)/Double(gray.count)
        let variance=gray.reduce(0){$0+pow($1-mean,2)}/Double(gray.count)
        return (12...243).contains(mean) && variance>=36
    }
    static func enhanced(_ input:[Int])->[Int] {
        guard !input.isEmpty else{return []}
        var gray=input.map{min(255,max(0,$0))};var histogram=Array(repeating:0,count:256)
        for value in gray {histogram[value]+=1}
        var cdf=histogram;var acc=0
        for i in cdf.indices {acc+=histogram[i];cdf[i]=acc}
        let first=cdf.first(where:{$0>0}) ?? 0
        if gray.count>first {
            gray=gray.map{min(255,max(0,Int(Double(cdf[$0]-first)/Double(gray.count-first)*255)))}
        }
        let sorted=gray.sorted();let p1=sorted[Int(0.01*Double(sorted.count-1))];let p99=sorted[Int(0.99*Double(sorted.count-1))]
        if p99>p1 {gray=gray.map{min(255,max(0,Int(Double($0-p1)/Double(p99-p1)*255)))}}
        return gray
    }
}
