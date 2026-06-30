import AVKit
import SwiftUI
import UIKit

struct DashboardView: View {
    let result: AnalysisResult
    let isCompact: Bool
    let onNewCapture: () -> Void
    @State private var showingEvidenceDetail = false

    var body: some View {
        VStack(spacing: isCompact ? 7 : 9) {
            ResultHeader(result: result, isCompact: isCompact)
            EyeCropPreview(frameURLs: result.eyePreviewFrameURLs, isCompact: isCompact) {
                showingEvidenceDetail = true
            }
            AxisPatternChart(axis: result.horizontalAxis, duration: result.durationSeconds, tint: .red, isCompact: isCompact)
            AxisPatternChart(axis: result.verticalAxis, duration: result.durationSeconds, tint: .blue, isCompact: isCompact)
            MetricStrip(result: result, isCompact: isCompact)
            ProcessingPipeline(steps: result.processingSteps, isCompact: isCompact)
            ClinicalSummaryCard(result: result, isCompact: isCompact)

            Button(action: onNewCapture) {
                Label("Analyze Another Video", systemImage: "arrow.triangle.2.circlepath.camera.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryActionButtonStyle())
            .padding(.top, 1)
        }
        .sheet(isPresented: $showingEvidenceDetail) {
            NavigationStack {
                EyeEvidenceDetailView(result: result)
            }
        }
    }
}

struct ResultHeader: View {
    let result: AnalysisResult
    let isCompact: Bool

    private var accent: Color {
        switch result.finding {
        case .detected:
            return .red
        case .notDetected:
            return .green
        case .inconclusive:
            return .orange
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.16))
                Image(systemName: result.finding == .detected ? "waveform.path.ecg.rectangle.fill" : "checkmark.seal.fill")
                    .font(.system(size: isCompact ? 23 : 27, weight: .semibold))
                    .foregroundStyle(accent)
            }
            .frame(width: isCompact ? 54 : 60, height: isCompact ? 54 : 60)

            VStack(alignment: .leading, spacing: 4) {
                Text(result.finding.rawValue)
                    .font((isCompact ? Font.headline : Font.title3).weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text("\(result.source.rawValue) · \(result.durationText) · \(result.modelName)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 1) {
                Text("\(result.confidencePercent)%")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(accent)
                Text("confidence")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(isCompact ? 11 : 13)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct EyeCropPreview: View {
    let frameURLs: [URL]
    let isCompact: Bool
    let onOpen: () -> Void
    @State private var frames: [UIImage] = []

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                ZStack {
                    if frames.isEmpty {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color(.secondarySystemBackground))
                        Image(systemName: "eye.slash")
                            .foregroundStyle(.secondary)
                    } else {
                        TimelineView(.periodic(from: .now, by: 0.075)) { context in
                            let index = animatedIndex(for: context.date)
                            Image(uiImage: frames[index])
                                .resizable()
                                .scaledToFill()
                                .overlay(alignment: .topLeading) {
                                    Text("CROPPED EYE GIF")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 4)
                                        .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 4))
                                        .padding(6)
                                }
                                .overlay(alignment: .bottomTrailing) {
                                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(7)
                                        .background(.black.opacity(0.58), in: Circle())
                                        .padding(6)
                                }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                }
                .frame(width: isCompact ? 128 : 146, height: isCompact ? 72 : 82)
                .clipped()

                VStack(alignment: .leading, spacing: 5) {
                    Label("Typical nystagmus crop", systemImage: "eye.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    Text("Tap to inspect video, crop frames, and ROI box.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    PatternLegend()
                }
                Spacer(minLength: 0)
                            }
        }
        .buttonStyle(.plain)
        .padding(isCompact ? 10 : 11)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .onAppear(perform: loadFrames)
        .onChange(of: frameURLs) { _, _ in loadFrames() }
    }

    private func animatedIndex(for date: Date) -> Int {
        guard !frames.isEmpty else { return 0 }
        let tick = Int(date.timeIntervalSinceReferenceDate / 0.075)
        return tick % frames.count
    }

    private func loadFrames() {
        frames = frameURLs.compactMap { UIImage(contentsOfFile: $0.path) }
    }
}

struct PatternLegend: View {
    var body: some View {
        HStack(spacing: 8) {
            LegendItem(color: .red, label: "fast")
            LegendItem(color: .blue, label: "slow")
            LegendItem(color: .green, label: "turn")
        }
        .font(.caption2.weight(.semibold))
    }
}

struct LegendItem: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).foregroundStyle(.secondary)
        }
    }
}

