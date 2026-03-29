package com.kk.homenystagmusmonitor.analysis

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.asin
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

data class GazeVector(val x: Double, val y: Double, val z: Double)

data class GazeAngles(
    val pitchDeg: Double,
    val yawDeg: Double
)

data class AxisDetection(
    val present: Boolean,
    val direction: String,
    val directionLabel: String,
    val amplitude: Double,
    val frequencyHz: Double,
    val confidence: Double,
    val spv: Double
)

data class NystagmusDetectionResult(
    val horizontal: AxisDetection,
    val vertical: AxisDetection,
    val summary: String,
    val hasNystagmus: Boolean
)

/**
 * 迁移自 SwinUNet-VOG 的核心公式：
 * pitch = asin(-y), yaw = atan2(-x, -z)
 */
object GazeAngleFitter {
    fun vectorToAngles(vector: GazeVector): GazeAngles {
        val pitch = asin((-vector.y).coerceIn(-1.0, 1.0))
        val yaw = atan2(-vector.x, -vector.z)
        return GazeAngles(
            pitchDeg = Math.toDegrees(pitch),
            yawDeg = Math.toDegrees(yaw)
        )
    }
}

/**
 * Kotlin 版简化眼震检测器，参考 nystagmus.py 的 NystagmusDetector。
 */
class NystagmusDetector(
    private val fps: Double = 30.0
) {
    private val velocityThreshold = 5.0
    private val minAmplitude = 2.0
    private val minFrequency = 0.5
    private val maxFrequency = 6.0

    fun detect(pitch: List<Double>, yaw: List<Double>): NystagmusDetectionResult {
        val horizontal = analyzeSingleAxis(yaw, isHorizontal = true)
        val vertical = analyzeSingleAxis(pitch, isHorizontal = false)
        val has = horizontal.present || vertical.present
        val summary = when {
            !horizontal.present && !vertical.present -> "未检测到明显眼震"
            horizontal.present && !vertical.present -> "检测到水平眼震，快相方向: ${horizontal.directionLabel}"
            !horizontal.present && vertical.present -> "检测到垂直眼震，快相方向: ${vertical.directionLabel}"
            else -> "检测到混合眼震 - 水平(${horizontal.directionLabel}) + 垂直(${vertical.directionLabel})"
        }
        return NystagmusDetectionResult(
            horizontal = horizontal,
            vertical = vertical,
            summary = summary,
            hasNystagmus = has
        )
    }

    private fun analyzeSingleAxis(angles: List<Double>, isHorizontal: Boolean): AxisDetection {
        if (angles.size < 3) {
            return AxisDetection(false, "none", "无", 0.0, 0.0, 0.0, 0.0)
        }
        val velocity = computeVelocity(angles)
        val direction = analyzeDirection(velocity)
        val frequency = computeFrequency(angles)
        val amplitude = percentile(angles, 95.0) - percentile(angles, 5.0)
        val spv = computeSpv(velocity, direction.direction)

        val hasSufficientAmplitude = amplitude > minAmplitude
        val hasRhythmicPattern = frequency > minFrequency
        val hasFastPhases = direction.confidence > 0.3
        val present = hasSufficientAmplitude && (hasRhythmicPattern || hasFastPhases)

        val directionLabel = when (direction.direction) {
            "positive" -> if (isHorizontal) "向右" else "向上"
            "negative" -> if (isHorizontal) "向左" else "向下"
            "bidirectional" -> "双向"
            else -> "无"
        }

        return AxisDetection(
            present = present,
            direction = direction.direction,
            directionLabel = directionLabel,
            amplitude = amplitude,
            frequencyHz = frequency,
            confidence = direction.confidence,
            spv = spv
        )
    }

    private fun computeVelocity(angles: List<Double>): List<Double> {
        val dt = 1.0 / fps
        return angles.indices.map { i ->
            when (i) {
                0 -> (angles[1] - angles[0]) / dt
                angles.lastIndex -> (angles[i] - angles[i - 1]) / dt
                else -> (angles[i + 1] - angles[i - 1]) / (2 * dt)
            }
        }
    }

    private data class DirectionInfo(val direction: String, val confidence: Double)

    private fun analyzeDirection(velocity: List<Double>): DirectionInfo {
        val posCount = velocity.count { it > velocityThreshold }
        val negCount = velocity.count { it < -velocityThreshold }
        val total = posCount + negCount
        if (total == 0) return DirectionInfo("none", 0.0)
        return when {
            posCount > negCount * 1.5 -> DirectionInfo("positive", posCount.toDouble() / total.toDouble())
            negCount > posCount * 1.5 -> DirectionInfo("negative", negCount.toDouble() / total.toDouble())
            else -> DirectionInfo("bidirectional", 0.5)
        }
    }

    /**
     * 简单 DFT 求主频，避免引入额外依赖。
     */
    private fun computeFrequency(angles: List<Double>): Double {
        val n = angles.size
        if (n < fps.toInt()) return 0.0
        val mean = angles.average()
        val centered = angles.map { it - mean }
        var bestFreq = 0.0
        var bestPower = 0.0
        val freqStep = fps / n
        for (k in 1 until n / 2) {
            val freq = k * freqStep
            if (freq < minFrequency || freq > maxFrequency) continue
            var real = 0.0
            var imag = 0.0
            centered.forEachIndexed { idx, value ->
                val phase = 2.0 * PI * k * idx / n
                real += value * cos(phase)
                imag -= value * sin(phase)
            }
            val power = real * real + imag * imag
            if (power > bestPower) {
                bestPower = power
                bestFreq = freq
            }
        }
        return bestFreq
    }

    private fun computeSpv(velocity: List<Double>, direction: String): Double {
        if (velocity.isEmpty()) return 0.0
        val slowCandidates = when (direction) {
            "positive" -> velocity.filter { it < 0 }.map { abs(it) }
            "negative" -> velocity.filter { it > 0 }.map { abs(it) }
            "bidirectional" -> velocity.map { abs(it) }.sorted().take(velocity.size / 2)
            else -> emptyList()
        }
        if (slowCandidates.isEmpty()) return 0.0
        return median(slowCandidates)
    }

    private fun percentile(values: List<Double>, p: Double): Double {
        if (values.isEmpty()) return 0.0
        val sorted = values.sorted()
        val rank = ((p / 100.0) * (sorted.size - 1)).coerceIn(0.0, (sorted.size - 1).toDouble())
        val low = rank.toInt()
        val high = max(low, kotlin.math.ceil(rank).toInt())
        val frac = rank - low
        return sorted[low] * (1.0 - frac) + sorted[high] * frac
    }

    private fun median(values: List<Double>): Double {
        if (values.isEmpty()) return 0.0
        val sorted = values.sorted()
        val mid = sorted.size / 2
        return if (sorted.size % 2 == 0) (sorted[mid - 1] + sorted[mid]) / 2.0 else sorted[mid]
    }
}

