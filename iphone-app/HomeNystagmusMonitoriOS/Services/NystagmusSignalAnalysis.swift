import Foundation

struct GazeVector3D {
    let x: Double
    let y: Double
    let z: Double
}

struct GazeAngles {
    let pitchDeg: Double
    let yawDeg: Double
}

struct AxisDetection {
    let present: Bool
    let direction: String
    let directionLabel: String
    let amplitude: Double
    let frequencyHz: Double
    let confidence: Double
    let spv: Double
    let cvPercent: Double
    let patterns: [SignalPattern]
}

struct NystagmusDetectionResult {
    let horizontal: AxisDetection
    let vertical: AxisDetection
    let summary: String
    let hasNystagmus: Bool
}

enum GazeAngleFitter {
    static func vectorToAngles(_ vector: GazeVector3D) -> GazeAngles {
        let pitch = asin((-vector.y).clamped(to: -1.0...1.0))
        let yaw = atan2(-vector.x, -vector.z)
        return GazeAngles(pitchDeg: pitch * 180.0 / .pi, yawDeg: yaw * 180.0 / .pi)
    }
}

struct SignalProcessor {
    let fps: Double
    let highPassCutoffHz: Double = 0.1
    let lowPassCutoffHz: Double = 6.0
    let medianKernelSize: Int = 5

    func process(_ raw: [Double]) -> [Double] {
        guard !raw.isEmpty else { return [] }
        let interpolated = interpolateNaN(raw)
        let median = medianFilter(interpolated, kernelSize: medianKernelSize)
        let highPassed = highPassFilter(median, cutoffHz: highPassCutoffHz)
        return lowPassFilter(highPassed, cutoffHz: lowPassCutoffHz)
    }

    private func interpolateNaN(_ raw: [Double]) -> [Double] {
        let valid = raw.indices.filter { !raw[$0].isNaN }
        guard let first = valid.first else { return Array(repeating: 0, count: raw.count) }
        guard valid.count > 1 else { return Array(repeating: raw[first], count: raw.count) }

        var out = raw
        let last = valid.last ?? first
        for index in 0..<first {
            out[index] = raw[first]
        }
        if last + 1 < raw.count {
            for index in (last + 1)..<raw.count {
                out[index] = raw[last]
            }
        }

        for pairIndex in 0..<(valid.count - 1) {
            let left = valid[pairIndex]
            let right = valid[pairIndex + 1]
            out[left] = raw[left]
            guard right > left + 1 else { continue }
            for index in (left + 1)..<right {
                let t = Double(index - left) / Double(right - left)
                out[index] = raw[left] * (1.0 - t) + raw[right] * t
            }
        }
        return out.map { $0.isNaN ? 0 : $0 }
    }

    private func medianFilter(_ values: [Double], kernelSize: Int) -> [Double] {
        guard values.count >= 3 else { return values }
        let kernel = kernelSize.isMultiple(of: 2) ? kernelSize + 1 : kernelSize
        let radius = kernel / 2
        return values.indices.map { index in
            let start = max(0, index - radius)
            let end = min(values.count - 1, index + radius)
            return median(Array(values[start...end]))
        }
    }

    private func highPassFilter(_ values: [Double], cutoffHz: Double) -> [Double] {
        guard values.count > 1 else { return values }
        let low = lowPassFilter(values, cutoffHz: cutoffHz)
        return zip(values, low).map { original, baseline in
            original - baseline
        }
    }

    private func lowPassFilter(_ values: [Double], cutoffHz: Double) -> [Double] {
        guard values.count > 1 else { return values }
        let dt = 1.0 / fps
        let rc = 1.0 / (2.0 * .pi * cutoffHz)
        let alpha = dt / (rc + dt)
        var out = values
        for index in 1..<out.count {
            out[index] = out[index - 1] + alpha * (values[index] - out[index - 1])
        }
        return out
    }
}

