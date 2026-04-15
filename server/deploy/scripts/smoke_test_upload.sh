#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
DEPLOY_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)

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
VIDEO_PATH="${1:-$DEPLOY_DIR/../../samples/249.mp4}"
RECORD_ID="smoke_$(date +%Y%m%dT%H%M%S)"

if [ ! -f "$VIDEO_PATH" ]; then
  echo "Sample video not found: $VIDEO_PATH" >&2
  exit 1
fi

curl -fsS -X POST "http://$HOST:$PORT/api/videos" \
  -F "accountId=hospital-smoke" \
  -F "recordId=$RECORD_ID" \
  -F "accountName=离线验收" \
  -F "patientId=patient-smoke" \
  -F "startedAt=2026-01-01 09:00:00" \
  -F "durationSec=10" \
  -F "inputMode=single_eye" \
  -F "video=@$VIDEO_PATH;type=video/mp4"
echo
