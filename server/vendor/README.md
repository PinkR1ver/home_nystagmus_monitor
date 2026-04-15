# Vendor Runtime Files

当前仓库已内置 `SwinUNet-VOG` 的最小运行子集到：

- `server/vendor/SwinUNet-VOG/`

当前包含：

- `vertiwisdom.py`
- `preprocessing.py`
- `model.py`
- `nystagmus.py`
- `geometric_normalization.py`

说明：

- 目录内应直接包含 `vertiwisdom.py`
- 模型权重请放到 `server/models/`，或通过 `VOG_CHECKPOINT_PATH` / `HNM_MODEL_DIR` 指定
- 若后续算法工程不放在这里，可设置 `HNM_VOG_DIR`
- 如果 `vertiwisdom.py` 不在根目录，可额外设置 `HNM_VOG_MODULE_PATHS`
