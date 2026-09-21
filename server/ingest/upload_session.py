"""Upload an exported Android session folder. Standard library, verified HTTPS only."""
import argparse, hashlib, json, os, urllib.request, urllib.error
from pathlib import Path
from datetime import datetime, timezone
p=argparse.ArgumentParser()
p.add_argument('folder',type=Path)
p.add_argument('--task',choices=['eye','standing','gait','sts','imu'],required=True)
p.add_argument('--duration',type=float,required=True)
p.add_argument('--url',default='https://39.107.192.82')
p.add_argument('--credential-file',type=Path,required=True)
p.add_argument('--report-version',default='android-0.4.0-eye-v1')
a=p.parse_args()
if not a.url.startswith('https://'): p.error('HTTPS required')
cred=json.loads(a.credential_file.read_text())
rid=a.folder.name
base=a.url.rstrip('/')+'/v1/records/'+rid

def send(url,method='GET',data=None,headers=None):
    req=urllib.request.Request(url,data=data,method=method,headers={'Authorization':'Bearer '+cred['token'],**(headers or {})})
    with urllib.request.urlopen(req,timeout=300) as response: return json.load(response)

def js(url,method,data):
    return send(url,method,json.dumps(data,ensure_ascii=False).encode(),{'Content-Type':'application/json'})

ctx=a.folder/'test_context.json'
metadata={'schemaVersion':1,'taskType':a.task,'startedAt':datetime.fromtimestamp(int(rid.split('-')[0])/1000,timezone.utc).isoformat(),'durationSec':a.duration,'context':json.loads(ctx.read_text()) if ctx.exists() else {},'device':{'platform':'android'}}
js(base,'PUT',metadata)
manifest={}
for name in ['video.mp4','landmarks.json','test_context.json','eye_signals.csv','imu.csv','report.zip','imu.zip']:
    file=a.folder/name
    if not file.is_file(): continue
    with file.open('rb') as f: h=hashlib.file_digest(f,'sha256').hexdigest()
    with file.open('rb') as stream:
        send(base+'/artifacts/'+name,'PUT',stream,{'Content-Type':'application/octet-stream','Content-Length':str(file.stat().st_size),'X-Content-SHA256':h})
    manifest[name]=h
report=a.folder/('eye_report.json' if a.task=='eye' else 'report.json')
version=None
if report.exists():
    payload=json.loads(report.read_text())
    # Preserve app outcome; callers can upload unavailable reports without fabricating success.
    outcome='unable_to_analyze' if payload.get('unavailableReason') or payload.get('status') in ['UNAVAILABLE','FAILED','unable_to_analyze'] else 'analyzed'
    js(base+'/client-report','PUT',{'version':a.report_version,'outcome':outcome,'payload':payload})
    version=a.report_version
result=js(base+'/complete','POST',{'artifacts':manifest,'reportVersion':version})
print(json.dumps({'recordId':rid,'status':result['status'],'revision':result['revision']}))
