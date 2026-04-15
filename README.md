# Home Nystagmus Monitor

居家眼震监测 Android 应用，用于采集、分析与记录管理，并支持向远端系统上传记录。

## 当前能力
- 基于 Compose 的三栏主界面（采集 / 记录 / 设置）
- 患者账号登录、历史账号切换、最近登录自动恢复
- CameraX 实时采集与固定硬件场景下的眼部区域处理
- 录制视频记录并上传到服务端分析
- 分账号记录管理与上传流程（服务端返回分析结果）

## 项目结构
- `AGENTS.md`：项目规则、里程碑与长期约定
- `app/src/main/java/com/kk/homenystagmusmonitor/data`：数据模型与数据层
- `app/src/main/java/com/kk/homenystagmusmonitor/ui`：界面与状态管理
- `server/`：FastAPI 服务端、SQLite、报告与 ZIP 打包逻辑
- `server/deploy/`：离线医院服务器交付脚本、锁定依赖与部署文档

## 本地运行
1. 使用 Android Studio 打开项目根目录
2. 等待 Gradle 同步完成
3. 运行 `app` 模块到真机或模拟器

## 本地接收服务端
仓库内已提供可运行的记录接收服务端，路径：`server/`。

1. 创建并激活虚拟环境
   - `cd server`
   - `python3 -m venv .venv`
   - `source .venv/bin/activate`
2. 安装依赖
   - `pip install -r requirements.txt`
3. 启动服务
   - `uvicorn main:app --host 0.0.0.0 --port 8787 --reload`

如果目标是离线医院服务器交付，请不要直接复制本地 `.venv`，优先看：

- `server/deploy/README.md`
- `server/deploy/runtime-matrix.md`

常用接口：
- `GET /health`
- `POST /api/records`
- `GET /api/records`

Android 端服务器地址建议：
- 模拟器：`http://10.0.2.2:8787`
- 真机（同局域网）：`http://<电脑局域网IP>:8787`
