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

SERVICE_NAME="${HNM_SERVICE_NAME:-hnm-server}"
APP_USER="${HNM_APP_USER:-hnm}"
SERVICE_TARGET="/etc/systemd/system/${SERVICE_NAME}.service"

tmp_file=$(mktemp)
cat > "$tmp_file" <<EOF
[Unit]
Description=Home Nystagmus Monitor Server
After=network.target

[Service]
Type=simple
User=${APP_USER}
Group=${APP_USER}
WorkingDirectory=${SERVER_DIR}
EnvironmentFile=${ENV_FILE}
ExecStart=${SERVER_DIR}/deploy/scripts/run_server_foreground.sh
Restart=on-failure
RestartSec=5
KillMode=process

[Install]
WantedBy=multi-user.target
EOF

sudo cp "$tmp_file" "$SERVICE_TARGET"
rm -f "$tmp_file"

sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME"

echo "Installed systemd service: $SERVICE_TARGET"
echo "Next: sudo systemctl start $SERVICE_NAME"
