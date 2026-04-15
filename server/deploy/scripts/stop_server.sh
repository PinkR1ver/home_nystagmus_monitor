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

RUN_DIR="${HNM_RUN_DIR:-$SERVER_DIR/run}"
PID_FILE="$RUN_DIR/hnm-server.pid"

if [ ! -f "$PID_FILE" ]; then
  echo "No PID file found."
  exit 0
fi

PID=$(cat "$PID_FILE")
if kill -0 "$PID" 2>/dev/null; then
  kill "$PID"
  echo "Stopped PID $PID"
else
  echo "Process $PID is not running."
fi

rm -f "$PID_FILE"