/**
 * 对齐 vertiwisdom.py 的主流程：
 * 1) 无效帧(NaN)插值
 * 2) 中值滤波
 * 3) 低通平滑
 */
class SignalProcessor(
    private val fps: Double = 30.0,
    private val highPassCutoffHz: Double = 0.1,
    private val lowPassCutoffHz: Double = 6.0,
    private val medianKernelSize: Int = 5
) {
    data class ProcessedSignal(
        val values: List<Double>,
        val invalidMask: List<Boolean>
    )

    fun process(raw: List<Double>): ProcessedSignal {
        if (raw.isEmpty()) return ProcessedSignal(emptyList(), emptyList())
        val invalidMask = raw.map { it.isNaN() }
        val interpolated = interpolateNaN(raw)
        val median = medianFilter(interpolated, kernelSize = medianKernelSize)
        val highPassed = highPassFilterZeroPhase(median, highPassCutoffHz)
        val lowPassed = lowPassFilterZeroPhase(highPassed, lowPassCutoffHz)
        return ProcessedSignal(values = lowPassed, invalidMask = invalidMask)
    }

    private fun interpolateNaN(raw: List<Double>): List<Double> {
        val out = raw.toMutableList()
        val validIdx = raw.indices.filter { !raw[it].isNaN() }
        if (validIdx.isEmpty()) return List(raw.size) { 0.0 }
        if (validIdx.size == 1) return List(raw.size) { raw[validIdx.first()] }

        // 头尾外推
        val first = validIdx.first()
        val last = validIdx.last()
        for (i in 0 until first) out[i] = raw[first]
        for (i in last + 1 until raw.size) out[i] = raw[last]

        // 中间线性插值
        var ptr = 0
        while (ptr < validIdx.size - 1) {
            val left = validIdx[ptr]
            val right = validIdx[ptr + 1]
            val vLeft = raw[left]
            val vRight = raw[right]
            out[left] = vLeft
            for (i in left + 1 until right) {
                val t = (i - left).toDouble() / (right - left).toDouble()
                out[i] = vLeft * (1 - t) + vRight * t
            }
            out[right] = vRight
            ptr++
        }
        return out.map { if (it.isNaN()) 0.0 else it }
    }

    private fun medianFilter(values: List<Double>, kernelSize: Int): List<Double> {
        if (values.size < 3) return values
        val k = if (kernelSize % 2 == 1) kernelSize else kernelSize + 1
        val r = k / 2
        return values.indices.map { i ->
            val start = (i - r).coerceAtLeast(0)
            val end = (i + r).coerceAtMost(values.lastIndex)
            val window = values.subList(start, end + 1).sorted()
            window[window.size / 2]
        }
    }

    private fun lowPassFilterZeroPhase(values: List<Double>, cutoffHz: Double): List<Double> {
        if (values.size < 3) return values
        val nyquist = fps / 2.0
        val cutoff = cutoffHz.coerceAtMost(nyquist - 0.1).coerceAtLeast(0.1)
        val dt = 1.0 / fps
        val rc = 1.0 / (2.0 * PI * cutoff)
        val alpha = dt / (rc + dt)

        // 双向一阶低通近似 filtfilt 零相位
        val forward = MutableList(values.size) { 0.0 }
        forward[0] = values[0]
        for (i in 1 until values.size) {
            forward[i] = forward[i - 1] + alpha * (values[i] - forward[i - 1])
        }
        val backward = MutableList(values.size) { 0.0 }
        backward[values.lastIndex] = forward.last()
        for (i in values.lastIndex - 1 downTo 0) {
            backward[i] = backward[i + 1] + alpha * (forward[i] - backward[i + 1])
        }
        return backward
    }

    private fun highPassFilterZeroPhase(values: List<Double>, cutoffHz: Double): List<Double> {
        if (values.size < 3) return values
        val nyquist = fps / 2.0
        val cutoff = cutoffHz.coerceAtMost(nyquist - 0.1).coerceAtLeast(0.01)
        val dt = 1.0 / fps
        val rc = 1.0 / (2.0 * PI * cutoff)
        val alpha = rc / (rc + dt)

        // y[i] = a * (y[i-1] + x[i] - x[i-1])
        val forward = MutableList(values.size) { 0.0 }
        forward[0] = 0.0
        for (i in 1 until values.size) {
            forward[i] = alpha * (forward[i - 1] + values[i] - values[i - 1])
        }
        val backward = MutableList(values.size) { 0.0 }
        backward[values.lastIndex] = 0.0
        for (i in values.lastIndex - 1 downTo 0) {
            backward[i] = alpha * (backward[i + 1] + forward[i] - forward[i + 1])
        }
        return backward
    }
}

