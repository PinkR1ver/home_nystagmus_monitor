import Foundation
@main struct EyeQualitySmoke {
    static func main() {
        let good=(0..<300).map{EyeRawSample(timeMs:$0*1000/30,yawDeg:1,pitchDeg:2)}
        precondition(EyeQuality.unavailable(good) == nil)
        precondition(EyeQuality.unavailable(Array(good.prefix(89))) != nil)
        var sparse=good
        for i in stride(from:0,to:300,by:3) {sparse[i].yawDeg=nil}
        precondition(EyeQuality.unavailable(sparse)?.contains("80%") == true)
        var gap=good
        for i in 50..<61 {gap[i].pitchDeg=nil}
        precondition(EyeQuality.unavailable(gap)?.contains("0.33") == true)
        gap[60].pitchDeg=2
        precondition(EyeQuality.unavailable(gap) == nil)
        precondition(!EyeQuality.usable(gray:Array(repeating:100,count:2160),width:60,height:36))
        precondition(!EyeQuality.usable(gray:[0,255],width:59,height:36))
        precondition(EyeQuality.usable(gray:[80,120],width:60,height:36))
        precondition(EyeQuality.enhanced([0,0,100,100]) == [0,0,255,255])
        precondition(EyeQuality.enhanced([42,42]) == [42,42])
        print("PASS: 3-second/80%/10-frame gates, image size/brightness/contrast and Android histogram enhancement")
    }
}