struct EyeEvidenceDetailView: View {
    let result: AnalysisResult
    @Environment(\.dismiss) private var dismiss
    @State private var loadedFrames: [LoadedEvidenceFrame] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let url = result.evidenceVideoURL {
                    VStack(alignment: .leading, spacing: 8) {
                        DetailSectionHeader(title: "Nystagmus video", subtitle: result.fileName)
                        VideoPlayer(player: AVPlayer(url: url))
                            .frame(height: 210)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    DetailSectionHeader(title: "Cropped eye loop", subtitle: "The same frames used on the dashboard")
                    EvidenceCropLoop(frames: loadedFrames)
                        .frame(height: 150)
                }

                VStack(alignment: .leading, spacing: 8) {
                    DetailSectionHeader(title: "Crop detail", subtitle: "Original frame with ROI box")
                    EvidenceSourceLoop(frames: loadedFrames)
                        .frame(height: 260)
                }

                RoiDetailTable(frames: result.eyeEvidenceFrames)
            }
            .padding(16)
        }
        .background(AppBackground())
        .navigationTitle("Eye evidence")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
        .onAppear(perform: loadFrames)
    }

    private func loadFrames() {
        loadedFrames = result.eyeEvidenceFrames.compactMap { frame in
            guard let source = UIImage(contentsOfFile: frame.sourceFrameURL.path),
                  let crop = UIImage(contentsOfFile: frame.cropFrameURL.path)
            else {
                return nil
            }
            return LoadedEvidenceFrame(source: source, crop: crop, metadata: frame)
        }
    }
}

struct LoadedEvidenceFrame: Identifiable {
    let id = UUID()
    let source: UIImage
    let crop: UIImage
    let metadata: EyeEvidenceFrame
}

struct DetailSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

struct EvidenceCropLoop: View {
    let frames: [LoadedEvidenceFrame]

    var body: some View {
        ZStack {
            if frames.isEmpty {
                EmptyEvidenceFrame(symbol: "eye.slash", title: "No crop frames")
            } else {
                TimelineView(.periodic(from: .now, by: 0.075)) { context in
                    let frame = frames[index(for: context.date)]
                    Image(uiImage: frame.crop)
                        .resizable()
                        .scaledToFill()
                        .overlay(alignment: .topLeading) {
                            Text(frame.metadata.roiModeLabel.uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 5)
                                .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 5))
                                .padding(8)
                        }
                        .overlay(alignment: .bottomTrailing) {
                            Text("\(frame.metadata.timeSeconds, specifier: "%.2f")s")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(.black.opacity(0.62), in: Capsule())
                                .padding(8)
                        }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    private func index(for date: Date) -> Int {
        guard !frames.isEmpty else { return 0 }
        return Int(date.timeIntervalSinceReferenceDate / 0.075) % frames.count
    }
}

struct EvidenceSourceLoop: View {
    let frames: [LoadedEvidenceFrame]

    var body: some View {
        ZStack {
            if frames.isEmpty {
                EmptyEvidenceFrame(symbol: "rectangle.dashed", title: "No source frames")
            } else {
                TimelineView(.periodic(from: .now, by: 0.12)) { context in
                    let frame = frames[index(for: context.date)]
                    SourceFrameWithROI(frame: frame)
                }
            }
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func index(for date: Date) -> Int {
        guard !frames.isEmpty else { return 0 }
        return Int(date.timeIntervalSinceReferenceDate / 0.12) % frames.count
    }
}

struct SourceFrameWithROI: View {
    let frame: LoadedEvidenceFrame

    var body: some View {
        GeometryReader { proxy in
            let imageSize = frame.source.size
            let displayRect = aspectFitRect(imageSize: imageSize, in: proxy.size)
            let roi = frame.metadata.normalizedCropRect
            let roiRect = CGRect(
                x: displayRect.minX + roi.minX * displayRect.width,
                y: displayRect.minY + roi.minY * displayRect.height,
                width: roi.width * displayRect.width,
                height: roi.height * displayRect.height
            )

            ZStack {
                Image(uiImage: frame.source)
                    .resizable()
                    .scaledToFit()
                    .frame(width: proxy.size.width, height: proxy.size.height)

                Path(roundedRect: roiRect, cornerRadius: 4)
                    .stroke(.yellow, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [7, 4]))

                VStack(alignment: .leading, spacing: 3) {
                    Text(frame.metadata.roiModeLabel)
                    Text("ROI x \(roi.minX, specifier: "%.2f") y \(roi.minY, specifier: "%.2f") w \(roi.width, specifier: "%.2f") h \(roi.height, specifier: "%.2f")")
                }
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.black.opacity(0.64), in: RoundedRectangle(cornerRadius: 6))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(8)
            }
        }
    }

    private func aspectFitRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, container.width > 0, container.height > 0 else {
            return CGRect(origin: .zero, size: container)
        }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        return CGRect(
            x: (container.width - width) / 2.0,
            y: (container.height - height) / 2.0,
            width: width,
            height: height
        )
    }
}

struct RoiDetailTable: View {
    let frames: [EyeEvidenceFrame]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DetailSectionHeader(title: "Crop metadata", subtitle: "\(frames.count) evidence frames")

            HStack(spacing: 8) {
                DetailChip(value: frames.first?.roiModeLabel ?? "No ROI", label: "mode")
                DetailChip(value: averageRectText, label: "avg ROI")
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var averageRectText: String {
        guard !frames.isEmpty else { return "—" }
        var totalWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        for frame in frames {
            totalWidth += frame.normalizedCropRect.width
            totalHeight += frame.normalizedCropRect.height
        }
        let count = CGFloat(frames.count)
        return String(format: "%.2f x %.2f", totalWidth / count, totalHeight / count)
    }
}

struct DetailChip: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 7))
    }
}

