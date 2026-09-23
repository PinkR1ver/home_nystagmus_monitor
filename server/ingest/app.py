"""Account-scoped collection ingestion. Does not run or fabricate analysis."""
import hashlib
import json
import os
import shutil
import uuid
from pathlib import Path
from typing import Literal

import psycopg
from psycopg.rows import dict_row
from psycopg.types.json import Jsonb
from fastapi import FastAPI, Depends, Header, HTTPException, Query, Request
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field, ConfigDict

DSN = os.getenv('DATABASE_URL', 'dbname=motion_lab user=motionlab host=/var/run/postgresql')
ROOT = Path(os.getenv('DATA_DIR', '/var/lib/motion-lab'))
MAX_FILE = 300 * 1024 * 1024
NAMES = {'video.mp4', 'landmarks.json', 'test_context.json', 'eye_signals.csv', 'imu.csv', 'report.zip', 'imu.zip'}
app = FastAPI(title='Motion Lab Collection API', version='1.0.0', docs_url=None, redoc_url=None, openapi_url=None)

def db():
    return psycopg.connect(DSN, row_factory=dict_row)

def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode()).hexdigest()

def auth(authorization: str = Header(default='')):
    if not authorization.startswith('Bearer ') or len(authorization)>256:
        raise HTTPException(401, 'Bearer token required')
    token_hash = hashlib.sha256(authorization[7:].encode()).hexdigest()
    with db() as c:
        row = c.execute('SELECT account_id FROM api_tokens WHERE token_hash=%s AND revoked_at IS NULL', (token_hash,)).fetchone()
    if not row:
        raise HTTPException(401, 'Invalid or revoked token')
    return row['account_id']

def lock(c):
    # Serialize short mutation transactions so revision cursors cannot skip late commits.
    c.execute('SELECT pg_advisory_xact_lock(817260921)')

def record(c, account, rid, writable=False):
    r = c.execute('SELECT * FROM records WHERE account_id=%s AND record_id=%s', (account,rid)).fetchone()
    if not r:
        raise HTTPException(404, 'Record not found')
    if writable and r['status'] == 'archived':
        raise HTTPException(409, 'Record archived')
    return r

def touch(c, account, rid):
    c.execute("UPDATE records SET revision=nextval('change_revision'),updated_at=now() WHERE account_id=%s AND record_id=%s", (account,rid))

class RecordInput(BaseModel):
    model_config = ConfigDict(extra='forbid')
    schemaVersion: Literal[1] = 1
    taskType: Literal['eye','standing','gait','sts','imu','befast']
    startedAt: str = Field(min_length=10,max_length=64)
    durationSec: float = Field(ge=0,le=86400,allow_inf_nan=False)
    device: dict = Field(default_factory=dict)
    context: dict = Field(default_factory=dict)
    subjectId: str | None = Field(default=None,max_length=128)

class ReportInput(BaseModel):
    model_config = ConfigDict(extra='forbid')
    version: str = Field(min_length=1,max_length=100)
    outcome: Literal['analyzed','unable_to_analyze']
    payload: dict

class CommitInput(BaseModel):
    model_config = ConfigDict(extra='forbid')
    artifacts: dict[str,str] = Field(min_length=1,max_length=10)
    reportVersion: str | None = Field(default=None,max_length=100)

@app.middleware('http')
async def limits(request: Request, call_next):
    from fastapi.responses import JSONResponse
    limit = MAX_FILE if '/artifacts/' in request.url.path else 8*1024*1024
    try:
        length = int(request.headers.get('content-length','0'))
    except ValueError:
        return JSONResponse({'detail':'Invalid content length'},400)
    if length<0 or length>limit:
        return JSONResponse({'detail':'Request too large'},413)
    if request.method in ('POST','PUT') and '/artifacts/' not in request.url.path:
        body=bytearray()
        async for chunk in request.stream():
            body.extend(chunk)
            if len(body)>limit:
                return JSONResponse({'detail':'Request too large'},413)
        request._body=bytes(body)
    return await call_next(request)

@app.get('/health')
def health():
    with db() as c:
        c.execute('SELECT 1')
    return {'status':'ok','service':'motion-lab-ingest','schemaVersion':1}

@app.get('/v1/me')
def me(account=Depends(auth)):
    return {'accountId':str(account)}

@app.get('/v1/schema')
def schema(account=Depends(auth)):
    return app.openapi()

