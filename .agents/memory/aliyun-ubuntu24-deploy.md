# 阿里云 Ubuntu 24.04 部署执行单

## 目标

把服务端部署到：

- `Ubuntu 24.04`
- 阿里云 ECS
- GPU：`NVIDIA L20`
- CUDA 驱动已安装
- 可以联网，但优先使用国内源
- 不使用 Docker

推荐形态：

- `python3.12 + venv + systemd`

## 先看这些文件

- `server/deploy/README.md`
- `server/deploy/aliyun-ubuntu24/README.md`
- `server/deploy/runtime-matrix.md`
- `server/deploy/scripts/install_online_ubuntu.sh`
- `server/deploy/scripts/run_server_foreground.sh`
- `server/deploy/scripts/install_systemd_service.sh`
- `server/deploy/scripts/check_torch_cuda.sh`

## 当前已经有的东西

- `server/main.py` 已支持运行时路径配置
- `server/vendor/SwinUNet-VOG` 作为默认算法目录
- `server/models` 作为默认模型目录
- 公共锁定文件已在 `server/deploy/requirements/`
- 已经有健康检查和样例上传脚本

## 这条路线要怎么做

1. 上传 `server/` 到服务器，例如 `/opt/hnm/server`
2. 放好：
   - `vendor/SwinUNet-VOG`
   - `models/checkpoint_best.pth`
3. 复制环境文件：
   - `cp deploy/aliyun-ubuntu24/env/hnm-server.aliyun.env.example deploy/aliyun-ubuntu24/env/hnm-server.aliyun.env`
4. 修改路径、端口、用户
5. 运行：
   - `ENV_FILE=... deploy/scripts/install_online_ubuntu.sh`
6. 运行：
   - `ENV_FILE=... deploy/scripts/check_torch_cuda.sh`
7. 安装 systemd：
   - `sudo ENV_FILE=... deploy/scripts/install_systemd_service.sh`
8. 启动服务：
   - `sudo systemctl start hnm-server`
9. 验收：
   - `ENV_FILE=... deploy/scripts/healthcheck.sh`
   - `ENV_FILE=... deploy/scripts/smoke_test_upload.sh /path/to/249.mp4`

## 关键提醒

- 公共依赖默认走阿里云 PyPI 镜像
- `torch==2.11.0` / `torchvision==0.26.0` 的 GPU 轮子不一定完整存在于阿里云镜像
- 所以 GPU 安装优先级是：
  1. `TORCH_WHEELHOUSE`
  2. `TORCH_INDEX_URL`
  3. `PIP_INDEX_URL`

如果 `check_torch_cuda.sh` 里 `cuda_available=false`：

- 先看 `nvidia-smi`
- 再看实际安装的 torch 来源
- 最后再决定是否切到 `cpu` profile
