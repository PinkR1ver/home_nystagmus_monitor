# HNM Offline Hospital Deployment

本方案对应旧的医院离线交付路径：

- 目标机：`openEuler 22.03 (x86_64)`
- 目标机：不能联网
- 目标机：希望使用 NVIDIA GPU

如果你现在要部署到阿里云 `Ubuntu 24.04`，不要看这份，改看：

- `server/deploy/aliyun-ubuntu24/README.md`

## 推荐运行矩阵

当前仓库按下面这组矩阵做离线锁定：

- Linux：`openEuler 22.03 (x86_64)`
- Python：`3.12`
- GPU：`NVIDIA`
- PyTorch 通道：`cu126`
- 推荐驱动：`560.35.03+`

原因：

- `openEuler 22.03` 的 `glibc` 基线足以覆盖 `manylinux_2_28` 轮子要求
- 当前本地验证环境已经跑通 `mediapipe==0.10.14` 与 `Python 3.12`
- `torch==2.11.0` / `torchvision==0.26.0` 可按 `cu126` 预下载 GPU 轮子
- 相比更新的 CUDA 通道，`cu126` 对旧一些的医院 GPU 兼容面更稳

如果医院机器最终只能跑 CPU，可切换到 `cpu` profile。

## 交付物建议

- `server/`：服务端源码与 Dashboard 静态资源
- `wheelhouse/`：离线 Python 依赖仓库
- `vendor/SwinUNet-VOG/`：`vertiwisdom.py` 所在算法工程
- `models/`：`checkpoint_best.pth` 等模型权重
- `samples/249.mp4`：验收用样例视频

## 目录说明

- `../env/hnm-server.env.example`：医院服务器环境变量模板
- `../requirements/runtime-common.lock.txt`：公共离线依赖锁定
- `../requirements/runtime-gpu-cu126.lock.txt`：GPU 依赖锁定
- `../requirements/runtime-cpu.lock.txt`：CPU 依赖锁定
- `../scripts/build_wheelhouse.sh`：联网环境构建离线 wheelhouse
- `../scripts/package_offline_bundle.sh`：整理医院交付包
- `../scripts/install_offline.sh`：医院服务器离线安装
- `../scripts/start_server.sh`：后台启动服务
- `../scripts/stop_server.sh`：停止服务
- `../scripts/healthcheck.sh`：健康检查
- `../scripts/smoke_test_upload.sh`：样例上传验收

## 默认路径约定

`server/main.py` 已支持这些环境变量：

- `HNM_DATA_DIR`
- `HNM_MODEL_DIR`
- `HNM_VOG_DIR`
- `HNM_VOG_MODULE_PATHS`
- `VOG_CHECKPOINT_PATH`

默认情况下：

- 模型目录：`server/models`
- 算法目录：`server/vendor/SwinUNet-VOG`
- 数据目录：`server/data`

## 推荐交付流程

1. 在联网构建机准备 Python 3.12。
2. 运行 `../scripts/build_wheelhouse.sh` 生成离线依赖仓库。
3. 把 `SwinUNet-VOG` 放到 `server/vendor/SwinUNet-VOG`，模型放到 `server/models/`。
4. 运行 `../scripts/package_offline_bundle.sh` 生成最终交付目录。
5. 把交付目录拷贝到医院服务器。
6. 在医院服务器执行 `../scripts/install_offline.sh`。
7. 配置 `../env/hnm-server.env` 后执行 `../scripts/start_server.sh`。
8. 使用 `../scripts/healthcheck.sh` 与 `../scripts/smoke_test_upload.sh` 做验收。

## openEuler 额外注意

- 医院服务器是 RPM 体系，不要直接照抄 Ubuntu/Debian 的系统包命令。
- 离线 wheelhouse 仍然可以沿用 Python manylinux 轮子思路，不需要改成源码编译为主。
- 真正需要和医院运维确认的是 NVIDIA 驱动版本、CUDA 兼容关系、以及 `python3.12` 的安装来源。
