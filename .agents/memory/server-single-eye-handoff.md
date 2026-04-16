# 服务端 single_eye 交接单

## 这份文档是干什么的

给下一位 agent 一个最短路径的 handoff：

- 先知道当前服务端已经收口到什么状态
- 再知道本地怎么验证
- 最后知道后续改动时不要误回滚什么

## 当前状态

截至当前仓库状态，服务端分析链路已经明确收口为：

- 只支持 `single_eye`

这意味着：

- `server/main.py` 中的 `inputMode` 仍然保留为接口兼容字段
- 但服务端会统一归一为 `single_eye`
- 即使上传时传 `full_face`，最终服务端也会按 `single_eye` 处理

## 已完成的关键改动

### 1. 移除 MediaPipe 依赖

当前仓库已经不再依赖 `mediapipe`：

- `server/requirements.txt` 已移除 `mediapipe`
- `server/deploy/requirements/runtime-common.lock.txt` 已移除 `mediapipe`
- 部署文档里与 `mediapipe` 绑定的描述已同步删除

### 2. 算法运行时只保留单眼路径

关键文件：

- `server/vendor/SwinUNet-VOG/vertiwisdom.py`
- `server/main.py`

当前设计：

- vendored `vertiwisdom.py` 里的眼部 ROI 提取器已改成单眼实现
- 内部主流程实际使用 `SingleEyeNormalizer`
- 保留了一个兼容别名：
  - `MediaPipeEyeNormalizer = SingleEyeNormalizer`

保留这个别名的目的：

- 避免上层调用点在短期内因为类名变化而断掉
- 但它已经不代表 MediaPipe 逻辑

### 3. 服务端接口兼容但已收口

`POST /api/videos` 当前状态：

- 仍接收表单字段 `inputMode`
- 但最终会统一落成 `single_eye`

这能保证：

- Android 端暂时不用同步修改协议
- 旧脚本即使还传 `full_face` 也不会直接报错

## 本地验证结果

已用本机样例视频验证通过：

- 样例：`test/249.mp4`
- `/health` 正常
- `/api/videos` 上传成功
- 分析成功
- 产物成功生成：
  - PDF
  - 眼部视频
  - ZIP

一次关键验证点：

- 上传时故意传 `inputMode=full_face`
- 服务端返回仍是 `inputMode=single_eye`

这说明兼容层工作正常。

## 本地复现方式

在仓库根目录：

```bash
source server/.venv/bin/activate
cd server
uvicorn main:app --host 127.0.0.1 --port 8788
```

然后在另一个终端：

```bash
curl -sS -X POST "http://127.0.0.1:8788/api/videos" \
  -F "accountId=test-account-249" \
  -F "recordId=rec_test_249_manual" \
  -F "accountName=本地测试" \
  -F "patientId=patient-249" \
  -F "startedAt=2026-04-16 15:45:00" \
  -F "durationSec=10" \
  -F "inputMode=full_face" \
  -F "video=@test/249.mp4;type=video/mp4"
```

期望结果：

- 请求成功
- 返回 JSON 中 `inputMode` 为 `single_eye`

## 后续改动时不要误做的事

- 不要把 `full_face` 分支重新接回来，除非用户明确要求恢复双路径
- 不要重新把 `mediapipe` 塞回依赖，只因为看到兼容别名还叫 `MediaPipeEyeNormalizer`
- 不要把 `inputMode` 字段直接从接口删掉，除非 Android / 调用方同步完成

## 当前最值得优先做的下一步

如果用户继续要求“精简”或“部署清理”，优先考虑：

1. 继续压缩 `server/vendor/SwinUNet-VOG/` 中仍然不需要的 UI/兼容层代码
2. 检查部署脚本里是否还有对旧运行矩阵的暗含假设
3. 如果 Android 端也准备同步收口，再删除上传里的 `inputMode` 冗余兼容逻辑
