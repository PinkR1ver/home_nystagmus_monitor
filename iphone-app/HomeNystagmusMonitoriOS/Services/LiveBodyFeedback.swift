import AVFoundation
import UIKit
import CoreImage

/// One serial inference queue, dropping late camera frames rather than delaying recording.
final class LiveBodyFeedback:NSObject,AVCaptureVideoDataOutputSampleBufferDelegate {
    let queue=DispatchQueue(label:"motion.live-pose",qos:.userInitiated)
    private let context=CIContext(options:[.cacheIntermediates:false])
    private var detector:BodyPoseDetector?
    private var initializationFailed=false
    private var lastTime = -1.0
    var onFrame:((BodyPoseFrame,CGSize,Double)->Void)?
    var onError:((String)->Void)?
    func captureOutput(_ output:AVCaptureOutput,didOutput sampleBuffer:CMSampleBuffer,from connection:AVCaptureConnection) {
        let timestamp=CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        guard timestamp.isFinite,timestamp-lastTime>=0.15,let buffer=CMSampleBufferGetImageBuffer(sampleBuffer) else{return}
        lastTime=timestamp
        let start=ProcessInfo.processInfo.systemUptime
        do {
            if detector == nil && !initializationFailed {
                do {detector=try BodyPoseDetector()}catch{initializationFailed=true;throw error}
            }
            guard let detector else{return}
            let input=CIImage(cvPixelBuffer:buffer)
            let scale=min(1,960/max(input.extent.width,input.extent.height))
            let scaled=input.transformed(by:CGAffineTransform(scaleX:scale,y:scale))
            guard let cg=context.createCGImage(scaled,from:scaled.extent) else{return}
            let frame=try detector.detect(UIImage(cgImage:cg),timestampMs:Int(timestamp*1000))
            let size=CGSize(width:cg.width,height:cg.height)
            let milliseconds=(ProcessInfo.processInfo.systemUptime-start)*1000
            DispatchQueue.main.async{[weak self] in self?.onFrame?(frame,size,milliseconds)}
        }catch{let message=error.localizedDescription;DispatchQueue.main.async{[weak self] in self?.onError?(message)}}
    }
}

final class LiveBodyOverlay:UIView {
    private let skeleton=CAShapeLayer()
    private let badge=UILabel()
    private var poseFrame:BodyPoseFrame?
    private var imageSize=CGSize.zero
    private var latency=0.0
    private var failure:String?
    private let edges=[(11,12),(11,23),(12,24),(23,24),(11,13),(13,15),(12,14),(14,16),(23,25),(25,27),(24,26),(26,28),(27,29),(29,31),(27,31),(28,30),(30,32),(28,32),(15,17),(15,19),(16,18),(16,20)]
    override init(frame:CGRect) {
        super.init(frame:frame);isUserInteractionEnabled=false
        skeleton.strokeColor=UIColor(red:1,green:36/255,blue:66/255,alpha:1).cgColor;skeleton.fillColor=UIColor.clear.cgColor;skeleton.lineWidth=2.5
        layer.addSublayer(skeleton)
        badge.numberOfLines=3;badge.textColor = .white;badge.font = .preferredFont(forTextStyle:.subheadline);badge.backgroundColor=UIColor.black.withAlphaComponent(0.55);badge.layer.cornerRadius=12;badge.clipsToBounds=true;badge.textAlignment = .center
        addSubview(badge);badge.text="正在加载身体姿态模型…"
    }
    required init?(coder:NSCoder){fatalError("init(coder:) not implemented")}
    func update(_ frame:BodyPoseFrame,size:CGSize,latency:Double){self.poseFrame=frame;imageSize=size;self.latency=latency;failure=nil;setNeedsLayout()}
    func showError(_ message:String){failure=message;setNeedsLayout()}
    override func layoutSubviews() {
        super.layoutSubviews();skeleton.frame=bounds
        badge.frame=CGRect(x:20,y:safeAreaInsets.top+70,width:max(0,bounds.width-40),height:72)
        let path=UIBezierPath();defer{skeleton.path=path.cgPath}
        if let failure {badge.text="姿态预览不可用\n"+failure;return}
        guard let frame=poseFrame else{return}
        guard frame.personCount == 1,frame.imagePoints.count == 33,frame.scores.count == 33,imageSize.width>0,imageSize.height>0 else {
            badge.text=frame.personCount>1 ? "检测到多人 · 请保持仅一人入镜":"未检测到完整人体 · 请调整取景";return
        }
        // Match AVCaptureVideoPreviewLayer.resizeAspectFill, upright pixel output.
        let scale=max(bounds.width/imageSize.width,bounds.height/imageSize.height)
        let width=imageSize.width*scale;let height=imageSize.height*scale;let origin=CGPoint(x:(bounds.width-width)/2,y:(bounds.height-height)/2)
        func point(_ i:Int)->CGPoint {CGPoint(x:origin.x+frame.imagePoints[i].x*width,y:origin.y+frame.imagePoints[i].y*height)}
        for(a,b)in edges where frame.scores[a]>=0.3 && frame.scores[b]>=0.3 {
            path.move(to:point(a));path.addLine(to:point(b))
        }
        for i in frame.imagePoints.indices where frame.scores[i]>=0.3 {
            let p=point(i);path.append(UIBezierPath(ovalIn:CGRect(x:p.x-2,y:p.y-2,width:4,height:4)))
        }
        let required=[0,11,12,23,24,27,28,31,32]
        let full=required.allSatisfy {i in frame.scores[i]>=0.5 && bounds.insetBy(dx:10,dy:10).contains(point(i))}
        badge.text="\(full ? "一人 · 全身入镜":"请让头部与双脚完整入镜")\n姿态预览 \(Int(latency)) ms · 保存后完整分析"
    }
}
