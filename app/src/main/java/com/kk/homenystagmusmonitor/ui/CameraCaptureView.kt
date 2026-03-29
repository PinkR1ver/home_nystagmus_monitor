package com.kk.homenystagmusmonitor.ui

import android.Manifest
import android.content.Context
import android.hardware.camera2.CaptureRequest
import android.util.Range
import androidx.camera.camera2.interop.Camera2Interop
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.CameraInfoUnavailableException
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.video.FileOutputOptions
import androidx.camera.video.FallbackStrategy
import androidx.camera.video.Quality
import androidx.camera.video.QualitySelector
import androidx.camera.video.Recorder
import androidx.camera.video.Recording
import androidx.camera.video.VideoCapture
import androidx.camera.video.VideoRecordEvent
import androidx.camera.view.PreviewView
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import java.io.File

@Composable
fun CameraCaptureView(
    isRunning: Boolean,
    useFrontCamera: Boolean,
    modifier: Modifier = Modifier,
    onVideoRecorded: (String?, Long) -> Unit
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    var hasPermission by remember { mutableStateOf(hasCameraPermission(context)) }
    val permissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission()
    ) { granted -> hasPermission = granted }

    LaunchedEffect(Unit) {
        if (!hasPermission) permissionLauncher.launch(Manifest.permission.CAMERA)
    }

    if (!hasPermission) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("需要相机权限才能进行实时采集。", color = MaterialTheme.colorScheme.error)
            Button(onClick = { permissionLauncher.launch(Manifest.permission.CAMERA) }) {
                Text("授权相机")
            }
        }
        return
    }

    val previewView = remember {
        PreviewView(context).apply {
            scaleType = PreviewView.ScaleType.FILL_CENTER
        }
    }
    val cameraProviderState = remember { mutableStateOf<ProcessCameraProvider?>(null) }
    val videoCaptureState = remember { mutableStateOf<VideoCapture<Recorder>?>(null) }
    val activeRecordingState = remember { mutableStateOf<Recording?>(null) }
    val recordingStartMsState = remember { mutableStateOf(0L) }
    val currentOutputPathState = remember { mutableStateOf<String?>(null) }

    DisposableEffect(Unit) {
        onDispose {
            activeRecordingState.value?.stop()
            activeRecordingState.value = null
            cameraProviderState.value?.unbindAll()
        }
    }

    LaunchedEffect(lifecycleOwner, useFrontCamera) {
        val cameraProviderFuture = ProcessCameraProvider.getInstance(context)
        val cameraProvider = cameraProviderFuture.get()
        cameraProviderState.value = cameraProvider
        cameraProvider.unbindAll()
        val selector = resolveCameraSelector(cameraProvider, useFrontCamera)

        val previewBuilder = Preview.Builder()
        configureTargetFps(previewBuilder)
        val preview = previewBuilder.build().also {
            it.setSurfaceProvider(previewView.surfaceProvider)
        }

        val recorder = Recorder.Builder()
            .setQualitySelector(
                QualitySelector.from(
                    Quality.HD,
                    FallbackStrategy.lowerQualityOrHigherThan(Quality.SD)
                )
            )
            .build()
        val videoCapture = VideoCapture.withOutput(recorder)
        videoCaptureState.value = videoCapture

        cameraProvider.bindToLifecycle(lifecycleOwner, selector, preview, videoCapture)
    }

    LaunchedEffect(isRunning, videoCaptureState.value) {
        val videoCapture = videoCaptureState.value ?: return@LaunchedEffect
        if (isRunning && activeRecordingState.value == null) {
            startRecording(
                context = context,
                videoCapture = videoCapture,
                activeRecordingState = activeRecordingState,
                recordingStartMsState = recordingStartMsState,
                currentOutputPathState = currentOutputPathState,
                onVideoRecorded = onVideoRecorded
            )
        } else if (!isRunning && activeRecordingState.value != null) {
            activeRecordingState.value?.stop()
            activeRecordingState.value = null
        }
    }

    AndroidView(
        factory = { previewView },
        modifier = modifier.fillMaxWidth()
    )
}

private fun configureTargetFps(builder: Preview.Builder) {
    try {
        Camera2Interop.Extender(builder)
            .setCaptureRequestOption(
                CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE,
                Range(30, 60)
            )
    } catch (_: Exception) {
        // 某些设备不支持锁定 60fps，系统会自动回退到可用帧率。
    }
}

private fun resolveCameraSelector(
    cameraProvider: ProcessCameraProvider,
    useFrontCamera: Boolean
): CameraSelector {
    val preferred = if (useFrontCamera) {
        CameraSelector.DEFAULT_FRONT_CAMERA
    } else {
        CameraSelector.DEFAULT_BACK_CAMERA
    }
    val fallback = if (useFrontCamera) {
        CameraSelector.DEFAULT_BACK_CAMERA
    } else {
        CameraSelector.DEFAULT_FRONT_CAMERA
    }
    return when {
        cameraProvider.hasCameraSafely(preferred) -> preferred
        cameraProvider.hasCameraSafely(fallback) -> fallback
        else -> preferred
    }
}

private fun ProcessCameraProvider.hasCameraSafely(selector: CameraSelector): Boolean {
    return try {
        hasCamera(selector)
    } catch (_: CameraInfoUnavailableException) {
        false
    }
}

private fun hasCameraPermission(context: Context): Boolean {
    return ContextCompat.checkSelfPermission(
        context,
        Manifest.permission.CAMERA
    ) == android.content.pm.PackageManager.PERMISSION_GRANTED
}

private fun startRecording(
    context: Context,
    videoCapture: VideoCapture<Recorder>,
    activeRecordingState: MutableState<Recording?>,
    recordingStartMsState: MutableState<Long>,
    currentOutputPathState: MutableState<String?>,
    onVideoRecorded: (String?, Long) -> Unit
) {
    val outputDir = File(context.filesDir, "records_videos").apply { mkdirs() }
    val outputFile = File(outputDir, "rec_${System.currentTimeMillis()}.mp4")
    currentOutputPathState.value = outputFile.absolutePath
    recordingStartMsState.value = 0L

    val pending = videoCapture.output.prepareRecording(
        context,
        FileOutputOptions.Builder(outputFile).build()
    )
    activeRecordingState.value = pending.start(ContextCompat.getMainExecutor(context)) { event ->
        when (event) {
            is VideoRecordEvent.Start -> {
                recordingStartMsState.value = System.currentTimeMillis()
            }

            is VideoRecordEvent.Finalize -> {
                val startedAt = recordingStartMsState.value
                val durationMs = if (startedAt > 0L) {
                    (System.currentTimeMillis() - startedAt).coerceAtLeast(0L)
                } else {
                    0L
                }
                if (!event.hasError()) {
                    onVideoRecorded(currentOutputPathState.value, durationMs)
                } else {
                    onVideoRecorded(null, 0L)
                }
                activeRecordingState.value = null
                currentOutputPathState.value = null
                recordingStartMsState.value = 0L
            }

            else -> Unit
        }
    }
}
