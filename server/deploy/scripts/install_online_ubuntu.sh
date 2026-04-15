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

PROFILE="${HNM_DEPLOY_PROFILE:-gpu-cu126}"
PYTHON_BIN="${PYTHON_BIN:-python3.12}"
VENV_DIR="${HNM_VENV_DIR:-$SERVER_DIR/.venv-aliyun}"

COMMON_REQ="$DEPLOY_DIR/requirements/runtime-common.lock.txt"
case "$PROFILE" in
  gpu-cu126)
    PROFILE_REQ="$DEPLOY_DIR/requirements/runtime-gpu-cu126.lock.txt"
    ;;
  cpu)
    PROFILE_REQ="$DEPLOY_DIR/requirements/runtime-cpu.lock.txt"
    ;;
  *)
    echo "Unsupported HNM_DEPLOY_PROFILE: $PROFILE" >&2
    exit 1
    ;;
esac

if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  echo "Python not found: $PYTHON_BIN" >&2
  echo "Ubuntu 24.04 usually provides python3.12; please install python3.12 and python3.12-venv first." >&2
  exit 1
fi

"$PYTHON_BIN" -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"

python -m pip install --upgrade pip setuptools wheel

PIP_ARGS=()
if [ -n "${PIP_INDEX_URL:-}" ]; then
  PIP_ARGS+=(--index-url "$PIP_INDEX_URL")
fi
if [ -n "${PIP_TRUSTED_HOST:-}" ]; then
  PIP_ARGS+=(--trusted-host "$PIP_TRUSTED_HOST")
fi

pip install "${PIP_ARGS[@]}" -r "$COMMON_REQ"

if [ -n "${TORCH_WHEELHOUSE:-}" ] && [ -d "${TORCH_WHEELHOUSE:-}" ]; then
  pip install --no-index --find-links "$TORCH_WHEELHOUSE" -r "$PROFILE_REQ"
elif [ -n "${TORCH_INDEX_URL:-}" ]; then
  pip install --index-url "$TORCH_INDEX_URL" -r "$PROFILE_REQ"
else
  pip install "${PIP_ARGS[@]}" -r "$PROFILE_REQ"
fi

mkdir -p "${HNM_DATA_DIR:-$SERVER_DIR/data}"
mkdir -p "${HNM_MODEL_DIR:-$SERVER_DIR/models}"
mkdir -p "${HNM_VOG_DIR:-$SERVER_DIR/vendor/SwinUNet-VOG}"
mkdir -p "${HNM_LOG_DIR:-$SERVER_DIR/logs}"
mkdir -p "${HNM_RUN_DIR:-$SERVER_DIR/run}"

echo "Online install complete."
echo "Venv: $VENV_DIR"