class NystagmusAnalyzer(
    private val fps: Double = 30.0,
    private val config: AnalyzerConfig = AnalyzerConfig()
) {
    data class AnalyzerConfig(
        val minValidSamples: Int = 30,
        val highPassCutoffHz: Double = 0.1,
        val lowPassCutoffHz: Double = 6.0,
        val medianKernelSize: Int = 5,
        val turningPointProminence: Double = 0.2,
        val turningPointMinDistanceSec: Double = 0.25,
        val minPatternTimeSec: Double = 0.15,
        val maxPatternTimeSec: Double = 1.5,
        val minSlopeRatio: Double = 1.2,
        val maxSlopeRatio: Double = 10.0,
        val minAmplitudeDeg: Double = 5.0,
        val minConsecutivePatterns: Int = 3,
        val maxConsecutiveGapSec: Double = 0.1,
        val minFrequencyHz: Double = 0.5,
        val maxFrequencyHz: Double = 6.0
    )

    private val signalProcessor = SignalProcessor(
        fps = fps,
        highPassCutoffHz = config.highPassCutoffHz,
        lowPassCutoffHz = config.lowPassCutoffHz,
        medianKernelSize = config.medianKernelSize
    )

    fun detect(
        pitchRaw: List<Double>,
        yawRaw: List<Double>
    ): NystagmusDetectionResult {
        val horizontal = analyzeAxis(yawRaw, isHorizontal = true)
        val vertical = analyzeAxis(pitchRaw, isHorizontal = false)
        val has = horizontal.present || vertical.present
        val summary = when {
            !horizontal.present && !vertical.present -> "未检测到明显眼震"
            horizontal.present && !vertical.present -> "检测到水平眼震，快相方向: ${horizontal.directionLabel}"
            !horizontal.present && vertical.present -> "检测到垂直眼震，快相方向: ${vertical.directionLabel}"
            else -> "检测到混合眼震 - 水平(${horizontal.directionLabel}) + 垂直(${vertical.directionLabel})"
        }
        return NystagmusDetectionResult(
            horizontal = horizontal,
            vertical = vertical,
            summary = summary,
            hasNystagmus = has
        )
    }

    private data class Pattern(
        val timePoint: Double,
        val totalTime: Double,
        val slowSlope: Double,
        val fastSlope: Double
    )

    private data class DirectionResult(
        val direction: String,
        val spv: Double,
        val confidence: Double,
        val present: Boolean
    )

    private fun analyzeAxis(raw: List<Double>, isHorizontal: Boolean): AxisDetection {
        if (raw.size < config.minValidSamples) {
            return AxisDetection(false, "none", "无", 0.0, 0.0, 0.0, 0.0)
        }
        val processed = signalProcessor.process(raw)
        val validSamples = processed.invalidMask.count { !it }
        if (validSamples < config.minValidSamples) {
            return AxisDetection(false, "none", "无", 0.0, 0.0, 0.0, 0.0)
        }
        val signal = processed.values
        val freq = computeFrequency(signal)
        val amplitude = percentile(signal, 95.0) - percentile(signal, 5.0)
        val patterns = identifyPatterns(signal)
        val result = determineDirectionAndPresence(patterns, isHorizontal)

        return AxisDetection(
            present = result.present,
            direction = result.direction,
            directionLabel = directionToLabel(result.direction, isHorizontal),
            amplitude = amplitude,
            frequencyHz = freq,
            confidence = result.confidence,
            spv = result.spv
        )
    }

    private fun identifyPatterns(signal: List<Double>): List<Pattern> {
        val turning = findTurningPoints(
            signal,
            prominence = config.turningPointProminence,
            minDistanceSec = config.turningPointMinDistanceSec
        )
        if (turning.size < 3) return emptyList()
        val t = signal.indices.map { it / fps }
        val out = mutableListOf<Pattern>()
        for (i in 1 until turning.lastIndex) {
            val i1 = turning[i - 1]
            val i2 = turning[i]
            val i3 = turning[i + 1]
            val p1 = signal[i1]
            val p2 = signal[i2]
            val p3 = signal[i3]

            // 与 python 一致：只看峰值三角形
            if (!(p2 > p1 && p2 > p3)) continue

            val ampLeft = abs(p2 - p1)
            val ampRight = abs(p2 - p3)
            val amplitude = max(ampLeft, ampRight)
            if (amplitude < config.minAmplitudeDeg) continue

            val totalTime = t[i3] - t[i1]
            if (totalTime !in config.minPatternTimeSec..config.maxPatternTimeSec) continue

            val slopeBefore = (p2 - p1) / ((t[i2] - t[i1]).coerceAtLeast(1e-6))
            val slopeAfter = (p3 - p2) / ((t[i3] - t[i2]).coerceAtLeast(1e-6))
            val fast = if (abs(slopeBefore) > abs(slopeAfter)) slopeBefore else slopeAfter
            val slow = if (abs(slopeBefore) > abs(slopeAfter)) slopeAfter else slopeBefore
            if (fast * slow > 0) continue
            val ratio = abs(fast) / abs(slow).coerceAtLeast(1e-6)
            if (ratio !in config.minSlopeRatio..config.maxSlopeRatio) continue

            out += Pattern(
                timePoint = t[i2],
                totalTime = totalTime,
                slowSlope = slow,
                fastSlope = fast
            )
        }
        return out
    }

    private fun determineDirectionAndPresence(
        patterns: List<Pattern>,
        isHorizontal: Boolean
    ): DirectionResult {
        if (patterns.isEmpty()) return DirectionResult("none", 0.0, 0.0, false)
        val positive = patterns.filter { it.slowSlope > 0 }
        val negative = patterns.filter { it.slowSlope < 0 }
        val posConsecutive = hasConsecutive(positive)
        val negConsecutive = hasConsecutive(negative)

        return when {
            posConsecutive && negConsecutive -> {
                val spv = max(
                    median(positive.map { abs(it.slowSlope) }),
                    median(negative.map { abs(it.slowSlope) })
                )
                DirectionResult("bidirectional", spv, 0.6, true)
            }

            posConsecutive -> {
                val spv = median(positive.map { abs(it.slowSlope) })
                val dir = if (isHorizontal) "left" else "up"
                DirectionResult(dir, spv, 0.8, true)
            }

            negConsecutive -> {
                val spv = median(negative.map { abs(it.slowSlope) })
                val dir = if (isHorizontal) "right" else "down"
                DirectionResult(dir, spv, 0.8, true)
            }

            else -> DirectionResult("none", 0.0, 0.3, false)
        }
    }

    private fun hasConsecutive(
        patterns: List<Pattern>,
        minConsecutive: Int = config.minConsecutivePatterns,
        maxGapSec: Double = config.maxConsecutiveGapSec
    ): Boolean {
        if (patterns.size < minConsecutive) return false
        val sorted = patterns.sortedBy { it.timePoint }
        var c = 1
        var maxC = 1
        for (i in 1 until sorted.size) {
            val prevEnd = sorted[i - 1].timePoint + sorted[i - 1].totalTime / 2.0
            val curStart = sorted[i].timePoint - sorted[i].totalTime / 2.0
            val gap = curStart - prevEnd
            if (gap <= maxGapSec) {
                c++
                maxC = max(maxC, c)
            } else {
                c = 1
            }
        }
        return maxC >= minConsecutive
    }

    private fun findTurningPoints(signal: List<Double>, prominence: Double, minDistanceSec: Double): List<Int> {
        if (signal.size < 3) return emptyList()
        val minDistance = (minDistanceSec * fps).toInt().coerceAtLeast(1)
        val peaks = mutableListOf<Int>()
        val valleys = mutableListOf<Int>()
        var lastPeak = -minDistance
        var lastValley = -minDistance

        for (i in 1 until signal.lastIndex) {
            val prev = signal[i - 1]
            val cur = signal[i]
            val next = signal[i + 1]
            if (cur > prev && cur >= next && (cur - min(prev, next)) >= prominence && (i - lastPeak) >= minDistance) {
                peaks += i
                lastPeak = i
            }
            if (cur < prev && cur <= next && (max(prev, next) - cur) >= prominence && (i - lastValley) >= minDistance) {
                valleys += i
                lastValley = i
            }
        }
        return (peaks + valleys).sorted()
    }

    private fun computeFrequency(values: List<Double>): Double {
        if (values.size < fps.toInt()) return 0.0
        val centered = values.map { it - values.average() }
        var bestFreq = 0.0
        var bestPower = 0.0
        val n = centered.size
        val step = fps / n
        for (k in 1 until n / 2) {
            val freq = k * step
            if (freq !in config.minFrequencyHz..config.maxFrequencyHz) continue
            var real = 0.0
            var imag = 0.0
            centered.forEachIndexed { idx, value ->
                val phase = 2.0 * PI * k * idx / n
                real += value * cos(phase)
                imag -= value * sin(phase)
            }
            val power = real * real + imag * imag
            if (power > bestPower) {
                bestPower = power
                bestFreq = freq
            }
        }
        return bestFreq
    }

    private fun directionToLabel(direction: String, isHorizontal: Boolean): String {
        return when (direction) {
            "right" -> "向右"
            "left" -> "向左"
            "up" -> "向上"
            "down" -> "向下"
            "bidirectional" -> "双向"
            else -> "无"
        }.let { label ->
            if (isHorizontal || label !in setOf("向左", "向右")) label else label
        }
    }

    private fun percentile(values: List<Double>, p: Double): Double {
        if (values.isEmpty()) return 0.0
        val sorted = values.sorted()
        val rank = ((p / 100.0) * (sorted.size - 1)).coerceIn(0.0, (sorted.size - 1).toDouble())
        val low = rank.toInt()
        val high = kotlin.math.ceil(rank).toInt().coerceAtLeast(low)
        val frac = rank - low
        return sorted[low] * (1.0 - frac) + sorted[high] * frac
    }

    private fun median(values: List<Double>): Double {
        if (values.isEmpty()) return 0.0
        val sorted = values.sorted()
        val mid = sorted.size / 2
        return if (sorted.size % 2 == 0) (sorted[mid - 1] + sorted[mid]) / 2.0 else sorted[mid]
    }
}

