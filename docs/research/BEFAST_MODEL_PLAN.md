# BEFAST 模型与落地方案

核查日期：2026-09-23。输入：用户提供的 `BEFAST.html`（项目转化汇报）。状态：模型调研与实现方案完成；本文件不代表新模块已接入 App。Android 优先，Apple 后续按同一协议移植。

## 结论与边界

可以逐步覆盖六个入口的采集、特征、趋势及医生复核，但不能靠下载几个通用模型直接得到经过验证的卒中数字评分。现有 Motion Lab 已有身体姿态、IMU、眼动和上传基础；新增工作主要是面部、上肢专项任务、语音、头痛问卷与统一评估会话。

原文件把 T 定义为 Thunder。标准 BEFAST 的 T 是 Time；CDC 列出突然的平衡/视力/面臂/言语变化以及无明显原因的剧烈头痛，并要求立即求助。[CDC 原文](https://www.cdc.gov/stroke/signs-symptoms/index.html)。产品建议保留标准 T（症状初现/最后正常时间、紧急求助），把 Thunder/NRS 作为额外模块；它是对原方案的建议调整，尚非用户确认的重定义。不能等录完或等模型评分才显示紧急求助入口。

## 模块映射

| 模块 | 当前基础 | 模型与新增流程 | 可输出的结果及限制 |
| --- | --- | --- | --- |
| B Balance | MediaPipe Pose Heavy、站立/步态指标、手机 IMU 已实现 | 复用现有 Heavy 模型，标准化站立/行走任务；记录手机放置位置、采样率和佩戴方式。后续单独接手环 SDK | 身体摆动、步频、左右步态变化及个人基线。手机二维/估算三维运动特征不等于临床平衡评分；不同佩戴位置不可直接合并 |
| E Eyes | 保存视频后，固定单眼 ROI + `swinunet_web.onnx` 推理、质量门控、眼动报告已实现 | 保留现有链路；Face Landmarker 可辅助定位/眨眼/头动质量检查，但不能替代近眼采集及当前眼动模型 | 眼动信号与模式证据；不覆盖 BEFAST 所有视觉症状（视力下降、复视、视野缺损需另行采集/评估），不能据此排除卒中 |
| F Face | 主 App 尚无面部专项评估 | MediaPipe Face Landmarker；先采中性面，再微笑/露齿，固定距离和姿势，做头姿校正；左右嘴角/眼睑位移以面部尺度归一化 | 左右运动差、变化趋势与视频证据；blendshape 是动画/表情系数，不是面瘫或卒中概率。先做特征，不给未经验证的正常阈值 |
| A Arms | Heavy 的肩/肘/腕点位与身体运动报告可复用，专项上肢任务未实现 | 正面双臂平举任务，跟踪腕高度下降、抬臂角度、左右差及可见覆盖率；时长由临床任务规范确定 | 上肢下垂/不对称特征。躯干旋转、遮挡和镜像必须处理；没有可靠掌面朝向时不宣称识别旋前，必要时另评估手部模型 |
| S Speech | 旧研究 demo 有 wav2vec2 embeddings，主 App 未接语音评估 | Silero VAD 分段 + 原始音频；优先比较多语言 Whisper tiny/base 与 SenseVoiceSmall，采用固定中文短句及持续元音任务，录完分析 | 发声/静音比例、停顿、时长、固定文本对齐和转写。ASR 错字/识别置信度不等于构音障碍；卒中/构音障碍分类器需标注队列与独立验证 |
| T Time + 额外 Thunder | 未实现 | 不需要模型：记录初现/最后正常时间、突发与达峰过程、患者自己填写 NRS 0–10 和“无法回答”，保留急救入口 | 头痛记录与趋势；行为或情绪模型只能触发询问，不能生成“患者 NRS”，缺失不能填 0 |

## 公开模型、运行方式与许可

1. **MediaPipe Face Landmarker**：Google 官方 Android 示例提供摄像头/图片/视频路径，并由 [download_tasks.gradle](https://github.com/google-ai-edge/mediapipe-samples/blob/c2518ec444c3a3a99689e5d31eddadc240c83a0c/examples/face_landmarker/android/app/download_tasks.gradle) 指向版本 `float16/1` 的 `.task`。使用 App 现有 MediaPipe Tasks 路线；Android/iOS 各自写适配层。官方 [Python API 源码](https://github.com/google-ai-edge/mediapipe/blob/master/mediapipe/tasks/python/vision/face_landmarker.py) 定义 52 项 blendshape 和面部变换输出。代码为 Apache-2.0；模型权重的随附条款/模型卡还需归档，不能用代码许可证替代权重审核。已下载并验证包结构，尚未在手机运行。
2. **Silero VAD**：[官方仓库](https://github.com/snakers4/silero-vad) 发布 ONNX 和 MIT 许可，可复用现有 ONNX Runtime。用途仅是语音活动分段；保持状态张量、采样率/块长契约，并用噪声、静音和多人语音验收。已下载，不代表运行集成完成。
3. **Whisper tiny/base 多语言版**：[官方模型说明](https://github.com/openai/whisper) 明确代码与权重为 MIT；`.en` 版本不适合中文。[whisper.cpp](https://github.com/ggml-org/whisper.cpp) 有 Android/iOS 示例及端侧运行路径。建议作为许可清晰的默认转写候选，量化后在目标手机实测大小、内存、速度和中文表现；目前未下载/集成。不能把桌面速度当手机速度。
4. **SenseVoiceSmall**：[发布者模型卡](https://huggingface.co/FunAudioLLM/SenseVoiceSmall) 提供中文/粤语等识别与 ONNX 路线；[sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) 提供跨平台运行选项。模型卡当前为 `license: other`，指向 [FunASR MODEL_LICENSE](https://github.com/modelscope/FunASR/blob/main/MODEL_LICENSE)，不应称为 Apache/MIT 权重。作为中文识别对比候选，先核实条款并冻结版本；情绪/音频事件输出不直接当神经功能评分。目前未下载/集成。
5. **wav2vec2-base-960h**：[Meta 模型卡](https://huggingface.co/facebook/wav2vec2-base-960h) 标注 Apache-2.0、英语、LibriSpeech。可作研究特征基线，不是现成中文构音障碍分类器，旧 demo 的 embedding 不代表已获得临床分类权重。
6. **openSMILE**：[官方说明](https://github.com/audeering/opensmile#license) 限制开源版本用于商业产品。厂家合作版不应未经许可打包；若需要其声学特征，可购买许可或自行实现所需基础 DSP 指标并验证。

未在本次核验中找到可以直接覆盖六项、且具备目标中文居家人群验证的完整卒中模型。已有文献/演示与可复用权重的区分见 [原研究来源](../../befast-feature-demo/SOURCES.md)。不能据此断言所有相关研究都没有公开权重。

## 下载证据

缓存目录：`/Volumes/macOSexternal/Documents/proj/model-cache/befast`，不纳入 Git，不自动加入 APK/IPA。机器可读来源与校验值见 [模型清单](BEFAST_MODEL_MANIFEST.json)。

- Face：3,758,596 bytes，SHA256 `64184e229b263107bc2b804c6625db1341ff2bb731874b0bcc2fe6544e0bc9ff`。ZIP CRC 通过；包内有 face detector、landmark detector、blendshape TFLite 与几何元数据。
- Silero：2,327,524 bytes，SHA256 `1a153a22f4509e292a94e67d6f9b85e8deb25b4988682b7e174c65279d8788e3`。下载与哈希完成；当前默认 Python 没有 ONNX/ORT，尚未进行结构或推理验证。
- 官方 Google 网页受本机 TLS 错误影响，因此核查使用其官方 GitHub 示例/API 和示例中的模型存储 URL；不把无法读取的页面当证据。

## Android 优先实施顺序与验收

1. **统一会话与 F/A/T**：沿用白底红色 Motion Lab 设计，新增 BEFAST 入口和任务页；保持录制结束后分析。F 加面部推理，A 复用 Heavy 做上肢任务，T/头痛先做结构化患者记录。保存原始值、质量状态、单位、任务版本、左右约定、来源，而非只存一个综合分数。
2. **S 语音**：增加可见的麦克风录制流程、固定语句/持续元音、VAD/DSP，再接一种转写引擎。先对中文、方言、静音、电视声和低信噪比做样例验收；不把流畅转写当没有构音障碍。
3. **B/E 标准化与趋势**：沿用已实现模型，补齐任务一致性与个体基线；眼动质量不足返回不可判读。B 测试固定位置、姿态/遮挡和不完整身体，A/F 测试镜像/头转/多人与遮挡，检查所有模块的缺失状态和报告可复核性。
4. **服务端与医生复核**：扩展现有服务支持 `befast_session` 及 face/arm/speech/headache/time 结果。建议包含 sessionId、module、taskVersion、modelVersion/hash、timestamps、quality、features+units、selfReport、artifactRefs、analysisOrigin；保留 accountId/recordId、不可变版本、增量同步、hash 下载和 archive 语义。客户端推理状态不能冒充服务端诊断。
5. **临床与硬件阶段**：再接明确厂商的手环 SDK、时间戳/单位/设备精度与缺失处理；血压不能默认所有手环都能可靠输出。经过患者/设备/场景隔离的验证后才讨论阈值和多模态预警模型。Apple 随已稳定的 Android 协议逐项移植，分别做设备验收。

最低技术验收：F/A/S 实际模型输入输出、指标 fixture、离线重启持久化、同步/下载/归档和错误重试；相机/麦克风权限拒绝与中断；目标 Android 真机耗时/内存/温升；用户可区分未采集、质量不足、特征结果和患者自评。研究对照另需临床参考标准、目标队列、校准、敏感度/特异度及误报分析，不能被 smoke test 替代。

## 与汇报文件的架构差异

- 汇报要求“院内部署、仅上传脱敏特征”，当前系统是独立外部服务器且支持原视频和客户端报告上传。本轮不改上传行为；后续新增独立随访配置，默认仅传所需特征，原视频上传需明确选择与机构流程，部署迁移院内环境后才能宣称数据不出院。特征向量也不自动等于匿名数据。
- HTTPS 是传输加密，服务器仍可读取数据，不等同于只有通信端点可解密的端到端加密。
- “24 h 无感摄像/麦克风”不能由普通手机 App 的录制入口自然推导。本轮方案采用用户可见的短时任务；持续手环采集、后台能力、知情同意/退出、医院接口分别规划。
- 文件中的自动中危/高危规则、NRS 推断、30 例内测与 100 例 RCT 是提案内容，不是已验证算法或已完成研究；本轮不伪造对应能力/数据。

## Git 交付节点

此前 Apple/后端节点已通过 [PR #1](https://github.com/PinkR1ver/home_nystagmus_monitor/pull/1) 合并，main 提交 `5a157cdb58cc9b8064cba423a557f6fa9f0b99c2`，GitGuardian 检查通过。原 Apple 分支保留；166 MB 演示源视频经独立发布分支迁移到 LFS。当前研究从合并后的 main 新建 `codex/befast-model-research`，没有改动 App 或线上数据库。
