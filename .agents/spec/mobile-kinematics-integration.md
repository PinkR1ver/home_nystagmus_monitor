# Mobile Kinematics 整合主线

- Created: 2026-09-14
- Last updated: 2026-09-14
- Status: Completed — Android first integration and desktop verification; device acceptance pending
- 用户决定：两个平台保留并行演进路线；当前 Android 优先，iPhone 后续再做、目前归档暂停。以运动实验室 Android App 现有 UI 为视觉方案，并加入眼动检测 section。

## 源码基线

- 来源：`/Volumes/macOSexternal/Downloads/mobile-kinematics-app-source-20260913/mobile-kinematics-app-source-20260913`
- 独立 Android v0.4.0（versionCode 7），applicationId `com.mobilekinematics.qishen`。
- Kotlin/Compose、CameraX、MediaPipe Pose Heavy，minSdk 28 / targetSdk 36，arm64-v8a。
- 已在来源目录初始化独立本地 Git；原包标签 `archive/source-v0.4.0-20260913`。新 App 仍在原目录，眼动能力已迁入该工程。

## 已了解的架构

- CameraScreen + LivePoseAnalyzer：实时 33 点骨架、人数/入镜/延迟反馈，允许丢帧。
- VideoAnalyzer：保存视频后约 20 Hz 重新分析；报告要求每帧恰好一人。
- BodyModel：14 体段、CoM、惯量；MotionAnalyzer / StsAnalyzer：静站、步态、坐站。
- SessionStore：本地目录会话，视频、landmarks.json、report.json、test_context.json，AtomicFile 写入、JSON/CSV ZIP 导出。
- IMU：前台服务原始六轴采集，不含自动事件识别。
- Manifest 明确移除网络权限；目前没有与本项目兼容的账户/服务端同步。

## 已确认的产品与视觉方向

- Android 运动实验室是当前整合宿主，现有 UI 是视觉基准；旧项目提供可复用的眼动检测能力。
- 保留白色/浅灰背景、红色强调色、圆角卡片和“首页 / 记录 / 我的”导航语言。
- 代码基准：`ui/AppUi.kt` 的 Accent `#FF2442`、Paper `#F7F7F7`、Ink `#222329`、Muted `#777B85`；不是采用旧 iOS Rehab Demo 的深色视觉。
- 眼动首版已确认采用录制结束后分析：先保存视频，再检测并生成报告，不要求实时检测。
- 新增独立“眼动检测”section；具体采集、分析和报告范围见新 App `.agents/spec/eye-movement-section.md`。
- iPhone/iPad 当前 Archived / Paused，代码原位保留；归档标签 `archive/pre-kinematics-20260914`。

## 整合建议（细节未决策）

1. 首页保留运动评估，增加独立眼动检测入口，沿用现有视觉组件。
2. 第一阶段按同一评估会话组织不同采集任务与独立报告；全身与眼部需要不同取景，不默认同时采集。
3. 定义版本化评估元数据：稳定 ID、任务类型、算法/模型版本、时间基准、单位/坐标、质量与未计算原因。账户/上传策略确认后映射旧 recordId 语义。
4. 保持 MediaPipe 根相对模型三维、iOS 双摄相机坐标、眼动角度/像素位移的边界，不能直接拼接比较。

## 待讨论

- 眼动 section 首版：采集/导入与报告指标的具体边界；录制结束后分析已确认。
- 头姿/视线融合是否后续另立任务？当前仅确认加入眼动检测。
- 首版保持离线；账户/服务器同步与头姿融合属于后续范围。

## 验证与下一步

- 已核对模型与两份配置 SHA-256，均与 SHARE_MANIFEST.md 相符。
- 已阅读 README、交接、验证文档及相机/分析/会话关键源码。
- 本机已通过原 39 项与新增 10 项测试（49/49）；APK 构建成功，Lint 0 errors / 23 warnings。
- 本机 testDebugUnitTest + assembleDebug + lintDebug 已完成；目标手机的摄像头、视频播放、完整推理性能和中断恢复待设备验收。
- 不因建立主线而把尚未实现的整合标记完成。

## Android 实施进展

- 已在新 App 接通独立眼动 section、采集/导入、手动单眼选区、录后本地分析、历史报告和 ZIP 导出。
- 复用当前仓库 Android `swinunet_web.onnx`；同 iPhone 文件 SHA-256 一致，无需重新下载模型。
- 采用本地离线推理，不增加服务器同步。详细实现与验证状态以新项目 `docs/EYE_DETECTION.md` 和 `.agents/spec/eye-movement-section.md` 为准。
- 本机模型 CPU 单帧 smoke、Android 构建、49 项回归、APK 签名及内置模型校验均通过。没有连接 Android 真机，设备验收未执行。

## 2026-09-22 update

Apple development explicitly resumed in a separate `codex/apple-motion-lab` branch. Its visual baseline is Android v0.5.0 (`ee5243d`); see [Apple spec](apple-motion-lab.md). Earlier paused/offline-only statements above describe the initial integration phase; Android cloud sync is now delivered.