@app.put('/v1/records/{rid}')
def create_record(rid: str, body: RecordInput, account=Depends(auth)):
    import re
    if not re.fullmatch(r'[A-Za-z0-9_-]{1,128}',rid):
        raise HTTPException(422,'Invalid record ID')
    from datetime import datetime
    try:
        date=datetime.fromisoformat(body.startedAt.replace('Z','+00:00'))
        if date.tzinfo is None: raise ValueError()
    except ValueError:
        raise HTTPException(422,'startedAt requires ISO 8601 with timezone')
    data=body.model_dump(); h=digest(data)
    with db() as c:
        lock(c)
        old=c.execute('SELECT metadata_hash FROM records WHERE account_id=%s AND record_id=%s',(account,rid)).fetchone()
        if old and old['metadata_hash']!=h: raise HTTPException(409,'Record ID has different metadata')
        if not old:
            c.execute('INSERT INTO records(account_id,record_id,task_type,metadata,metadata_hash) VALUES(%s,%s,%s,%s,%s)',(account,rid,body.taskType,Jsonb(data),h))
        return record(c,account,rid)

@app.get('/v1/records')
def list_records(after: int=Query(0,ge=0), limit: int=Query(100,ge=1,le=200), includeArchived: bool=False, account=Depends(auth)):
    with db() as c:
        # Include tombstones in cursor advancement even when hidden from display.
        rows=c.execute('SELECT * FROM records WHERE account_id=%s AND revision>%s ORDER BY revision LIMIT %s',(account,after,limit)).fetchall()
    return {'records':[r for r in rows if includeArchived or r['status']!='archived'],
            'archivedRecordIds':[r['record_id'] for r in rows if r['status']=='archived'],
            'nextCursor':rows[-1]['revision'] if rows else after,'hasMore':len(rows)==limit}

@app.get('/v1/records/{rid}')
def get_record(rid: str, account=Depends(auth)):
    with db() as c:
        r=record(c,account,rid)
        r['artifacts']=c.execute('SELECT name,sha256,byte_size,content_type,deleted_at FROM artifacts WHERE account_id=%s AND record_id=%s',(account,rid)).fetchall()
        r['reports']=c.execute('SELECT origin,version,outcome,payload,created_at FROM reports WHERE account_id=%s AND record_id=%s ORDER BY created_at',(account,rid)).fetchall()
        return r

@app.put('/v1/records/{rid}/artifacts/{name}')
async def upload(rid: str, name: str, request: Request, x_content_sha256: str=Header(), account=Depends(auth)):
    import re
    if name not in NAMES or not re.fullmatch('[0-9a-f]{64}',x_content_sha256):
        raise HTTPException(422,'Unsupported artifact name or SHA-256')
    with db() as c:
        r=record(c,account,rid,True)
        if r['task_type']=='befast': raise HTTPException(422,'BEFAST accepts feature reports only; raw artifacts are not allowed')
        if r['status']=='complete':
            existing=c.execute('SELECT sha256 FROM artifacts WHERE account_id=%s AND record_id=%s AND name=%s',(account,rid,name)).fetchone()
            if existing and existing['sha256']==x_content_sha256: return {'sha256':x_content_sha256,'duplicate':True}
            raise HTTPException(409,'Completed record is immutable')
    if shutil.disk_usage(ROOT).free<MAX_FILE+2*1024**3: raise HTTPException(507,'Storage reserve reached')
    folder=ROOT/'objects'/str(account)
    folder.mkdir(parents=True,exist_ok=True)
    path=folder/str(uuid.uuid4()); h=hashlib.sha256(); total=0; committed=False
    try:
        with path.open('xb') as f:
            async for chunk in request.stream():
                total+=len(chunk)
                if total>MAX_FILE: raise HTTPException(413,'Artifact exceeds 300 MiB')
                h.update(chunk); f.write(chunk)
            f.flush(); os.fsync(f.fileno())
        if total==0 or h.hexdigest()!=x_content_sha256: raise HTTPException(422,'Empty file or SHA-256 mismatch')
        with db() as c:
            lock(c); r=record(c,account,rid,True)
            old=c.execute('SELECT sha256 FROM artifacts WHERE account_id=%s AND record_id=%s AND name=%s',(account,rid,name)).fetchone()
            if old:
                if old['sha256']!=x_content_sha256: raise HTTPException(409,'Artifact already has different content')
                return {'sha256':x_content_sha256,'duplicate':True}
            if r['status']=='complete': raise HTTPException(409,'Completed record is immutable')
            c.execute('INSERT INTO artifacts(account_id,record_id,name,sha256,byte_size,content_type,storage_key) VALUES(%s,%s,%s,%s,%s,%s,%s)',
                      (account,rid,name,h.hexdigest(),total,'application/octet-stream',str(path.relative_to(ROOT))))
            touch(c,account,rid)
        committed=True
        return {'sha256':h.hexdigest(),'bytes':total,'duplicate':False}
    finally:
        if not committed: path.unlink(missing_ok=True)

