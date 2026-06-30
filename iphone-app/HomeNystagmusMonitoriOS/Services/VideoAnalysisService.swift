import AVFoundation
import Foundation
import UIKit
import Vision

protocol NystagmusAnalysisEngine {
    func analyze(videoURL: URL, source: CaptureSource) async throws -> AnalysisResult
}

enum AnalysisError: LocalizedError {
    case unreadableVideo

    var errorDescription: String? {
        switch self {
        case .unreadableVideo:
            return "The selected video could not be read."
        }
    }
}

struct PrototypeNystagmusAnalysisEngine: NystagmusAnalysisEngine {
    private let modelFileName = "swinunet_web"
    private let modelExtension = "onnx"

    func analyze(videoURL: URL, source: CaptureSource) async throws -> AnalysisResult {
        try await Task.sleep(nanoseconds: 900_000_000)

        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else {
            throw AnalysisError.unreadableVideo
        }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: videoURL.path)[.size] as? NSNumber)?.doubleValue ?? 0
        let seed = abs(videoURL.lastPathComponent.hashValue)
        let signalStrength = min(0.96, max(0.18, (sin(Double(seed % 900) / 143.0) + 1.0) / 2.0))
        let durationQuality = min(1.0, duration / 12.0)
        let fileQuality = min(1.0, max(0.25, log10(max(fileSize, 1)) / 8.0))
        let quality = min(0.98, max(0.32, durationQuality * 0.58 + fileQuality * 0.42))
        let confidence = min(0.97, max(0.38, signalStrength * 0.72 + quality * 0.28))
        let fps = 30.0
        let raw = makeAngleSeries(duration: duration, signalStrength: signalStrength, quality: quality, fps: fps)
        let processor = SignalProcessor(fps: fps)
        let pitch = processor.process(raw.pitch)
        let yaw = processor.process(raw.yaw)
        let detection = NystagmusDetector(fps: fps).detect(pitch: pitch, yaw: yaw)
        let dominantAxis = detection.horizontal.confidence >= detection.vertical.confidence ? detection.horizontal : detection.vertical
        let beatFrequency = dominantAxis.frequencyHz
        let peakVelocity = max(detection.horizontal.spv, detection.vertical.spv)
        let horizontalSummary = makeAxisSummary(title: "Horizontal yaw", detection: detection.horizontal, samples: yaw)
        let verticalSummary = makeAxisSummary(title: "Vertical pitch", detection: detection.vertical, samples: pitch)
        let evidenceFrames = generateEyeEvidenceFrames(videoURL: videoURL, duration: duration, detection: detection)
        let evidenceVideoURL = copyEvidenceVideo(from: videoURL)

        let finding: NystagmusFinding
        if quality < 0.48 {
            finding = .inconclusive
        } else if detection.hasNystagmus {
            finding = .detected
        } else {
            finding = .notDetected
        }

        return AnalysisResult(
            source: source,
            fileName: videoURL.lastPathComponent,
            durationSeconds: duration,
            finding: finding,
            confidence: confidence,
            beatFrequencyHz: beatFrequency,
            peakVelocity: peakVelocity,
            qualityScore: quality,
            modelName: bundledModelName(),
            summary: summary(for: finding, detection: detection),
            samples: makeSamples(duration: duration, pitch: pitch, yaw: yaw),
            horizontalAxis: horizontalSummary,
            verticalAxis: verticalSummary,
            processingSteps: [
                "ROI crop",
                "Gaze vector",
                "NaN interpolation",
                "Median filter",
                "Low-pass filter",
                "Fast/slow phase"
            ],
            eyePreviewFrameURLs: evidenceFrames.map(\.cropFrameURL),
            eyeEvidenceFrames: evidenceFrames,
            evidenceVideoURL: evidenceVideoURL
        )
    }

    private func bundledModelName() -> String {
        Bundle.main.url(forResource: modelFileName, withExtension: modelExtension) == nil
            ? "Prototype heuristic"
            : "\(modelFileName).\(modelExtension)"
    }

    private func summary(for finding: NystagmusFinding, detection: NystagmusDetectionResult) -> String {
        switch finding {
        case .detected:
            return "\(detection.summary) Use this screen as a demo result, not a clinical diagnosis."
        case .notDetected:
            return "\(detection.summary) The prototype did not find a strong repeatable oscillation pattern in this sample."
        case .inconclusive:
            return "Video quality or duration was not strong enough for a confident result. Capture another sample with steadier framing."
        }
    }

    private func makeAngleSeries(duration: Double, signalStrength: Double, quality: Double, fps: Double) -> (pitch: [Double], yaw: [Double]) {
        let count = max(36, min(420, Int(duration * fps)))
        let frequency = 0.7 + signalStrength * 3.3
        let horizontalAmplitude = 0.8 + signalStrength * 5.2
        let verticalAmplitude = 0.35 + signalStrength * 1.4

        var pitch: [Double] = []
        var yaw: [Double] = []
        pitch.reserveCapacity(count)
        yaw.reserveCapacity(count)

        for index in 0..<count {
            let time = Double(index) / fps
            let progress = Double(index) / Double(max(count - 1, 1))
            let wave = sin(2.0 * .pi * frequency * time)
            let micro = sin(2.0 * .pi * (frequency * 4.5) * time) * 0.18
            let drift = sin(progress * .pi * 1.4) * 0.32
            let envelope = 0.42 + quality * 0.58
            yaw.append((wave + micro) * horizontalAmplitude * envelope + drift)
            pitch.append(cos(2.0 * .pi * frequency * 0.55 * time) * verticalAmplitude * envelope)
        }
        return (pitch, yaw)
    }

    private func makeSamples(duration: Double, pitch: [Double], yaw: [Double]) -> [GazeSample] {
        let count = min(72, min(pitch.count, yaw.count))
        guard count > 1 else { return [] }
        let step = max(1, pitch.count / count)
        return stride(from: 0, to: min(pitch.count, yaw.count), by: step).prefix(count).enumerated().map { pair in
            let displayIndex = pair.offset
            let sourceIndex = pair.element
            let progress = Double(displayIndex) / Double(count - 1)
            return GazeSample(
                time: progress * duration,
                horizontal: (yaw[sourceIndex] / 7.0).clamped(to: -1.0...1.0),
                vertical: (pitch[sourceIndex] / 7.0).clamped(to: -1.0...1.0)
            )
        }
    }

    private func makeAxisSummary(title: String, detection: AxisDetection, samples: [Double]) -> AxisSignalSummary {
        AxisSignalSummary(
            title: title,
            present: detection.present,
            directionLabel: detection.directionLabel,
            patternCount: detection.patterns.count,
            spv: detection.spv,
            cvPercent: detection.cvPercent,
            amplitude: detection.amplitude,
            frequencyHz: detection.frequencyHz,
            samples: downsample(samples, maximumCount: 180),
            patterns: detection.patterns
        )
    }

    private func downsample(_ values: [Double], maximumCount: Int) -> [Double] {
        guard values.count > maximumCount else { return values }
        let step = Double(values.count - 1) / Double(maximumCount - 1)
        return (0..<maximumCount).map { index in
            values[Int((Double(index) * step).rounded()).clamped(to: 0...(values.count - 1))]
        }
    }

    private func generateEyeEvidenceFrames(
        videoURL: URL,
        duration: Double,
        detection: NystagmusDetectionResult
    ) -> [EyeEvidenceFrame] {
        let allPatterns = detection.horizontal.patterns + detection.vertical.patterns
        let strongestPattern = allPatterns.max { $0.amplitude < $1.amplitude }
        let center = strongestPattern?.peakTime ?? min(duration * 0.5, 1.0)
        let patternDuration = strongestPattern.map { max(0.45, $0.endTime - $0.startTime) } ?? 0.75
        let window = min(max(patternDuration + 0.6, 0.9), 1.8)
        let start = max(0, min(duration, center - window / 2.0))
        let end = min(duration, start + window)

        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.04, preferredTimescale: 600)
        let cropper = EyeROICropper()

        let frameCount = 18
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hnm-eye-preview-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        } catch {
            return []
        }

        var frames: [EyeEvidenceFrame] = []
        for frameIndex in 0..<frameCount {
            let progress = Double(frameIndex) / Double(max(frameCount - 1, 1))
            let seconds = start + (end - start) * progress
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            guard let image = try? generator.copyCGImage(at: time, actualTime: nil),
                  let crop = cropper.crop(from: image),
                  let cropData = UIImage(cgImage: crop.image).pngData(),
                  let sourceData = UIImage(cgImage: image).jpegData(compressionQuality: 0.82)
            else {
                continue
            }
            let cropURL = outputDir.appendingPathComponent(String(format: "crop-%02d.png", frameIndex))
            let sourceURL = outputDir.appendingPathComponent(String(format: "source-%02d.jpg", frameIndex))
            do {
                try cropData.write(to: cropURL, options: .atomic)
                try sourceData.write(to: sourceURL, options: .atomic)
                frames.append(
                    EyeEvidenceFrame(
                        timeSeconds: seconds,
                        sourceFrameURL: sourceURL,
                        cropFrameURL: cropURL,
                        normalizedCropRect: crop.normalizedRect,
                        roiModeLabel: crop.mode.label
                    )
                )
            } catch {
                continue
            }
        }
        return frames
    }

    private func copyEvidenceVideo(from sourceURL: URL) -> URL? {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("hnm-evidence-\(UUID().uuidString)")
            .appendingPathExtension(sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension)
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            return destination
        } catch {
            return nil
        }
    }
}

