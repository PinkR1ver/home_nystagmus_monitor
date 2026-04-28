# 模型权重打包：`safetensors + config.json`

## 背景
- `safetensors` 只存张量（权重/缓冲区），不包含模型结构。
- 本项目 `server/models/checkpoint_best.pth` 是训练 checkpoint，包含 `model_state_dict` 以及 optimizer/scheduler 等训练态字段。

## 当前约定（v1）
- 权重导出：`server/models/checkpoint_best.safetensors`
  - 来自 `checkpoint_best.pth` 的 `model_state_dict`
- 架构配置：`server/models/config.json`
  - 固化 `GazeSwinUNet` 的关键构造参数（与 `server/vendor/SwinUNet-VOG/vertiwisdom.py:load_gaze_model()` 一致）
- 转换脚本：`tmp/convert_checkpoint_best_to_safetensors.py`（目录已 gitignore）
  - 保存后会做 key 集合与 shape/dtype 的快速校验
- 服务端加载：`server/main.py` 在 `HNM_MODEL_DIR` 下优先匹配 `*.safetensors`，再回退 `*.pth`；`vertiwisdom.load_gaze_model()` 同时支持两种后缀。

## 注意
- 如果未来改动 `GazeSwinUNet(...)` 的构造参数，需要同步更新 `config.json`，否则会出现权重无法加载或行为不一致。

