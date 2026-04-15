#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
DEPLOY_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
SERVER_DIR=$(cd -- "$DEPLOY_DIR/.." && pwd)
PROJECT_ROOT=$(cd -- "$SERVER_DIR/.." && pwd)

BUNDLE_DIR="${1:-$PROJECT_ROOT/dist/offline-bundle}"
WHEELHOUSE_DIR="${WHEELHOUSE_DIR:-$PROJECT_ROOT/dist/wheelhouse}"
VOG_SOURCE_DIR="${VOG_SOURCE_DIR:-$SERVER_DIR/vendor/SwinUNet-VOG}"
MODEL_SOURCE_DIR="${MODEL_SOURCE_DIR:-$SERVER_DIR/models}"
SAMPLE_VIDEO="${SAMPLE_VIDEO:-$PROJECT_ROOT/test/249.mp4}"

rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR"

python3 - "$SERVER_DIR" "$BUNDLE_DIR/server" <<'PY'
from pathlib import Path
import shutil
import sys

src = Path(sys.argv[1])
dst = Path(sys.argv[2])

ignore = shutil.ignore_patterns(
    ".venv",
    "__pycache__",
    "data",
    "*.pyc",
    "*.pyo",
    ".DS_Store",
    "skills-lock.json",
    "torchinductor_*",
)
shutil.copytree(src, dst, dirs_exist_ok=True, ignore=ignore)
PY

if [ -d "$WHEELHOUSE_DIR" ]; then
  cp -R "$WHEELHOUSE_DIR" "$BUNDLE_DIR/wheelhouse"
fi

if [ -d "$VOG_SOURCE_DIR" ]; then
  mkdir -p "$BUNDLE_DIR/server/vendor"
  cp -R "$VOG_SOURCE_DIR" "$BUNDLE_DIR/server/vendor/SwinUNet-VOG"
fi

if [ -d "$MODEL_SOURCE_DIR" ]; then
  mkdir -p "$BUNDLE_DIR/server/models"
  cp -R "$MODEL_SOURCE_DIR"/. "$BUNDLE_DIR/server/models/" 2>/dev/null || true
fi

if [ -f "$SAMPLE_VIDEO" ]; then
  mkdir -p "$BUNDLE_DIR/samples"
  cp "$SAMPLE_VIDEO" "$BUNDLE_DIR/samples/$(basename "$SAMPLE_VIDEO")"
fi

echo "Offline bundle ready: $BUNDLE_DIR"
