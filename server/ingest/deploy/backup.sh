#!/bin/bash
set -euo pipefail
umask 077
backup_dir=/var/backups/motion-lab
mkdir -p "$backup_dir"
# Hold the mutation advisory lock for a coherent SQL + object snapshot.
/usr/bin/python3 /opt/motion-lab/backup.py
