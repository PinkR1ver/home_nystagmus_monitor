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

HOST="${HNM_HOST:-0.0.0.0}"
PORT="${HNM_PORT:-8787}"
WORKERS="${HNM_WORKERS:-1}"
VENV_DIR="${HNM_VENV_DIR:-$SERVER_DIR/.venv-aliyun}"

cd "$SERVER_DIR"
exec "$VENV_DIR/bin/uvicorn" main:app --host "$HOST" --port "$PORT" --workers "$WORKERS"
