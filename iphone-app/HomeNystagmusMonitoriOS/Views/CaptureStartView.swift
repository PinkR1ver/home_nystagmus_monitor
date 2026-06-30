import SwiftUI

struct HeaderView: View {
    let isCompact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 6 : 8) {
            HStack(spacing: 10) {
                Image(systemName: "eye.trianglebadge.exclamationmark.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.cyan, .orange)
                    .font(.system(size: isCompact ? 26 : 30, weight: .semibold))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Home Nystagmus Monitor")
                        .font((isCompact ? Font.title3 : Font.title2).weight(.bold))
                        .foregroundStyle(.primary)
                    Text("iPhone device prototype")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            if !isCompact {
                Text("Capture or import a short eye video. The prototype presents a demo-ready nystagmus dashboard.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CaptureStartView: View {
    let isAnalyzing: Bool
    let errorMessage: String?
    let isCompact: Bool
    let onStartCamera: () -> Void
    let onImportVideo: () -> Void

    var body: some View {
        VStack(spacing: isCompact ? 12 : 16) {
            CameraStageCard(isCompact: isCompact)

            VStack(spacing: 10) {
                Button(action: onStartCamera) {
                    Label("Start Capture", systemImage: "video.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .disabled(isAnalyzing)

                Button(action: onImportVideo) {
                    Label("Import Video", systemImage: "square.and.arrow.down.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryActionButtonStyle())
                .disabled(isAnalyzing)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

struct CameraStageCard: View {
    let isCompact: Bool

    var body: some View {
        VStack(spacing: isCompact ? 10 : 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(.black.gradient)
                    .frame(height: isCompact ? 330 : 390)

                VStack(spacing: isCompact ? 16 : 20) {
                    ZStack {
                        Circle()
                            .stroke(.white.opacity(0.18), lineWidth: 28)
                            .frame(width: isCompact ? 150 : 180, height: isCompact ? 150 : 180)
                        Circle()
                            .stroke(.cyan.opacity(0.78), lineWidth: 3)
                            .frame(width: isCompact ? 118 : 142, height: isCompact ? 118 : 142)
                        Image(systemName: "eye.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white)
                            .font(.system(size: isCompact ? 48 : 58, weight: .semibold))
                    }

                    VStack(spacing: 6) {
                        Text("Align one eye in frame")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("Keep the device steady for 10 to 15 seconds.")
                            .font(isCompact ? .footnote : .subheadline)
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }
                .padding(24)
            }

            HStack(spacing: 10) {
                CaptureHint(symbol: "light.max", title: "Bright", value: "Even light")
                CaptureHint(symbol: "iphone.gen3", title: "Stable", value: "Fixed phone")
                CaptureHint(symbol: "timer", title: "Short", value: "10-15 sec")
            }
        }
    }
}

struct CaptureHint: View {
    let symbol: String
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(.cyan)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
            Text(value)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
