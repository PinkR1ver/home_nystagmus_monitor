#!/bin/bash
set -euo pipefail
if ! runuser -u postgres -- psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='motionlab'" | grep -q 1; then
 runuser -u postgres -- createuser motionlab
fi
if ! runuser -u postgres -- psql -tAc "SELECT 1 FROM pg_database WHERE datname='motion_lab'" | grep -q 1; then
 runuser -u postgres -- createdb -O motionlab motion_lab
fi
runuser -u motionlab -- psql -v ON_ERROR_STOP=1 -d motion_lab -f /opt/motion-lab/schema.sql
cp /opt/motion-lab/deploy/motion-lab*.service /opt/motion-lab/deploy/motion-lab*.timer /etc/systemd/system/
cp /opt/motion-lab/deploy/nginx.conf /etc/nginx/sites-available/motion-lab
ln -sf /etc/nginx/sites-available/motion-lab /etc/nginx/sites-enabled/motion-lab
nginx -t
systemctl daemon-reload
systemctl enable --now motion-lab.service motion-lab-backup.timer
systemctl reload nginx
