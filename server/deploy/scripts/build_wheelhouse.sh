#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
DEPLOY_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
PROJECT_ROOT=$(cd -- "$DEPLOY_DIR/../.." && pwd)

PYTHON_BIN="${PYTHON_BIN:-python3.12}"
PROFILE="${PROFILE:-gpu-cu126}"
OUT_DIR="${1:-$PROJECT_ROOT/dist/wheelhouse}"

COMMON_REQ="$DEPLOY_DIR/requirements/runtime-common.lock.txt"

case "$PROFILE" in
  gpu-cu126)
    PROFILE_REQ="$DEPLOY_DIR/requirements/runtime-gpu-cu126.lock.txt"
    TORCH_INDEX_URL="https://download.pytorch.org/whl/cu126"
    ;;
  cpu)
    PROFILE_REQ="$DEPLOY_DIR/requirements/runtime-cpu.lock.txt"
    TORCH_INDEX_URL="https://download.pytorch.org/whl/cpu"
    ;;
  *)
    echo "Unsupported PROFILE: $PROFILE" >&2
    exit 1
    ;;
esac

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

"$PYTHON_BIN" -m pip download -r "$COMMON_REQ" --dest "$OUT_DIR"
"$PYTHON_BIN" -m pip download -r "$PROFILE_REQ" --dest "$OUT_DIR" --index-url "$TORCH_INDEX_URL"

echo "Wheelhouse ready: $OUT_DIR"
