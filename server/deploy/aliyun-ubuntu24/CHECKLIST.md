# Aliyun Ubuntu 24.04 Deploy Checklist

## 0. 目标环境

- 系统：`Ubuntu 24.04`
- 机器：阿里云 ECS
- GPU：`NVIDIA L20`
- CUDA 驱动：已安装
- 网络：可联网，优先使用国内可访问源
- 部署形态：宿主机 `python3.12 + venv + systemd`

## 1. 先上传哪些文件

### 推荐做法：直接上传整个 `server/`

上传本地目录：

- `server/`

原因：

- 少漏文件
- `web/`、`deploy/`、`main.py`、`requirements.txt` 会一起到位
- 后面按文档操作最简单

### 但有两个内容当前仓库里没有，需要你额外补上

必须额外上传到服务器：

1. 算法工程目录
   - 目标路径：`/opt/hnm/server/vendor/SwinUNet-VOG`
   - 要求：目录里直接能找到 `vertiwisdom.py`

2. 模型权重
   - 目标路径：`/opt/hnm/server/models/checkpoint_best.pth`
   - 或者放在别处，但要在环境文件里设置 `VOG_CHECKPOINT_PATH`

### 样例视频

建议额外上传一份：

- `test/249.mp4`

例如放到：

- `/opt/hnm/test/249.mp4`

用于最后执行验收上传。

## 2. 服务器目标目录

建议在服务器上整理成：

```text
/opt/hnm/
  server/
    main.py
    requirements.txt
    web/
    deploy/
    vendor/SwinUNet-VOG/
    models/checkpoint_best.pth
  data/
  logs/
  run/
  test/249.mp4
```

## 3. 服务器上执行步骤

### 3.1 进入服务目录

```bash
cd /opt/hnm/server
```

### 3.2 复制环境模板

```bash
cp deploy/aliyun-ubuntu24/env/hnm-server.aliyun.env.example \
   deploy/aliyun-ubuntu24/env/hnm-server.aliyun.env
```

### 3.3 编辑环境文件

至少确认这些值：

- `HNM_DATA_DIR=/opt/hnm/data`
- `HNM_MODEL_DIR=/opt/hnm/server/models`
- `HNM_VOG_DIR=/opt/hnm/server/vendor/SwinUNet-VOG`
- `HNM_LOG_DIR=/opt/hnm/logs`
- `HNM_RUN_DIR=/opt/hnm/run`
- `HNM_VENV_DIR=/opt/hnm/server/.venv-aliyun`
- `HNM_DEPLOY_PROFILE=gpu-cu126`
- `HNM_WORKERS=1`
- `PYTHON_BIN=python3.12`

如果 `checkpoint_best.pth` 不放在默认位置，再设置：

- `VOG_CHECKPOINT_PATH=/你的绝对路径/checkpoint_best.pth`

## 4. 安装依赖

```bash
ENV_FILE=deploy/aliyun-ubuntu24/env/hnm-server.aliyun.env \
bash deploy/scripts/install_online_ubuntu.sh
```

如果 `torch` GPU 包无法直接在线装上，优先补这两个变量之一后重试：

- `TORCH_WHEELHOUSE=/opt/hnm/wheelhouse`
- `TORCH_INDEX_URL=<国内可访问的 pytorch cu126 源>`

## 5. 检查 GPU 是否真的可用

```bash
nvidia-smi
```

```bash
ENV_FILE=deploy/aliyun-ubuntu24/env/hnm-server.aliyun.env \
bash deploy/scripts/check_torch_cuda.sh
```

验收目标：

- `cuda_available` 为 `true`
- `device_names` 里能看到 `NVIDIA L20`

## 6. 安装 systemd 服务

```bash
sudo ENV_FILE=/opt/hnm/server/deploy/aliyun-ubuntu24/env/hnm-server.aliyun.env \
bash /opt/hnm/server/deploy/scripts/install_systemd_service.sh
```

启动服务：

```bash
sudo systemctl start hnm-server
sudo systemctl status hnm-server
```

## 7. 健康检查

```bash
ENV_FILE=/opt/hnm/server/deploy/aliyun-ubuntu24/env/hnm-server.aliyun.env \
bash /opt/hnm/server/deploy/scripts/healthcheck.sh
```

重点看：

- `vertiwisdomReady` 是否为 `true`
- `runtimeConfig.modelDir`
- `runtimeConfig.vogDir`
- `runtimeConfig.checkpoint`

## 8. 样例上传验收

```bash
ENV_FILE=/opt/hnm/server/deploy/aliyun-ubuntu24/env/hnm-server.aliyun.env \
bash /opt/hnm/server/deploy/scripts/smoke_test_upload.sh /opt/hnm/test/249.mp4
```

验收通过标准：

- 接口返回 `uploadedRecordId`
- 返回 `analysisCompleted=true`
- 返回 `reportFile`
- 返回 `eyeVideoFile`
- 返回 `packageFile`

## 9. 如果出问题先查什么

### `/health` 里 `vertiwisdomReady=false`

先查：

- `vendor/SwinUNet-VOG/vertiwisdom.py` 是否真的在
- `models/checkpoint_best.pth` 是否真的在
- 环境文件里的 `HNM_VOG_DIR` / `HNM_MODEL_DIR` / `VOG_CHECKPOINT_PATH`

### `cuda_available=false`

先查：

- `nvidia-smi`
- `check_torch_cuda.sh` 输出的 `torch_cuda_version`
- `torch` 是否装成了 CPU 版

### 服务起不来

先查：

- `sudo systemctl status hnm-server`
- `/opt/hnm/logs/hnm-server.log`

## 10. 最小上传文件清单

如果你不想直接传整个 `server/`，最少也要传这些：

- `server/main.py`
- `server/requirements.txt`
- `server/web/`
- `server/deploy/`
- `server/vendor/SwinUNet-VOG/`（你额外补）
- `server/models/checkpoint_best.pth`（你额外补）
- `test/249.mp4`

但实际仍然更推荐：

- 直接上传整个 `server/`
- 再额外补 `vendor/SwinUNet-VOG/`
- 再额外补 `models/checkpoint_best.pth`
