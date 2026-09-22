# Apple Motion Lab · Android 同款设计版

2026-09-22 起在 `codex/apple-motion-lab` 分支恢复开发，主入口已按 Android v0.5.0 重写。白底、红色强调、圆角卡片，以及「首页 / 记录 / 我的」导航保持一致。

- 已实现：运动模式选择、录制/导入视频、本机持久记录、眼动入口、录制后 ONNX 分析、真实信号图、原始视频导出、受试者参数保存。
- 已设计入口但未接入：身体姿态推理、IMU 采集、云端账户/上传队列。界面明确展示当前状态。
- 眼动当前复用 Apple 自动 ROI，尚未移植 Android 手动单眼框选。相机需真机测试；模拟器可导入视频。
- 原始视频与报告数据存于 Documents/MotionLab；报告中的旧引擎预览图片 URL 仍是临时证据，主报告播放持久化原视频。
- 实际模拟器截图：[首页](visual-check/iphone-home.png)、[眼动](visual-check/iphone-eye.png)、[记录](visual-check/iphone-history.png)、[我的](visual-check/iphone-profile.png)、[云端](visual-check/iphone-cloud.png)、[iPad](visual-check/ipad-home.png)。

构建（从仓库根目录）：
```sh
DEVELOPER_DIR=/Volumes/macOSexternal/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project iphone-app/HomeNystagmusMonitoriOS.xcodeproj \
  -scheme HomeNystagmusMonitoriOS -sdk iphonesimulator \
  -derivedDataPath /tmp/motion-apple-build CODE_SIGNING_ALLOWED=NO build
```

报告持久化验证：
```sh
DEVELOPER_DIR=/Volumes/macOSexternal/Applications/Xcode.app/Contents/Developer xcrun swiftc \
  iphone-app/HomeNystagmusMonitoriOS/Models/AnalysisModels.swift \
  iphone-app/tests/ReportPersistenceSmoke.swift -o /tmp/motion-report-smoke
/tmp/motion-report-smoke
```

下面是保留的早期原型说明，旧 Dashboard / USB 组件目前未从新主界面提供入口。

---

# Home Nystagmus Monitor iPhone Prototype

This folder contains a standalone SwiftUI iPhone prototype for demonstrating the device workflow.

## Prototype Scope

- Start camera capture for a short eye video.
- Import an existing video when real nystagmus footage is unavailable.
- Run a local analysis service and show a polished dashboard result.
- Keep analysis state in memory only; no database or account system is included.
- Bundle the Android ONNX model asset at `HomeNystagmusMonitoriOS/Resources/swinunet_web.onnx` so the analysis layer can be replaced with a real iOS runtime later.

## Open

Open `HomeNystagmusMonitoriOS.xcodeproj` in Xcode and run the `HomeNystagmusMonitoriOS` scheme on an iPhone simulator or device.

The current `PrototypeNystagmusAnalysisEngine` is deliberately isolated behind `NystagmusAnalysisEngine`. Replace that implementation when adding ONNX Runtime, Core ML, or a server-backed analysis route.