struct NystagmusDetector {
    let fps: Double
    private let velocityThreshold = 5.0
    private let minAmplitude = 5.0
    private let minFrequency = 0.5
    private let maxFrequency = 6.0

    func detect(pitch: [Double], yaw: [Double]) -> NystagmusDetectionResult {
        let horizontal = analyzeSingleAxis(yaw, isHorizontal: true)
        let vertical = analyzeSingleAxis(pitch, isHorizontal: false)
        let has = horizontal.present || vertical.present
        let summary: String
        switch (horizontal.present, vertical.present) {
        case (false, false):
            summary = "No obvious nystagmus pattern was detected."
        case (true, false):
            summary = "Horizontal nystagmus signal detected. Fast phase: \(horizontal.directionLabel)."
        case (false, true):
            summary = "Vertical nystagmus signal detected. Fast phase: \(vertical.directionLabel)."
        case (true, true):
            summary = "Mixed nystagmus signal detected. Horizontal \(horizontal.directionLabel), vertical \(vertical.directionLabel)."
        }
        return NystagmusDetectionResult(horizontal: horizontal, vertical: vertical, summary: summary, hasNystagmus: has)
    }

    private func analyzeSingleAxis(_ angles: [Double], isHorizontal: Bool) -> AxisDetection {
        guard angles.count >= 3 else {
            return AxisDetection(present: false, direction: "none", directionLabel: "None", amplitude: 0, frequencyHz: 0, confidence: 0, spv: 0, cvPercent: 0, patterns: [])
        }
        let velocity = computeVelocity(angles)
        let direction = analyzeDirection(velocity)
        let frequency = computeFrequency(angles)
        let amplitude = percentile(angles, 95) - percentile(angles, 5)
        let analysis = analyzePatterns(angles, isHorizontal: isHorizontal)
        let patterns = analysis.patterns
        let cv = analysis.cvPercent
        let spv = analysis.spv
        let present = analysis.hasNystagmus
        let directionLabel: String
        switch analysis.direction {
        case "right", "left", "up", "down":
            directionLabel = analysis.direction
        case "bidirectional":
            directionLabel = "bidirectional"
        default:
            directionLabel = "none"
        }
        return AxisDetection(
            present: present,
            direction: analysis.direction,
            directionLabel: directionLabel,
            amplitude: amplitude,
            frequencyHz: frequency,
            confidence: direction.confidence,
            spv: spv,
            cvPercent: cv,
            patterns: patterns
        )
    }

    private struct PatternAnalysis {
        let patterns: [SignalPattern]
        let direction: String
        let spv: Double
        let cvPercent: Double
        let hasNystagmus: Bool
    }

    private struct CandidatePattern {
        let pattern: SignalPattern
        let slowSlope: Double
        let fastSlope: Double
        let totalTime: Double
        let timePoint: Double
    }