@app.get('/v1/records/{rid}/artifacts/{name}')
def download(rid: str,name: str,account=Depends(auth)):
    with db() as c:
        r=record(c,account,rid)
        if r['status']=='archived': raise HTTPException(410,'Record archived')
        row=c.execute('SELECT * FROM artifacts WHERE account_id=%s AND record_id=%s AND name=%s AND deleted_at IS NULL',(account,rid,name)).fetchone()
    if not row: raise HTTPException(404,'Artifact not found')
    return FileResponse(ROOT/row['storage_key'],media_type='application/octet-stream',filename=name,headers={'X-Content-SHA256':row['sha256'],'Cache-Control':'no-store'})

@app.put('/v1/records/{rid}/client-report')
def report(rid: str,body: ReportInput,account=Depends(auth)):
    h=digest(body.model_dump())
    with db() as c:
        lock(c); r=record(c,account,rid,True)
        old=c.execute("SELECT payload_hash FROM reports WHERE account_id=%s AND record_id=%s AND origin='client' AND version=%s",(account,rid,body.version)).fetchone()
        if old and old['payload_hash']!=h: raise HTTPException(409,'Report version conflict')
        if not old:
            if r['status']=='complete': raise HTTPException(409,'Completed record is immutable')
            c.execute("INSERT INTO reports(account_id,record_id,origin,version,outcome,payload,payload_hash) VALUES(%s,%s,'client',%s,%s,%s,%s)",(account,rid,body.version,body.outcome,Jsonb(body.payload),h))
            touch(c,account,rid)
    return {'origin':'client','version':body.version,'outcome':body.outcome}

@app.post('/v1/records/{rid}/complete')
def complete(rid: str,body: CommitInput,account=Depends(auth)):
    with db() as c:
        lock(c); r=record(c,account,rid,True)
        rows=c.execute('SELECT name,sha256 FROM artifacts WHERE account_id=%s AND record_id=%s AND deleted_at IS NULL',(account,rid)).fetchall()
        actual={a['name']:a['sha256'] for a in rows}
        if body.artifacts!=actual: raise HTTPException(409,'Artifact manifest does not match uploaded files')
        required={'imu.csv','imu.zip'} if r['task_type']=='imu' else {'video.mp4'}
        if r['task_type']=='befast':
            if actual: raise HTTPException(409,'BEFAST must not contain raw artifacts')
            if not body.reportVersion: raise HTTPException(409,'BEFAST feature report required')
        elif not required.intersection(actual): raise HTTPException(409,'Required raw capture missing')
        if body.reportVersion and not c.execute("SELECT 1 FROM reports WHERE account_id=%s AND record_id=%s AND origin='client' AND version=%s",(account,rid,body.reportVersion)).fetchone():
            raise HTTPException(409,'Report missing')
        if r['status']!='complete':
            c.execute("UPDATE records SET status='complete' WHERE account_id=%s AND record_id=%s",(account,rid)); touch(c,account,rid)
        return record(c,account,rid)

@app.post('/v1/records/{rid}/archive')
def archive(rid: str,account=Depends(auth)):
    with db() as c:
        lock(c); r=record(c,account,rid)
        if r['status']!='archived':
            c.execute("UPDATE records SET status='archived' WHERE account_id=%s AND record_id=%s",(account,rid)); touch(c,account,rid)
    # Logical archive first; interrupted cleanup can be retried safely.
    with db() as c:
        lock(c)
        rows=c.execute("SELECT storage_key FROM artifacts WHERE account_id=%s AND record_id=%s AND name='video.mp4' AND deleted_at IS NULL",(account,rid)).fetchall()
        for row in rows: (ROOT/row['storage_key']).unlink(missing_ok=True)
        c.execute("UPDATE artifacts SET deleted_at=now() WHERE account_id=%s AND record_id=%s AND name='video.mp4' AND deleted_at IS NULL",(account,rid))
    return {'recordId':rid,'status':'archived'}
