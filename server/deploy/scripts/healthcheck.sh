#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
DEPLOY_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
SERVER_DIR=$(cd -- "$DEPLOY_DIR/.." && pwd)

ENV_FILE="${ENV_FILE:-$DEPLOY_DIR/env/hnm-server.env}"
if [ ! -f "$ENV_FILE" ] && [ -f "$DEPLOY_DIR/aliyun-ubuntu24/env/hnm-server.aliyun.env" ]; then
  ENV_FILE="$DEPLOY_DIR/aliyun-ubuntu24/env/hnm-server.aliyun.env"
fi
if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

HOST="${HNM_HEALTH_HOST:-127.0.0.1}"
PORT="${HNM_PORT:-8787}"

curl -fsS "http://$HOST:$PORT/health"
echo
