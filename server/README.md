# Local Record Server

用于在本仓库内启动一个本地服务端，接收 Android 上传的视频记录，并调用 `SwinUNet-VOG/vertiwisdom.py` 进行分析。

如果你要看部署方案，请先看：

- `server/deploy/README.md`

其中已经拆成两条路线：

- `server/deploy/hospital-openeuler-offline/README.md`
- `server/deploy/aliyun-ubuntu24/README.md`

## 1) 本地开发安装

```bash
cd server
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## 2) 准备算法与模型

当前服务支持两种默认位置：

- 算法工程：`server/vendor/SwinUNet-VOG/`
- 模型目录：`server/models/`

至少需要满足下面其一：

1. 把 `vertiwisdom.py` 所在算法工程解压到 `server/vendor/SwinUNet-VOG/`
2. 或设置 `HNM_VOG_DIR=/abs/path/to/SwinUNet-VOG`
3. 如果 `vertiwisdom.py` 不在算法目录根部，可再设置 `HNM_VOG_MODULE_PATHS`

checkpoint 可放到：

- `server/models/checkpoint_best.pth`
- 或设置 `VOG_CHECKPOINT_PATH=/abs/path/to/checkpoint_best.pth`

## 3) 启动服务

```bash
cd server
source .venv/bin/activate
uvicorn main:app --host 0.0.0.0 --port 8787 --reload
```

例如显式指定运行时目录：

```bash
HNM_VOG_DIR=/data/hnm/vendor/SwinUNet-VOG \
HNM_MODEL_DIR=/data/hnm/models \
HNM_DATA_DIR=/data/hnm/runtime \
uvicorn main:app --host 0.0.0.0 --port 8787
```

## 4) 关键环境变量

- `HNM_DATA_DIR`
  - 数据目录，默认 `server/data`
- `HNM_MODEL_DIR`
  - 模型目录，默认 `server/models`
- `HNM_VOG_DIR`
  - 算法工程目录，默认 `server/vendor/SwinUNet-VOG`
- `HNM_VOG_MODULE_PATHS`
  - 额外的 `vertiwisdom.py` 搜索目录，使用系统路径分隔符拼接
- `VOG_CHECKPOINT_PATH`
  - 直接指定 checkpoint 文件

## 5) 接口

- `GET /health`
  - 健康检查，同时返回当前 runtime 路径配置
- `POST /api/videos`
  - 接收单条视频上传（multipart/form-data），并在服务端使用 `vertiwisdom.py` 分析
  - 表单字段：
    - `accountId`
    - `recordId`
    - `accountName`
    - `startedAt`
    - `durationSec`
    - `patientId`
    - `inputMode`：兼容保留字段，服务端当前始终按 `single_eye` 处理
    - `video`（mp4/mov/avi 等）
- `GET /api/records?accountId=xxx&limit=100`
  - 查看已接收记录

## 6) Android 端配置

在 App 设置页把服务器地址填成：

- 同一台电脑模拟器：`http://10.0.2.2:8787`
- 真机（同局域网）：`http://<你的电脑IP>:8787`

说明：
App 上传时会自动拼接 `/api/videos`，所以地址只填到端口即可。

## 7) 数据存储

- 主存储：`server/data/records.db`（SQLite）
- 上传视频：`server/data/uploads/`
- 报告：`server/data/reports/`
- 眼部视频：`server/data/eye_videos/`
- ZIP：`server/data/packages/`
- 兼容迁移：如果存在旧的 `server/data/records.jsonl` 且数据库为空，启动时会自动迁移到 SQLite。

## 8) 数据库建议

- 当前落地：`SQLite`（零运维、单机可靠，适合你现在本地+单服务部署）
- 后续上线到多实例/高并发时，建议迁移 `PostgreSQL`（并发写、备份、权限管理更完整）
