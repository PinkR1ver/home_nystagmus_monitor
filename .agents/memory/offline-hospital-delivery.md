# 离线医院交付执行单

## 目标
把当前项目做成适用于医院机器的最终交付包：

- 目标机：`openEuler 22.03 (x86_64)`
- 目标机：`不能联网`
- 目标机：`没有 Python`
- 目标机：`不能安装 RPM / 系统依赖`
- 希望支持：`NVIDIA GPU`

最终包必须满足：

- `解压即跑`
- `自带 Python 运行时`
- `不依赖目标机 python/pip/venv`

## 先看这些文件

- [server/main.py](server/main.py)
- [server/deploy/README.md](server/deploy/README.md)
- [server/deploy/runtime-matrix.md](server/deploy/runtime-matrix.md)
- [server/deploy/scripts/package_offline_bundle.sh](server/deploy/scripts/package_offline_bundle.sh)
- [server/deploy/scripts/start_server.sh](server/deploy/scripts/start_server.sh)
- [server/deploy/scripts/install_offline.sh](server/deploy/scripts/install_offline.sh)

## 当前已经完成

- `server/main.py` 已支持运行时目录配置：
  - `HNM_DATA_DIR`
  - `HNM_MODEL_DIR`
  - `HNM_VOG_DIR`
  - `HNM_VOG_MODULE_PATHS`
  - `VOG_CHECKPOINT_PATH`
- 默认算法目录：`server/vendor/SwinUNet-VOG`
- 默认模型目录：`server/models`
- 已补好 `server/deploy/` 的文档、锁定文件、脚本骨架
- 已做过一轮本地 bundle 演练：
  - `/health` 通过
  - 样例上传通过
  - 能生成 DB、PDF、眼部视频、ZIP

## 当前还没完成

当前脚本仍然默认目标机有 Python：

- `install_offline.sh` 还在走 `python3.12 -m venv`
- `start_server.sh` 还在依赖 venv 里的解释器

所以当前状态是：

- 已适配“有 Python 的离线机”
- 还没适配“无 Python 的医院机”

## 不要做的事

- 不要在 macOS 上产出最终医院运行包
- 不要继续把最终方案建立在 `wheelhouse + 目标机创建 venv`
- 不要复制 macOS 的 `.venv`
- 不要优先走 PyInstaller

## 推荐执行环境

在 Ubuntu 宿主机上：

1. 用 `distrobox` 创建 `openEuler 22.03 x86_64`
2. 把本项目放进这个 box
3. 所有最终打包动作都在这个 `openEuler` box 里完成

## 推荐打包方向

优先选：

- `conda-pack` / `micromamba-pack`

原因：

- 目标机没有 Python
- 需要打包解释器 + 依赖 + torch + opencv
- 这条路线最适合做“runtime/ 解压即跑”

如果不走 conda，也要实现等价目标：

- 产出可搬运的 `runtime/`
- 里面自带 `python`
- 里面自带所有依赖

## 目标目录形态

最终交付包应接近：

```text
offline-bundle/
  runtime/
  server/
    main.py
    web/
    models/
    vendor/SwinUNet-VOG/
    deploy/
  runtime-data/
  samples/
```

## GPU 结论

默认矩阵已锁定在：

- OS：`openEuler 22.03 (x86_64)`
- glibc：`2.34`
- Python：`3.12`
- torch：`2.11.0`
- torchvision：`0.26.0`
- 通道：`cu126`
- 推荐驱动：`560.35.03+`

关键提醒：

- GPU 能否最终跑通，取决于医院机器已有的 NVIDIA 驱动
- 所以最好同时产出：
  - `gpu-cu126` 包
  - `cpu` fallback 包

## 直接执行 checklist

1. 在 Ubuntu 上创建 `distrobox openEuler 22.03 x86_64`
2. 把项目放进 box
3. 在 box 内构建 `runtime/`（自带 Python 3.12）
4. 把所有 Python 依赖装进 `runtime/`
5. 修改 [server/deploy/scripts/start_server.sh](server/deploy/scripts/start_server.sh)
   - 不再依赖目标机 `python`
   - 改为运行 `runtime/bin/python` 或等价解释器
6. 修改 [server/deploy/scripts/install_offline.sh](server/deploy/scripts/install_offline.sh)
   - 不再创建 venv
   - 改成“解包 runtime / 修复路径 / 初始化目录”
   - 如果用了 `conda-pack`，这里应执行 `conda-unpack` 或等价步骤
7. 保留并继续使用：
   - `package_offline_bundle.sh`
   - `healthcheck.sh`
   - `smoke_test_upload.sh`
8. 在 box 内生成最终交付目录
9. 在 box 内做完整验收：
   - 启动服务
   - `/health`
   - 样例视频上传
   - 检查 DB / PDF / eye_video / ZIP
10. 额外产出 CPU fallback 包

## 可直接复用的资产

- 样例视频：`test/249.mp4`
- 参考 bundle：`dist/offline-bundle-local/`

注意：

- `dist/offline-bundle-local/` 只是结构参考
- 不能直接作为医院最终交付物

## 一句话交接

下一位 agent 的任务不是“继续补 wheelhouse”，而是：

在 `Ubuntu + distrobox(openEuler 22.03)` 里，把当前 `server/deploy/` 升级成“自带 Python runtime 的最终医院离线运行包”。 
