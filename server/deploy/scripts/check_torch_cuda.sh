#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
DEPLOY_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
SERVER_DIR=$(cd -- "$DEPLOY_DIR/.." && pwd)

ENV_FILE="${ENV_FILE:-$DEPLOY_DIR/aliyun-ubuntu24/env/hnm-server.aliyun.env}"
if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

VENV_DIR="${HNM_VENV_DIR:-$SERVER_DIR/.venv-aliyun}"

"$VENV_DIR/bin/python" - <<'PY'
import json
import torch

payload = {
    "torch_version": torch.__version__,
    "torch_cuda_version": getattr(torch.version, "cuda", None),
    "cuda_available": torch.cuda.is_available(),
    "device_count": torch.cuda.device_count(),
    "device_names": [torch.cuda.get_device_name(i) for i in range(torch.cuda.device_count())] if torch.cuda.is_available() else [],
}
print(json.dumps(payload, ensure_ascii=False, indent=2))
PY
