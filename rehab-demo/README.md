# Rehab Motion Demo

iPhone 康复训练三信号采集 Demo：后置广角＋超广角立体人体、独立头动、
以及现有 SwinUNet 眼动。

## 当前采集路线

1. `builtInDualWideCamera` 同时使用后置广角和超广角。
2. AVFoundation 从两路视差生成同步深度图，并提供相机标定内参。
3. YOLO11n Pose 输出 COCO 人体关键点。
4. 深度图与内参把 2D 关键点投影为相机空间 `X/Y/Z`（米）。
5. FCQ MobileNetV3 从 YOLO 推导的面部 ROI 输出头部 yaw / pitch / roll。
6. 项目已有 `swinunet_web.onnx` 从单眼 ROI 输出 gaze vector。

未使用 Apple 人体或面部关键点模型。Vision 仅作为第三方 Core ML 模型的
执行和裁剪接口。没有 Dual Wide 深度能力的设备会降级为后置单摄，人体、
头动和眼动仍可运行，但不输出立体深度。

## 性能策略

- 摄像头与双后摄深度：30 fps
- YOLO 人体：最高 10 fps
- FCQ 头动：最高 10 fps
- SwinUNet 眼动：最高 20 fps
- 深度预览：最高 6 fps

各模型使用独立串行队列和 busy gate，不积压旧帧。界面会显示最近一次
推理耗时。眼动输入有像素质量门控：完整全身距离下眼睛太小时，系统会
拒绝输出看似合理但无意义的 gaze 值。

### 确定性推理基准

2026-07-29 在当前 Apple Silicon Mac 上做了 12 次热启动推理（Core ML
`computeUnits = .all`；ONNX Runtime 使用 2 个 CPU 线程）：

| 模型 | 中位耗时 | P95 | 输出验证 |
|---|---:|---:|---|
| YOLO11n Pose | 4.5 ms | 4.6 ms | `[1, 56, 8400]` |
| FCQ Head Pose | 0.6 ms | 0.7 ms | `[1, 7]` |
| SwinUNet Gaze | 5.4 ms | 5.7 ms | `[1, 3]` |

这些数字用于证明模型资产可加载、可推理并评估相对开销，不等同于 iPhone
端端到端帧延迟。真机界面显示包含裁剪与后处理的最近一次实测耗时。
Core ML 与 ONNX 基准可分别用 `Tools/benchmark_coreml.swift` 和
`Tools/benchmark_gaze.py` 重复运行。

点击开始/停止评估会把三条信号写入 App Documents 下的
`RehabSessions/rehab-*.json`。记录包含头动、眼动、深度质量和每个关节的
2D 坐标与相机空间 X/Y/Z，最高按 30 Hz 采样。

## 运行

```sh
cd rehab-demo
DEVELOPER_DIR=/Volumes/macOSexternal/Applications/Xcode.app/Contents/Developer \
xcodebuild -project RehabDemo.xcodeproj -scheme RehabDemo \
  -sdk iphoneos -configuration Debug build
```

或用 Xcode 直接打开 `RehabDemo.xcodeproj`。

## 主要文件

```text
RehabDemo/
  Views/
    ContentView.swift
    CameraPreviewView.swift
    SignalPanelView.swift
  Services/
    CameraManager.swift          # Dual Wide + video/depth 同步
    DualSignalCapture.swift      # 三模型调度与信号融合
    StereoDepthProjector.swift   # 深度采样与 3D 投影
    YOLOPoseEstimator.swift      # 人体模型
    HeadPoseEstimator.swift      # 第三方头动模型
    ONNXGazeEstimator.swift      # 现有眼动模型
    FaceCropGeometry.swift       # YOLO 驱动的 face / eye ROI
  Models/
    SignalFrame.swift
  Resources/
    YOLO11nPose.mlpackage
    HeadPose.mlpackage
    swinunet_web.onnx
    THIRD_PARTY_MODELS.md
```

## 信号说明

| 类别 | 字段 | 来源 |
|---|---|---|
| Body | `bodyLandmarks` | YOLO11n Pose；有深度时每点包含 camera X/Y/Z |
| Body | `medianBodyDepthMeters` | 后置广角＋超广角视差深度 |
| Body | `stereoDepthCoverage` | 获得有效深度的关键点比例 |
| Head | `headYaw/Pitch/Roll` | FCQ Head Pose 权重模型 |
| Eye | `gazeDirectionX/Y` | SwinUNet ONNX 权重模型 |
| Quality | `headPoseQuality/gazeQuality` | 模型质量与输入像素门控 |

模型来源、哈希和许可证见
`RehabDemo/Resources/THIRD_PARTY_MODELS.md`。