    private func analyzePatterns(_ angles: [Double], isHorizontal: Bool) -> PatternAnalysis {
        let turningPoints = findTurningPoints(angles)
        guard turningPoints.count >= 3 else {
            return PatternAnalysis(patterns: [], direction: "none", spv: 0, cvPercent: 0, hasNystagmus: false)
        }

        var candidates: [CandidatePattern] = []
        for index in 1..<(turningPoints.count - 1) {
            let left = turningPoints[index - 1]
            let middle = turningPoints[index]
            let right = turningPoints[index + 1]
            let leftValue = angles[left]
            let middleValue = angles[middle]
            let rightValue = angles[right]

            guard middleValue > leftValue, middleValue > rightValue else { continue }

            let firstSlope = (angles[middle] - angles[left]) * fps / Double(max(middle - left, 1))
            let secondSlope = (angles[right] - angles[middle]) * fps / Double(max(right - middle, 1))
            let fastPhaseFirst = abs(firstSlope) > abs(secondSlope)
            let fastSlope = fastPhaseFirst ? firstSlope : secondSlope
            let slowSlope = fastPhaseFirst ? secondSlope : firstSlope
            let amplitude = max(abs(middleValue - leftValue), abs(middleValue - rightValue))
            let duration = Double(right - left) / fps
            let ratio = abs(fastSlope) / max(abs(slowSlope), 0.0001)

            guard amplitude >= minAmplitude else { continue }
            guard duration >= 0.15, duration <= 1.5 else { continue }
            guard fastSlope * slowSlope <= 0 else { continue }
            guard ratio >= 1.2, ratio <= 10.0 else { continue }

            let pattern = SignalPattern(
                    startTime: Double(left) / fps,
                    peakTime: Double(middle) / fps,
                    endTime: Double(right) / fps,
                    amplitude: amplitude,
                    fastPhaseFirst: fastPhaseFirst
                )
            candidates.append(
                CandidatePattern(
                    pattern: pattern,
                    slowSlope: slowSlope,
                    fastSlope: fastSlope,
                    totalTime: duration,
                    timePoint: Double(middle) / fps
                )
            )
        }

        guard !candidates.isEmpty else {
            return PatternAnalysis(patterns: [], direction: "none", spv: 0, cvPercent: 0, hasNystagmus: false)
        }

        let positiveHasConsecutive = hasConsecutivePatterns(candidates, positiveSlowPhase: true)
        let negativeHasConsecutive = hasConsecutivePatterns(candidates, positiveSlowPhase: false)

        let validCandidates: [CandidatePattern]
        let direction: String
        if positiveHasConsecutive && negativeHasConsecutive {
            validCandidates = candidates
            direction = "bidirectional"
        } else if positiveHasConsecutive {
            validCandidates = candidates.filter { $0.slowSlope > 0 }
            direction = isHorizontal ? "left" : "up"
        } else if negativeHasConsecutive {
            validCandidates = candidates.filter { $0.slowSlope < 0 }
            direction = isHorizontal ? "right" : "down"
        } else {
            return PatternAnalysis(patterns: [], direction: "none", spv: 0, cvPercent: 0, hasNystagmus: false)
        }

        let slowSlopes = validCandidates.map { abs($0.slowSlope) }
        return PatternAnalysis(
            patterns: validCandidates.map(\.pattern),
            direction: direction,
            spv: median(slowSlopes),
            cvPercent: coefficientOfVariationUsingMAD(slowSlopes),
            hasNystagmus: true
        )
    }

    private func findTurningPoints(_ angles: [Double]) -> [Int] {
        guard angles.count >= 3 else { return [] }
        let minDistance = max(1, Int(0.25 * fps))
        let prominence = 0.2
        var rawPoints: [Int] = []
        for index in 1..<(angles.count - 1) {
            let previous = angles[index - 1]
            let current = angles[index]
            let next = angles[index + 1]
            let isPeak = current >= previous && current > next
            let isTrough = current <= previous && current < next
            guard isPeak || isTrough else { continue }
            let leftRange = max(0, index - minDistance)..<index
            let rightRange = (index + 1)...min(angles.count - 1, index + minDistance)
            let leftExtreme = isPeak ? leftRange.map { angles[$0] }.min() : leftRange.map { angles[$0] }.max()
            let rightExtreme = isPeak ? rightRange.map { angles[$0] }.min() : rightRange.map { angles[$0] }.max()
            let localProminence = min(abs(current - (leftExtreme ?? current)), abs(current - (rightExtreme ?? current)))
            guard localProminence >= prominence else { continue }
            rawPoints.append(index)
        }

        var points: [Int] = []
        for point in rawPoints {
            if let last = points.last, point - last < minDistance {
                if abs(angles[point]) > abs(angles[last]) {
                    points[points.count - 1] = point
                }
            } else {
                points.append(point)
            }
        }
        return points
    }

