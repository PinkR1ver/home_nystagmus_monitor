# Mobile Kinematics 整合主线

- Created: 2026-09-14
- Last updated: 2026-09-14
- Status: Discussion — source intake completed; implementation not started
- 用户决定：结合运动实验室 App 是下一步主线。平台、宿主 App、合并形式及第一版范围尚待讨论。

## 源码基线

- 来源：`/Volumes/macOSexternal/Downloads/mobile-kinematics-app-source-20260913/mobile-kinematics-app-source-20260913`
- 独立 Android v0.4.0（versionCode 7），applicationId `com.mobilekinematics.qishen`。
- Kotlin/Compose、CameraX、MediaPipe Pose Heavy，minSdk 28 / targetSdk 36，arm64-v8a。
- 已在来源目录初始化独立本地 Git；原包标签 `archive/source-v0.4.0-20260913`。当前不迁移目录、不合并业务代码。

## 已了解的架构

- CameraScreen + LivePoseAnalyzer：实时 33 点骨架、人数/入镜/延迟反馈，允许丢帧。
- VideoAnalyzer：保存视频后约 20 Hz 重新分析；报告要求每帧恰好一人。
- BodyModel：14 体段、CoM、惯量；MotionAnalyzer / StsAnalyzer：静站、步态、坐站。
- SessionStore：本地目录会话，视频、landmarks.json、report.json、test_context.json，AtomicFile 写入、JSON/CSV ZIP 导出。
- IMU：前台服务原始六轴采集，不含自动事件识别。
- Manifest 明确移除网络权限；目前没有与本项目兼容的账户/服务端同步。

## 整合建议（未决策）

1. 优先讨论以新 Android App 为运动评估宿主，逐步加入眼动/头动入口；保留旧项目为能力来源。
2. 第一阶段按同一评估会话组织不同采集任务与独立报告；全身与眼部需要不同取景，不默认同时采集。
3. 定义版本化评估元数据：稳定 ID、任务类型、算法/模型版本、时间基准、单位/坐标、质量与未计算原因。账户/上传策略确认后映射旧 recordId 语义。
4. 保持 MediaPipe 根相对模型三维、iOS 双摄相机坐标、眼动角度/像素位移的边界，不能直接拼接比较。

## 待讨论

- 第一版 Android 优先还是 iPhone/iPad 优先？
- 统一 App 还是先统一报告/数据协议？新 App 是否作为宿主？
- 首个闭环是运动 + 眼震，还是身体 + 头姿 + 视线？
- 先保持离线工作流，还是首版接入账户/服务器？

## 验证与下一步

- 已核对模型与两份配置 SHA-256，均与 SHARE_MANIFEST.md 相符。
- 已阅读 README、交接、验证文档及相机/分析/会话关键源码。
- 交付方记载 39 tests / 0 failures、lint 0 errors；本轮未在本机重跑，不视为本机通过。
- 讨论确定范围后：本机 testDebugUnitTest + assembleDebug + lintDebug，再做目标手机三模式、前后摄像头与异常中断验证。
- 不因建立主线而把尚未实现的整合标记完成。
