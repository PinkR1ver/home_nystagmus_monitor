# HNM Deployment Index

本目录现在拆成两条部署路线：

## 场景 1：医院离线 openEuler

适用于：

- `openEuler 22.03 (x86_64)`
- 不能联网
- 以离线交付为主

看这里：

- `server/deploy/hospital-openeuler-offline/README.md`

## 场景 2：阿里云 Ubuntu 24.04 在线部署

适用于：

- `Ubuntu 24.04`
- 阿里云服务器
- `NVIDIA L20`
- CUDA 驱动已装好
- 可以联网，但主要使用国内可访问源
- 不使用 Docker

看这里：

- `server/deploy/aliyun-ubuntu24/README.md`

## 共享文件

下面这些文件是两条路线共用的：

- `env/hnm-server.env.example`
- `requirements/runtime-common.lock.txt`
- `requirements/runtime-gpu-cu126.lock.txt`
- `requirements/runtime-cpu.lock.txt`
- `runtime-matrix.md`
- `scripts/package_offline_bundle.sh`
- `scripts/healthcheck.sh`
- `scripts/smoke_test_upload.sh`
- `scripts/stop_server.sh`

## 仍然保留但仅适用于旧离线路线的脚本

- `scripts/build_wheelhouse.sh`
- `scripts/install_offline.sh`
- `scripts/start_server.sh`

## 新增给 Ubuntu 24.04 在线部署使用的文件

- `aliyun-ubuntu24/env/hnm-server.aliyun.env.example`
- `aliyun-ubuntu24/systemd/hnm-server.service.example`
- `scripts/install_online_ubuntu.sh`
- `scripts/run_server_foreground.sh`
- `scripts/install_systemd_service.sh`
- `scripts/check_torch_cuda.sh`
