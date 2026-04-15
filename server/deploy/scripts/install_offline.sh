#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
DEPLOY_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
SERVER_DIR=$(cd -- "$DEPLOY_DIR/.." && pwd)

ENV_FILE="${ENV_FILE:-$DEPLOY_DIR/env/hnm-server.env}"
if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

PROFILE="${HNM_DEPLOY_PROFILE:-gpu-cu126}"
PYTHON_BIN="${PYTHON_BIN:-python3.12}"
VENV_DIR="${HNM_VENV_DIR:-$SERVER_DIR/.venv-hospital}"
WHEELHOUSE_DIR="${WHEELHOUSE_DIR:-$SERVER_DIR/../wheelhouse}"

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

"$PYTHON_BIN" -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"

pip install --no-index --find-links "$WHEELHOUSE_DIR" -r "$COMMON_REQ" -r "$PROFILE_REQ"

mkdir -p "${HNM_DATA_DIR:-$SERVER_DIR/data}"
mkdir -p "${HNM_MODEL_DIR:-$SERVER_DIR/models}"
mkdir -p "${HNM_VOG_DIR:-$SERVER_DIR/vendor/SwinUNet-VOG}"
mkdir -p "${HNM_LOG_DIR:-$SERVER_DIR/logs}"
mkdir -p "${HNM_RUN_DIR:-$SERVER_DIR/run}"

echo "Offline install complete."
echo "Venv: $VENV_DIR"