struct EmptyEvidenceFrame: View {
    let symbol: String
    let title: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.title2)
            Text(title)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AxisPatternChart: View {
    let axis: AxisSignalSummary
    let duration: Double
    let tint: Color
    let isCompact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(axis.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                Text(axis.present ? "detected" : "clear")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(axis.present ? .red : .green)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background((axis.present ? Color.red : Color.green).opacity(0.12), in: Capsule())
                Spacer()
                Text("\(axis.patternCount) patterns · SPV \(axis.spv, specifier: "%.1f")°/s")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            SignalPatternCanvas(axis: axis, duration: duration, tint: tint)
                .frame(height: isCompact ? 72 : 86)
        }
        .padding(isCompact ? 10 : 11)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct SignalPatternCanvas: View {
    let axis: AxisSignalSummary
    let duration: Double
    let tint: Color

    var body: some View {
        Canvas { context, size in
            let samples = axis.samples
            guard samples.count > 1 else { return }
            let minValue = samples.min() ?? -1
            let maxValue = samples.max() ?? 1
            let range = max(maxValue - minValue, 0.1)

            func xPosition(time: Double) -> CGFloat {
                let progress = min(max(time / max(duration, 0.1), 0), 1)
                return CGFloat(progress) * size.width
            }

            func yPosition(value: Double) -> CGFloat {
                let normalized = (value - minValue) / range
                return size.height - CGFloat(normalized) * size.height
            }

            func value(at time: Double) -> Double {
                let progress = min(max(time / max(duration, 0.1), 0), 1)
                let rawIndex = progress * Double(samples.count - 1)
                let low = Int(floor(rawIndex))
                let high = min(samples.count - 1, low + 1)
                let fraction = rawIndex - Double(low)
                return samples[low] * (1 - fraction) + samples[high] * fraction
            }

            let gridColor = Color.secondary.opacity(0.18)
            for row in 0...3 {
                let y = CGFloat(row) * size.height / 3
                var grid = Path()
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(grid, with: .color(gridColor), lineWidth: 1)
            }

            var trace = Path()
            for (index, sample) in samples.enumerated() {
                let x = CGFloat(index) / CGFloat(samples.count - 1) * size.width
                let y = yPosition(value: sample)
                index == 0 ? trace.move(to: CGPoint(x: x, y: y)) : trace.addLine(to: CGPoint(x: x, y: y))
            }
            context.stroke(trace, with: .color(.green.opacity(0.74)), lineWidth: 1.7)

            for pattern in axis.patterns.prefix(8) {
                let p1 = CGPoint(x: xPosition(time: pattern.startTime), y: yPosition(value: value(at: pattern.startTime)))
                let p2 = CGPoint(x: xPosition(time: pattern.peakTime), y: yPosition(value: value(at: pattern.peakTime)))
                let p3 = CGPoint(x: xPosition(time: pattern.endTime), y: yPosition(value: value(at: pattern.endTime)))

                var first = Path()
                first.move(to: p1)
                first.addLine(to: p2)

                var second = Path()
                second.move(to: p2)
                second.addLine(to: p3)

                context.stroke(first, with: .color(pattern.fastPhaseFirst ? .red : .blue), lineWidth: 3)
                context.stroke(second, with: .color(pattern.fastPhaseFirst ? .blue : .red), lineWidth: 3)
                context.fill(Path(ellipseIn: CGRect(x: p2.x - 2.5, y: p2.y - 2.5, width: 5, height: 5)), with: .color(tint))
            }
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 7))
    }
}

struct MetricStrip: View {
    let result: AnalysisResult
    let isCompact: Bool

    var body: some View {
        HStack(spacing: 7) {
            CompactMetric(value: String(format: "%.1f", result.horizontalAxis.spv), label: "H SPV", tint: .red)
            CompactMetric(value: String(format: "%.1f", result.verticalAxis.spv), label: "V SPV", tint: .blue)
            CompactMetric(value: "\(result.horizontalAxis.patternCount + result.verticalAxis.patternCount)", label: "patterns", tint: .green)
            CompactMetric(value: "\(result.qualityPercent)%", label: "quality", tint: .orange)
        }
    }
}

struct CompactMetric: View {
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 50)
        .padding(.horizontal, 4)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(tint)
                .frame(height: 3)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ProcessingPipeline: View {
    let steps: [String]
    let isCompact: Bool

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(steps.prefix(isCompact ? 5 : 6).enumerated()), id: \.offset) { index, step in
                Text(step)
                    .font(.system(size: isCompact ? 8.5 : 9.5, weight: .bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 6))

                if index < min(steps.count, isCompact ? 5 : 6) - 1 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ClinicalSummaryCard: View {
    let result: AnalysisResult
    let isCompact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Prototype interpretation", systemImage: "doc.text.magnifyingglass")
                .font(.subheadline.weight(.semibold))

            Text(result.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(isCompact ? 2 : 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(isCompact ? 10 : 11)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
