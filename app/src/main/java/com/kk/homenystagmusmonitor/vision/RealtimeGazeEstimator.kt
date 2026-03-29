package com.kk.homenystagmusmonitor.vision

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Rect
import com.kk.homenystagmusmonitor.analysis.GazeAngleFitter
import com.kk.homenystagmusmonitor.analysis.GazeAngles
import com.kk.homenystagmusmonitor.analysis.GazeVector
import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import java.io.Closeable
import java.nio.FloatBuffer
import kotlin.math.pow
import kotlin.math.sqrt

/**
 * 实时处理：
 * Bitmap -> 中心固定 ROI（硬件单眼拍摄） -> ONNX -> 3D vector -> pitch/yaw
 */
class RealtimeGazeEstimator(
    context: Context
) : Closeable {
    private val appContext = context.applicationContext
    private val ortEnv = OrtEnvironment.getEnvironment()
    private val ortSession: OrtSession
    private val inputName: String

    init {
        val modelBytes = appContext.assets.open("swinunet_web.onnx").use { it.readBytes() }
        ortSession = ortEnv.createSession(modelBytes)
        inputName = ortSession.inputNames.first()
    }

    fun estimate(bitmap: Bitmap): GazeAngles? {
        // 性能优化：先裁剪并缩放到模型输入尺寸，再做轻量增强，避免整帧处理。
        val eyeRoi = extractCenterEyeRoi(bitmap)
        val enhanced = enhanceForDetection(eyeRoi)
        val inputData = preprocess(enhanced)

        val tensor = OnnxTensor.createTensor(
            ortEnv,
            FloatBuffer.wrap(inputData),
            longArrayOf(1, 3, 36, 60)
        )
        var anglesResult: GazeAngles?
        tensor.use { inputTensor ->
            val output = ortSession.run(mapOf(inputName to inputTensor))
            output.use { out ->
                @Suppress("UNCHECKED_CAST")
                val vector = (out[0].value as Array<FloatArray>)[0]
                val norm = sqrt(
                    (vector[0] * vector[0] + vector[1] * vector[1] + vector[2] * vector[2]).toDouble()
                ).coerceAtLeast(1e-8)
                val gaze = GazeVector(
                    x = vector[0] / norm,
                    y = vector[1] / norm,
                    z = vector[2] / norm
                )
                anglesResult = GazeAngleFitter.vectorToAngles(gaze)
            }
        }
        return anglesResult
    }

    private fun extractCenterEyeRoi(source: Bitmap): Bitmap {
        // 硬件放大单眼场景：使用更大的中心窗口，减少误裁剪。
        val roiWidth = (source.width * ROI_WIDTH_RATIO).toInt().coerceAtLeast(40)
        val roiHeight = (source.height * ROI_HEIGHT_RATIO).toInt().coerceAtLeast(30)
        val centerX = source.width / 2
        val centerY = (source.height * ROI_CENTER_Y_RATIO).toInt()
        val left = (centerX - roiWidth / 2).coerceAtLeast(0)
        val top = (centerY - roiHeight / 2).coerceAtLeast(0)
        val right = (left + roiWidth).coerceAtMost(source.width)
        val bottom = (top + roiHeight).coerceAtMost(source.height)

        val roiRect = Rect(left, top, right, bottom)
        val cropped = Bitmap.createBitmap(
            source,
            roiRect.left,
            roiRect.top,
            roiRect.width(),
            roiRect.height()
        )
        return Bitmap.createScaledBitmap(cropped, MODEL_WIDTH, MODEL_HEIGHT, true)
    }

    /**
     * 对齐 vertiwisdom.py 的 _enhance_simple 思路：
     * 1) 灰度化
     * 2) gamma（可选）
     * 3) 对比增强（这里用全局均衡近似 CLAHE）
     * 4) 百分位拉伸（1%-99%）
     */
    private fun enhanceForDetection(source: Bitmap): Bitmap {
        val width = source.width
        val height = source.height
        val pixels = IntArray(width * height)
        source.getPixels(pixels, 0, width, 0, 0, width, height)

        val gray = IntArray(pixels.size)
        for (i in pixels.indices) {
            val p = pixels[i]
            val r = (p shr 16) and 0xFF
            val g = (p shr 8) and 0xFF
            val b = p and 0xFF
            gray[i] = (0.299 * r + 0.587 * g + 0.114 * b).toInt().coerceIn(0, 255)
        }

        if (ENHANCE_GAMMA != 1.0) {
            val invGamma = 1.0 / ENHANCE_GAMMA
            val gammaLut = IntArray(256) { idx ->
                ((idx / 255.0).pow(invGamma) * 255.0).toInt().coerceIn(0, 255)
            }
            for (i in gray.indices) gray[i] = gammaLut[gray[i]]
        }

        // 用全局直方图均衡近似 CLAHE，保持轻依赖实时性。
        val histogram = IntArray(256)
        for (v in gray) histogram[v]++
        val cdf = IntArray(256)
        var acc = 0
        for (i in 0 until 256) {
            acc += histogram[i]
            cdf[i] = acc
        }
        val cdfMin = cdf.firstOrNull { it > 0 } ?: 0
        val total = gray.size.coerceAtLeast(1)
        if (total > cdfMin) {
            for (i in gray.indices) {
                val v = gray[i]
                val mapped = ((cdf[v] - cdfMin).toDouble() / (total - cdfMin) * 255.0)
                gray[i] = mapped.toInt().coerceIn(0, 255)
            }
        }

        val p1 = percentile(gray, 1.0)
        val p99 = percentile(gray, 99.0)
        if (p99 > p1) {
            for (i in gray.indices) {
                val stretched = ((gray[i] - p1).toDouble() / (p99 - p1).toDouble() * 255.0)
                gray[i] = stretched.toInt().coerceIn(0, 255)
            }
        }

        val outPixels = IntArray(pixels.size)
        for (i in gray.indices) {
            val v = gray[i]
            outPixels[i] = Color.rgb(v, v, v)
        }
        return Bitmap.createBitmap(outPixels, width, height, Bitmap.Config.ARGB_8888)
    }

    private fun percentile(values: IntArray, p: Double): Int {
        if (values.isEmpty()) return 0
        val sorted = values.copyOf()
        sorted.sort()
        val rank = ((p / 100.0) * (sorted.size - 1)).toInt().coerceIn(0, sorted.lastIndex)
        return sorted[rank]
    }

    private fun preprocess(eyeBitmap: Bitmap): FloatArray {
        val width = MODEL_WIDTH
        val height = MODEL_HEIGHT
        val output = FloatArray(3 * width * height)
        val pixels = IntArray(width * height)
        eyeBitmap.getPixels(pixels, 0, width, 0, 0, width, height)

        // NCHW [1,3,36,60], 与训练输入一致范围 [0,1]
        for (y in 0 until height) {
            for (x in 0 until width) {
                val idx = y * width + x
                val p = pixels[idx]
                val r = ((p shr 16) and 0xFF) / 255f
                val g = ((p shr 8) and 0xFF) / 255f
                val b = (p and 0xFF) / 255f
                output[idx] = r
                output[width * height + idx] = g
                output[2 * width * height + idx] = b
            }
        }
        return output
    }

    override fun close() {
        ortSession.close()
    }

    private companion object {
        // 大中心 ROI：针对硬件已将眼区放大并居中显示的场景。
        private const val ROI_WIDTH_RATIO = 0.85f
        private const val ROI_HEIGHT_RATIO = 0.85f
        private const val ROI_CENTER_Y_RATIO = 0.52f
        private const val MODEL_WIDTH = 60
        private const val MODEL_HEIGHT = 36
        private const val ENHANCE_GAMMA = 1.0
    }
}
