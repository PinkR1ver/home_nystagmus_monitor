import SwiftUI
import AVFoundation

struct EyeRegionView: View {
    let videoURL: URL
    let initial: EyeRegion
    let onConfirm: (EyeRegion) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var region = EyeRegion()
    @State private var frame: UIImage?
    @State private var confirmed = false
    @State private var error: String?
    private let accent = Color(red: 1, green: 36/255, blue: 66/255)
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("选择单眼区域").font(.system(size: 26, weight: .bold))
                    Text("框住同一只眼睛，保留完整眼睑。选区会固定应用于整个视频，请确认眼睛全程留在红框内。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if let frame {
                        Image(uiImage: frame).resizable().aspectRatio(contentMode: .fit)
                            .overlay {
                                GeometryReader { geometry in
                                    Rectangle().stroke(accent, lineWidth: 2)
                                        .frame(width: geometry.size.width * region.width, height: geometry.size.height * region.height)
                                        .position(x: geometry.size.width * (region.x + region.width / 2), y: geometry.size.height * (region.y + region.height / 2))
                                }
                            }.accessibilityLabel("首帧预览，红框为所选单眼区域")
                        control("水平位置", value: Binding(get: { region.x }, set: { region.x = $0; confirmed = false }), range: 0...max(0.001, 1-region.width))
                        control("垂直位置", value: Binding(get: { region.y }, set: { region.y = $0; confirmed = false }), range: 0...max(0.001, 1-region.height))
                        control("选区宽度", value: Binding(get: { region.width }, set: { region.width = $0; region.x = min(region.x, 1-$0); confirmed = false }), range: 0.05...1)
                        control("选区高度", value: Binding(get: { region.height }, set: { region.height = $0; region.y = min(region.y, 1-$0); confirmed = false }), range: 0.05...1)
                        Toggle("我已确认红框内为同一只清晰可见的眼睛", isOn: $confirmed)
                        Button {
                            onConfirm(region)
                            dismiss()
                        } label: {
                            Text("确认选区并分析").font(.headline).frame(maxWidth: .infinity).padding(16)
                                .foregroundStyle(.white).background(confirmed ? accent : .gray, in: Capsule())
                        }.disabled(!confirmed || !region.isValid)
                    } else if let error { Text(error).foregroundStyle(.red) }
                    else { ProgressView("读取视频首帧") }
                }.padding(24).frame(maxWidth: 640).frame(maxWidth: .infinity)
            }.background(.white).tint(accent)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("保留视频，返回记录") { dismiss() } } }
        }.task {
            region = initial
            do {
                frame = try await Task.detached {
                    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: videoURL))
                    generator.appliesPreferredTrackTransform = true
                    return UIImage(cgImage: try generator.copyCGImage(at: .zero, actualTime: nil))
                }.value
            } catch { self.error = "无法读取视频首帧：\(error.localizedDescription)" }
        }
    }
    private func control(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text(label); Spacer(); Text("\(Int(value.wrappedValue * 100))%").monospacedDigit() }.font(.subheadline)
            Slider(value: value, in: range).accessibilityLabel(label)
        }
    }
}
