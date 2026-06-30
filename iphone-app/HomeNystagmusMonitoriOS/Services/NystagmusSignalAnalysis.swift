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
    let targetSampleRate: Double = 600.0

    func process(_ raw: [Double]) -> [Double] {
        guard !raw.isEmpty else { return [] }
        let interpolated = interpolateNaN(raw)
        let highPassed = butterworthZeroPhase(interpolated, cutoffHz: highPassCutoffHz, filterType: .highPass)
        let lowPassed = butterworthZeroPhase(highPassed, cutoffHz: lowPassCutoffHz, filterType: .lowPass)
        return resample(lowPassed, targetSampleRate: targetSampleRate)
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

    private enum ButterworthFilterType {
        case lowPass
        case highPass
    }

    private struct Biquad {
        let b0: Double
        let b1: Double
        let b2: Double
        let a1: Double
        let a2: Double

        func apply(to values: [Double]) -> [Double] {
            guard !values.isEmpty else { return [] }
            var out = [Double](repeating: 0, count: values.count)
            var x1 = values[0]
            var x2 = values[0]
            var y1 = values[0]
            var y2 = values[0]
            for index in values.indices {
                let x0 = values[index]
                let y0 = b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
                out[index] = y0
                x2 = x1
                x1 = x0
                y2 = y1
                y1 = y0
            }
            return out
        }
    }

    private func butterworthZeroPhase(_ values: [Double], cutoffHz: Double, filterType: ButterworthFilterType) -> [Double] {
        guard values.count > 15, cutoffHz > 0, cutoffHz < fps / 2.0 else { return values }
        let filtered = applyButterworth(values, cutoffHz: cutoffHz, filterType: filterType)
        return Array(applyButterworth(Array(filtered.reversed()), cutoffHz: cutoffHz, filterType: filterType).reversed())
    }

    private func applyButterworth(_ values: [Double], cutoffHz: Double, filterType: ButterworthFilterType) -> [Double] {
        let sections = [
            makeBiquad(cutoffHz: cutoffHz, q: 0.61803398875, filterType: filterType),
            makeBiquad(cutoffHz: cutoffHz, q: 1.61803398875, filterType: filterType)
        ]
        let firstOrder = makeFirstOrder(cutoffHz: cutoffHz, filterType: filterType)
        return firstOrder.apply(to: sections.reduce(values) { partial, section in
            section.apply(to: partial)
        })
    }

    private func makeBiquad(cutoffHz: Double, q: Double, filterType: ButterworthFilterType) -> Biquad {
        let omega = 2.0 * .pi * cutoffHz / fps
        let cosOmega = cos(omega)
        let alpha = sin(omega) / (2.0 * q)

        let b0: Double
        let b1: Double
        let b2: Double
        switch filterType {
        case .lowPass:
            b0 = (1.0 - cosOmega) / 2.0
            b1 = 1.0 - cosOmega
            b2 = (1.0 - cosOmega) / 2.0
        case .highPass:
            b0 = (1.0 + cosOmega) / 2.0
            b1 = -(1.0 + cosOmega)
            b2 = (1.0 + cosOmega) / 2.0
        }

        let a0 = 1.0 + alpha
        let a1 = -2.0 * cosOmega
        let a2 = 1.0 - alpha
        return Biquad(b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0)
    }

    private struct FirstOrder {
        let b0: Double
        let b1: Double
        let a1: Double

        func apply(to values: [Double]) -> [Double] {
            guard !values.isEmpty else { return [] }
            var out = [Double](repeating: 0, count: values.count)
            var x1 = values[0]
            var y1 = values[0]
            for index in values.indices {
                let x0 = values[index]
                let y0 = b0 * x0 + b1 * x1 - a1 * y1
                out[index] = y0
                x1 = x0
                y1 = y0
            }
            return out
        }
    }

    private func makeFirstOrder(cutoffHz: Double, filterType: ButterworthFilterType) -> FirstOrder {
        let omega = 2.0 * .pi * cutoffHz / fps
        let cosOmega = cos(omega)
        let sinOmega = sin(omega)
        let gamma = cosOmega / (1.0 + sinOmega)
        switch filterType {
        case .lowPass:
            return FirstOrder(b0: (1.0 - gamma) / 2.0, b1: (1.0 - gamma) / 2.0, a1: -gamma)
        case .highPass:
            return FirstOrder(b0: (1.0 + gamma) / 2.0, b1: -(1.0 + gamma) / 2.0, a1: -gamma)
        }
    }

    private func resample(_ values: [Double], targetSampleRate: Double) -> [Double] {
        guard values.count > 1, targetSampleRate > 0 else { return values }
        let duration = Double(values.count - 1) / fps
        let targetCount = max(values.count, Int(duration * targetSampleRate))
        guard targetCount > 1 else { return values }

        var out = values
        out = [Double](repeating: 0, count: targetCount)
        for index in 0..<targetCount {
            let sourcePosition = Double(index) / Double(targetCount - 1) * Double(values.count - 1)
            let left = Int(floor(sourcePosition)).clamped(to: 0...(values.count - 1))
            let right = min(left + 1, values.count - 1)
            let fraction = sourcePosition - Double(left)
            out[index] = values[left] * (1.0 - fraction) + values[right] * fraction
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
        let amplitude = percentile(angles, 95) - percentile(angles, 5)
        let analysis = analyzePatterns(angles, isHorizontal: isHorizontal)
        let frequency = estimateFrequency(from: analysis.patterns)
        let patterns = analysis.patterns
        let cv = analysis.cvPercent
        let spv = analysis.spv
        let present = analysis.hasNystagmus
        let confidence = present ? min(0.98, max(0.45, 1.0 - cv / 120.0)) : 0.0
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
            confidence: confidence,
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

    private func estimateFrequency(from patterns: [SignalPattern]) -> Double {
        guard !patterns.isEmpty else { return 0 }
        let periods = patterns.map { max($0.endTime - $0.startTime, 0.0001) }
        let frequency = 1.0 / max(median(periods), 0.0001)
        return frequency.clamped(to: minFrequency...maxFrequency)
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
