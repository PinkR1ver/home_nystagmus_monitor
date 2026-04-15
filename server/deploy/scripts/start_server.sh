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

HOST="${HNM_HOST:-0.0.0.0}"
PORT="${HNM_PORT:-8787}"
WORKERS="${HNM_WORKERS:-1}"
VENV_DIR="${HNM_VENV_DIR:-$SERVER_DIR/.venv-hospital}"
LOG_DIR="${HNM_LOG_DIR:-$SERVER_DIR/logs}"
RUN_DIR="${HNM_RUN_DIR:-$SERVER_DIR/run}"

mkdir -p "$LOG_DIR" "$RUN_DIR"

LOG_FILE="$LOG_DIR/hnm-server.log"
PID_FILE="$RUN_DIR/hnm-server.pid"

if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  echo "Server already running with PID $(cat "$PID_FILE")"
  exit 0
fi

cd "$SERVER_DIR"
nohup "$VENV_DIR/bin/uvicorn" main:app --host "$HOST" --port "$PORT" --workers "$WORKERS" >>"$LOG_FILE" 2>&1 &
echo $! > "$PID_FILE"

echo "Server started. PID=$(cat "$PID_FILE") LOG=$LOG_FILE"