    private func hasConsecutivePatterns(_ candidates: [CandidatePattern], positiveSlowPhase: Bool) -> Bool {
        let sorted = candidates
            .filter { positiveSlowPhase ? $0.slowSlope > 0 : $0.slowSlope < 0 }
            .sorted { $0.timePoint < $1.timePoint }
        guard sorted.count >= 3 else { return false }

        var consecutive = 1
        for index in 1..<sorted.count {
            let previousEnd = sorted[index - 1].timePoint + sorted[index - 1].totalTime / 2.0
            let currentStart = sorted[index].timePoint - sorted[index].totalTime / 2.0
            if currentStart - previousEnd <= 0.1 {
                consecutive += 1
                if consecutive >= 3 {
                    return true
                }
            } else {
                consecutive = 1
            }
        }
        return false
    }

    private func computeVelocity(_ angles: [Double]) -> [Double] {
        let dt = 1.0 / fps
        return angles.indices.map { index in
            if index == 0 {
                return (angles[1] - angles[0]) / dt
            }
            if index == angles.count - 1 {
                return (angles[index] - angles[index - 1]) / dt
            }
            return (angles[index + 1] - angles[index - 1]) / (2.0 * dt)
        }
    }

    private func analyzeDirection(_ velocity: [Double]) -> (name: String, confidence: Double) {
        let positive = velocity.filter { $0 > velocityThreshold }.count
        let negative = velocity.filter { $0 < -velocityThreshold }.count
        let total = positive + negative
        guard total > 0 else { return ("none", 0) }
        if Double(positive) > Double(negative) * 1.5 {
            return ("positive", Double(positive) / Double(total))
        }
        if Double(negative) > Double(positive) * 1.5 {
            return ("negative", Double(negative) / Double(total))
        }
        return ("bidirectional", 0.5)
    }

    private func computeFrequency(_ angles: [Double]) -> Double {
        let n = angles.count
        guard n >= Int(fps) else { return 0 }
        let mean = angles.reduce(0, +) / Double(n)
        let centered = angles.map { $0 - mean }
        let freqStep = fps / Double(n)
        var bestFrequency = 0.0
        var bestPower = 0.0

        for k in 1..<(n / 2) {
            let frequency = Double(k) * freqStep
            if frequency < minFrequency || frequency > maxFrequency {
                continue
            }
            var real = 0.0
            var imag = 0.0
            for (index, value) in centered.enumerated() {
                let phase = 2.0 * .pi * Double(k) * Double(index) / Double(n)
                real += value * cos(phase)
                imag -= value * sin(phase)
            }
            let power = real * real + imag * imag
            if power > bestPower {
                bestPower = power
                bestFrequency = frequency
            }
        }
        return bestFrequency
    }

    private func computeSpv(_ velocity: [Double], direction: String) -> Double {
        guard !velocity.isEmpty else { return 0 }
        let candidates: [Double]
        switch direction {
        case "positive":
            candidates = velocity.filter { $0 < 0 }.map { abs($0) }
        case "negative":
            candidates = velocity.filter { $0 > 0 }.map { abs($0) }
        case "bidirectional":
            candidates = velocity.map { abs($0) }.sorted().prefix(velocity.count / 2).map { $0 }
        default:
            candidates = []
        }
        return median(candidates)
    }

    private func coefficientOfVariationUsingMAD(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let medianValue = median(values)
        guard abs(medianValue) > 0.0001 else { return 0 }
        let mad = median(values.map { abs($0 - medianValue) })
        return min(99, 1.4826 * mad / abs(medianValue) * 100)
    }
}

private func percentile(_ values: [Double], _ p: Double) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    let rank = ((p / 100.0) * Double(sorted.count - 1)).clamped(to: 0...Double(sorted.count - 1))
    let low = Int(rank)
    let high = max(low, Int(ceil(rank)))
    let fraction = rank - Double(low)
    return sorted[low] * (1.0 - fraction) + sorted[high] * fraction
}

private func median(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    let middle = sorted.count / 2
    if sorted.count.isMultiple(of: 2) {
        return (sorted[middle - 1] + sorted[middle]) / 2.0
    }
    return sorted[middle]
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