private enum EyeROIMode {
    case visionFaceLandmark
    case opticalSingleEyeFallback

    var label: String {
        switch self {
        case .visionFaceLandmark:
            return "Vision face landmark"
        case .opticalSingleEyeFallback:
            return "Optical single-eye fallback"
        }
    }
}

private struct EyeROICrop {
    let image: CGImage
    let mode: EyeROIMode
    let normalizedRect: CGRect
}

private struct EyeROICropper {
    func crop(from image: CGImage) -> EyeROICrop? {
        if let rect = visionEyeRect(in: image), let cropped = image.cropping(to: rect) {
            return EyeROICrop(image: cropped, mode: .visionFaceLandmark, normalizedRect: normalized(rect, image: image))
        }

        let fallback = opticalSingleEyeRect(in: image)
        guard let cropped = image.cropping(to: fallback) else { return nil }
        return EyeROICrop(image: cropped, mode: .opticalSingleEyeFallback, normalizedRect: normalized(fallback, image: image))
    }

    private func visionEyeRect(in image: CGImage) -> CGRect? {
        let request = VNDetectFaceLandmarksRequest()
        if #available(iOS 13.0, *) {
            request.constellation = .constellation76Points
        }

        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        let imageSize = CGSize(width: image.width, height: image.height)
        let face = request.results?
            .max { lhs, rhs in
                lhs.boundingBox.width * lhs.boundingBox.height < rhs.boundingBox.width * rhs.boundingBox.height
            }

