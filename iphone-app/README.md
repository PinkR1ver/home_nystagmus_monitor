> Implementation checkpoint (2026-09-23); physical-device acceptance remains pending. Manual fixed ROI, raw IMU capture, MediaPipe Heavy body/STS/standing/gait metrics and HTTPS cloud sync are implemented. Android-reference algorithm fixtures and synthetic live-server sync tests pass. Live body camera overlay, quality-gated eye analysis, report ZIP/CSV export and account-scoped cloud sync are implemented. Physical camera/IMU acceptance still requires an available iOS signing account and Developer build. See `.agents/spec/apple-motion-lab.md` for current state. Run CocoaPods install before opening the `.xcworkspace`.

# Apple Motion Lab · Android 同款设计版

2026-09-22 起在 `codex/apple-motion-lab` 分支恢复开发，主入口已按 Android v0.5.0 重写。白底、红色强调、圆角卡片，以及「首页 / 记录 / 我的」导航保持一致。

- 已实现：运动模式选择、录制/导入视频、本机持久记录、眼动入口、录制后 ONNX 分析、真实信号图、原始视频导出、受试者参数保存。
- 已接入：MediaPipe Heavy 身体姿态与运动报告、Core Motion IMU 采集、Keychain 账户凭据、HTTPS 同步/重试队列和 ZIP/CSV 导出。
- 眼动使用手动确认的固定单眼 ROI，完整视频录制后进行 ONNX 推理及质量筛选。模拟器运行验证已通过；相机和 IMU 真机验收仍等待开发签名。
- 原始视频与报告数据存于 Documents/MotionLab；报告中的旧引擎预览图片 URL 仍是临时证据，主报告播放持久化原视频。
- 实际模拟器截图：[首页](visual-check/iphone-home.png)、[眼动](visual-check/iphone-eye.png)、[记录](visual-check/iphone-history.png)、[我的](visual-check/iphone-profile.png)、[云端](visual-check/iphone-cloud.png)、[iPad](visual-check/ipad-home.png)。

构建（从仓库根目录）：
```sh
DEVELOPER_DIR=/Volumes/macOSexternal/Applications/Xcode.app/Contents/Developer xcodebuild \
  -workspace iphone-app/HomeNystagmusMonitoriOS.xcworkspace \
  -scheme HomeNystagmusMonitoriOS -sdk iphonesimulator \
  -derivedDataPath /tmp/motion-apple-build CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build
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
