import AVFoundation
import SwiftUI

/// A manually connected preview for the rear Dual Wide reference image.
struct CameraPreviewView: UIViewRepresentable {
  let camera: CameraManager
  let feed: CameraFeed
  let signals: SignalFrame?
  var showsOverlay = true

  func makeUIView(context: Context) -> PreviewContainerView {
    let view = PreviewContainerView()
    let previewLayer = AVCaptureVideoPreviewLayer(
      sessionWithNoConnection: camera.session
    )
    previewLayer.videoGravity = .resizeAspectFill
    view.layer.addSublayer(previewLayer)

    let overlay = CAShapeLayer()
    overlay.fillColor = UIColor.systemMint.withAlphaComponent(0.42).cgColor
    overlay.strokeColor = UIColor.systemMint.withAlphaComponent(0.92).cgColor
    overlay.lineCap = .round
    overlay.lineJoin = .round
    overlay.lineWidth = 2
    view.layer.addSublayer(overlay)

    context.coordinator.previewLayer = previewLayer
    context.coordinator.overlay = overlay
    camera.attachPreviewLayer(previewLayer, feed: feed)
    return view
  }

  func updateUIView(_ uiView: PreviewContainerView, context: Context) {
    context.coordinator.previewLayer?.frame = uiView.bounds
    context.coordinator.overlay?.frame = uiView.bounds
    context.coordinator.draw(
      signals: showsOverlay ? signals : nil,
      in: uiView.bounds
    )
  }

  func makeCoordinator() -> Coordinator { Coordinator() }

  final class PreviewContainerView: UIView {
    override class var layerClass: AnyClass { CALayer.self }

    override func layoutSubviews() {
      super.layoutSubviews()
      for sublayer in layer.sublayers ?? [] {
        sublayer.frame = bounds
      }
    }
  }

  final class Coordinator {
    var previewLayer: AVCaptureVideoPreviewLayer?
    var overlay: CAShapeLayer?

    func draw(signals: SignalFrame?, in bounds: CGRect) {
      guard let layer = overlay else { return }
      guard let signals, signals.personDetected else {
        layer.path = nil
        return
      }

      let path = UIBezierPath()
      var points: [String: CGPoint] = [:]
      for point in signals.bodyLandmarks {
        points[point.identifier] = CGPoint(
          x: point.x * bounds.width,
          y: point.y * bounds.height
        )
      }

      let connections = [
        ("neck", "root"),
        ("left_shoulder", "right_shoulder"),
        ("left_shoulder", "left_elbow"),
        ("left_elbow", "left_wrist"),
        ("right_shoulder", "right_elbow"),
        ("right_elbow", "right_wrist"),
        ("left_hip", "right_hip"),
        ("left_hip", "left_knee"),
        ("left_knee", "left_ankle"),
        ("right_hip", "right_knee"),
        ("right_knee", "right_ankle"),
        ("neck", "nose"),
        ("nose", "left_eye"),
        ("nose", "right_eye"),
        ("left_eye", "left_ear"),
        ("right_eye", "right_ear"),
      ]

      for (first, second) in connections {
        guard let start = points[first], let end = points[second] else { continue }
        path.move(to: start)
        path.addLine(to: end)
      }

      for point in points.values {
        path.append(
          UIBezierPath(
            arcCenter: point,
            radius: 3.2,
            startAngle: 0,
            endAngle: .pi * 2,
            clockwise: true
          )
        )
      }
      layer.path = path.cgPath
    }
  }
}
