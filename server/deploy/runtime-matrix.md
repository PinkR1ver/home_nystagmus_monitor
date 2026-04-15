# Runtime Matrix

## Frozen Matrix

- Profile: `gpu-cu126`
- OS: `openEuler 22.03 (x86_64)`
- glibc baseline: `2.34`
- Python: `3.12`
- Torch: `2.11.0`
- TorchVision: `0.26.0`
- Torch index: `https://download.pytorch.org/whl/cu126`
- MediaPipe: `0.10.14`
- OpenCV: `4.13.0.92`
- NumPy: `2.4.4`
- SciPy: `1.17.1`
- FastAPI: `0.135.3`
- Uvicorn: `0.44.0`

## Driver Guidance

- 推荐 NVIDIA Linux Driver：`560.35.03+`
- 若医院 GPU 或驱动与 `cu126` 不兼容，可退回 `cpu` profile

## Why This Matrix

- `openEuler 22.03` 的 `glibc 2.34` 可覆盖 `manylinux_2_28` 轮子要求
- 当前项目本地运行时已验证 `Python 3.12 + mediapipe 0.10.14`
- 当前仓库环境中实际安装的核心版本就是本文件锁定的版本
- GPU 交付以 `cu126` 为默认档，便于提前离线准备 wheelhouse