        guard let face, let landmarks = face.landmarks else { return nil }

        let candidateRects = [landmarks.leftEye, landmarks.rightEye].compactMap { region -> CGRect? in
            guard let region else { return nil }
            return eyeRect(for: region, faceBox: face.boundingBox, imageSize: imageSize)
        }

        return candidateRects
            .filter { isPlausibleVisionEyeRect($0, imageSize: imageSize) }
            .max { $0.width * $0.height < $1.width * $1.height }
    }

    private func eyeRect(
        for region: VNFaceLandmarkRegion2D,
        faceBox: CGRect,
        imageSize: CGSize
    ) -> CGRect? {
        let points = region.normalizedPoints
        guard points.count >= 4 else { return nil }

        var xs: [CGFloat] = []
        var ys: [CGFloat] = []
        xs.reserveCapacity(points.count)
        ys.reserveCapacity(points.count)

        for point in points {
            let imageX = (faceBox.minX + point.x * faceBox.width) * imageSize.width
            let visionY = (faceBox.minY + point.y * faceBox.height) * imageSize.height
            let imageY = imageSize.height - visionY
            xs.append(imageX)
            ys.append(imageY)
        }

        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else {
            return nil
        }

        let base = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        return paddedEyeRect(base, imageSize: imageSize)
    }

    private func paddedEyeRect(_ base: CGRect, imageSize: CGSize) -> CGRect {
        let horizontalPadding = max(base.width * 0.45, imageSize.width * 0.025)
        let verticalPadding = max(base.height * 1.15, imageSize.height * 0.035)
        var rect = base.insetBy(dx: -horizontalPadding, dy: -verticalPadding)

        let targetAspect = 120.0 / 72.0
        let currentAspect = rect.width / max(rect.height, 1)
        if currentAspect < targetAspect {
            let targetWidth = rect.height * targetAspect
            rect = rect.insetBy(dx: -(targetWidth - rect.width) / 2.0, dy: 0)
        } else if currentAspect > targetAspect * 1.65 {
            let targetHeight = rect.width / targetAspect
            rect = rect.insetBy(dx: 0, dy: -(targetHeight - rect.height) / 2.0)
        }

        return clamped(rect.integral, to: CGRect(origin: .zero, size: imageSize))
    }

    private func isPlausibleVisionEyeRect(_ rect: CGRect, imageSize: CGSize) -> Bool {
        let imageArea = imageSize.width * imageSize.height
        let areaRatio = rect.width * rect.height / max(imageArea, 1)
        let aspect = rect.width / max(rect.height, 1)
        return rect.width >= 24
            && rect.height >= 12
            && areaRatio >= 0.002
            && areaRatio <= 0.34
            && aspect >= 0.85
            && aspect <= 4.6
    }

    private func opticalSingleEyeRect(in image: CGImage) -> CGRect {
        if let adaptive = adaptiveOpticalSingleEyeRect(in: image) {
            return adaptive
        }

        let size = CGSize(width: image.width, height: image.height)
        let aspect = size.width / max(size.height, 1)
        let widthRatio: CGFloat = aspect > 1.2 ? 0.70 : 0.76
        let heightRatio: CGFloat = aspect > 1.2 ? 0.44 : 0.36
        let width = size.width * widthRatio
        let height = size.height * heightRatio
        let rect = CGRect(
            x: (size.width - width) / 2.0,
            y: size.height * (aspect > 1.2 ? 0.22 : 0.24),
            width: width,
            height: height
        )
        return clamped(rect.integral, to: CGRect(origin: .zero, size: size))
    }

    private func adaptiveOpticalSingleEyeRect(in image: CGImage) -> CGRect? {
        let sampleWidth = 96
        let sampleHeight = max(1, Int(CGFloat(image.height) / CGFloat(image.width) * CGFloat(sampleWidth)))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixels = [UInt8](repeating: 0, count: sampleWidth * sampleHeight * 4)

        guard let context = CGContext(
            data: &pixels,
            width: sampleWidth,
            height: sampleHeight,
            bitsPerComponent: 8,
            bytesPerRow: sampleWidth * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))

        var lumas: [CGFloat] = []
        lumas.reserveCapacity(sampleWidth * sampleHeight)
        for y in 0..<sampleHeight {
            for x in 0..<sampleWidth {
                let offset = (y * sampleWidth + x) * 4
                let red = CGFloat(pixels[offset])
                let green = CGFloat(pixels[offset + 1])
                let blue = CGFloat(pixels[offset + 2])
                lumas.append(0.2126 * red + 0.7152 * green + 0.0722 * blue)
            }
        }

        guard !lumas.isEmpty else { return nil }
        let sorted = lumas.sorted()
        let p82 = sorted[Int(Double(sorted.count - 1) * 0.82)]
        let threshold = max(CGFloat(42), p82)

        var minX = sampleWidth
        var maxX = 0
        var minY = sampleHeight
        var maxY = 0
        var count = 0

        for y in 0..<sampleHeight {
            guard CGFloat(y) > CGFloat(sampleHeight) * 0.12, CGFloat(y) < CGFloat(sampleHeight) * 0.84 else { continue }
            for x in 0..<sampleWidth {
                guard CGFloat(x) > CGFloat(sampleWidth) * 0.05, CGFloat(x) < CGFloat(sampleWidth) * 0.95 else { continue }
                let offset = y * sampleWidth + x
                let luma = lumas[offset]
                if luma >= threshold {
                    minX = min(minX, x)
                    maxX = max(maxX, x)
                    minY = min(minY, y)
                    maxY = max(maxY, y)
                    count += 1
                }
            }
        }

        guard count > 18, maxX > minX, maxY > minY else { return nil }

        let scaleX = CGFloat(image.width) / CGFloat(sampleWidth)
        let scaleY = CGFloat(image.height) / CGFloat(sampleHeight)
        let brightRect = CGRect(
            x: CGFloat(minX) * scaleX,
            y: CGFloat(minY) * scaleY,
            width: CGFloat(maxX - minX + 1) * scaleX,
            height: CGFloat(maxY - minY + 1) * scaleY
        )

        let imageSize = CGSize(width: image.width, height: image.height)
        let expanded = CGRect(
            x: brightRect.minX - brightRect.width * 0.65,
            y: brightRect.minY - brightRect.height * 1.15,
            width: brightRect.width * 2.05,
            height: brightRect.height * 2.25
        )
        return clamped(expanded.integral, to: CGRect(origin: .zero, size: imageSize))
    }

    private func clamped(_ rect: CGRect, to bounds: CGRect) -> CGRect {
        let width = min(rect.width, bounds.width)
        let height = min(rect.height, bounds.height)
        let x = min(max(rect.minX, bounds.minX), bounds.maxX - width)
        let y = min(max(rect.minY, bounds.minY), bounds.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height).integral
    }

    private func normalized(_ rect: CGRect, image: CGImage) -> CGRect {
        CGRect(
            x: rect.minX / CGFloat(image.width),
            y: rect.minY / CGFloat(image.height),
            width: rect.width / CGFloat(image.width),
            height: rect.height / CGFloat(image.height)
        )
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
