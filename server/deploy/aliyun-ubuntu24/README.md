# HNM Aliyun Ubuntu 24.04 Deployment

本方案对应新的在线部署路径：

- 目标机：`Ubuntu 24.04`
- 部署环境：阿里云 ECS
- GPU：`NVIDIA L20`
- CUDA 驱动：已安装
- 网络：可以联网，但优先使用国内可访问源
- 部署形态：宿主机 `Python + venv + systemd`
- 不使用 Docker

如果你现在就要上机执行，直接看：

- `server/deploy/aliyun-ubuntu24/CHECKLIST.md`

## 方案结论

推荐使用：

- `python3.12 + venv`
- `uvicorn`
- `systemd`
- 公共依赖走阿里云 PyPI 镜像
- `torch/torchvision` 优先走国内可访问 PyTorch 源或本地 wheelhouse

## 与旧医院方案的区别

这条路线：

- 不需要“解压即跑”的自带 Python runtime
- 不需要 `conda-pack`
- 不需要目标机离线 wheel 安装
- 但仍建议保留 `wheelhouse` 作为 GPU 依赖兜底

## 推荐目录

建议服务器目录形态如下：

```text
/opt/hnm/
  server/
    main.py
    web/
    models/
    vendor/SwinUNet-VOG/
    deploy/
  data/
  logs/
  run/
```

## 推荐步骤

1. 把项目里的 `server/` 上传到服务器，例如 `/opt/hnm/server`
2. 把算法工程放到 `/opt/hnm/server/vendor/SwinUNet-VOG`
3. 把模型权重放到 `/opt/hnm/server/models`
4. 复制环境模板：
   - `cp deploy/aliyun-ubuntu24/env/hnm-server.aliyun.env.example deploy/aliyun-ubuntu24/env/hnm-server.aliyun.env`
5. 按实际路径修改环境文件
6. 执行在线安装脚本：
   - `ENV_FILE=deploy/aliyun-ubuntu24/env/hnm-server.aliyun.env deploy/scripts/install_online_ubuntu.sh`
7. 验证 CUDA：
   - `ENV_FILE=deploy/aliyun-ubuntu24/env/hnm-server.aliyun.env deploy/scripts/check_torch_cuda.sh`
8. 安装 systemd 单元：
   - `sudo ENV_FILE=... deploy/scripts/install_systemd_service.sh`
9. 启动服务后验收：
   - `deploy/scripts/healthcheck.sh`
   - `deploy/scripts/smoke_test_upload.sh /path/to/test/249.mp4`

## PyTorch 安装策略

当前仓库锁定版本见：

- `server/deploy/runtime-matrix.md`

重点说明：

- 公共依赖默认走 `https://mirrors.aliyun.com/pypi/simple/`
- `torch==2.11.0` / `torchvision==0.26.0` 的 GPU 轮子不一定完整存在于阿里云镜像
- 所以脚本支持三种优先级：
  1. `TORCH_WHEELHOUSE`：本地 wheel 目录
  2. `TORCH_INDEX_URL`：国内可访问的 PyTorch 源
  3. 默认使用 `PIP_INDEX_URL`

如果在线安装后 `torch.cuda.is_available()` 为 `False`，优先检查：

- 驱动是否可用：`nvidia-smi`
- `torch` 实际安装来源
- 服务器能否访问对应 PyTorch GPU wheel 源

## systemd 说明

本方案使用：

- `deploy/scripts/run_server_foreground.sh` 作为 `ExecStart`
- `deploy/aliyun-ubuntu24/systemd/hnm-server.service.example` 作为模板

优点是：

- `systemd` 只负责托管
- 真正的运行参数仍由环境文件统一控制
- 不需要在 service 文件里硬编码一堆路径

## 风险提醒

- `vertiwisdom.py` 不在 PyPI，必须手动放到 `vendor/SwinUNet-VOG/`
- 模型权重不在 git，必须手动放到 `models/`
- GPU 可用性取决于驱动和 `torch` 安装来源，不取决于脚本本身
- 建议保留一个 `cpu` fallback 配置，防止 GPU 安装源不可用时阻塞上线
