# Local Record Server

用于在本仓库内启动一个本地服务端，接收 Android 上传的视频记录，并调用 `SwinUNet-VOG/vertiwisdom.py` 进行分析。

## 1) 安装依赖

```bash
cd server
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

另外请确保当前 Python / conda 环境已安装 `vertiwisdom.py` 依赖（如 `torch`、`opencv-python`、`mediapipe`、`numpy`、`scipy` 等），并且
模型已放到本仓库：`server/models/checkpoint_best.pth`（推荐），
或设置环境变量 `VOG_CHECKPOINT_PATH=/abs/path/to/checkpoint_best.pth`。

## 2) 启动服务

```bash
cd server
source .venv/bin/activate
uvicorn main:app --host 0.0.0.0 --port 8787 --reload
```

如果模型路径不在默认位置，可这样启动：

```bash
VOG_CHECKPOINT_PATH=/你的路径/checkpoint_best.pth uvicorn main:app --host 0.0.0.0 --port 8787 --reload
```

## 3) 接口

- `GET /health`
  - 健康检查
- `POST /api/videos`
  - 接收单条视频上传（multipart/form-data），并在服务端使用 `vertiwisdom.py` 分析
  - 表单字段：
    - `accountId`
    - `recordId`
    - `accountName`
    - `startedAt`
    - `durationSec`
    - `video`（mp4/mov/avi 等）
- `GET /api/records?accountId=xxx&limit=100`
  - 查看已接收记录

## 4) Android 端配置

在 App 设置页把服务器地址填成：

- 同一台电脑模拟器：`http://10.0.2.2:8787`
- 真机（同局域网）：`http://<你的电脑IP>:8787`

说明：
App 上传时会自动拼接 `/api/videos`，所以地址只填到端口即可。

## 5) 数据存储

- 主存储：`server/data/records.db`（SQLite）
- 上传视频：`server/data/uploads/`
- 兼容迁移：如果存在旧的 `server/data/records.jsonl` 且数据库为空，启动时会自动迁移到 SQLite。

## 6) 数据库建议

- 当前落地：`SQLite`（零运维、单机可靠，适合你现在本地+单服务部署）
- 后续上线到多实例/高并发时，建议迁移 `PostgreSQL`（并发写、备份、权限管理更完整）
