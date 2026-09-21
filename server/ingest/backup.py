import datetime, os, subprocess, tarfile
from pathlib import Path
from app import db, lock, ROOT
base=Path('/var/backups/motion-lab')
base.mkdir(exist_ok=True)
stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
out=base/stamp; out.mkdir(mode=0o700)
with db() as c:
    lock(c)
    subprocess.run(['pg_dump','-Fc','-f',str(out/'database.dump'),'motion_lab'],check=True)
    # Only committed live objects: unfinished uploads cannot enter this snapshot.
    keys=c.execute('SELECT storage_key FROM artifacts WHERE deleted_at IS NULL').fetchall()
    with tarfile.open(out/'objects.tar.gz','w:gz') as tar:
        for row in keys:
            path=ROOT/row['storage_key']
            if path.exists(): tar.add(path,arcname=row['storage_key'])
(out/'COMPLETE').touch()
print('Backup complete:',out.name)
# Retain 7 completed daily snapshots; never delete an unfinished backup automatically.
import shutil
completed=sorted(p for p in base.iterdir() if p.is_dir() and (p/'COMPLETE').exists())
for p in completed[:-7]: shutil.rmtree(p)
