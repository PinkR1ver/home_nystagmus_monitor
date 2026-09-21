"""Run as motionlab via sudo. Tokens are shown once; database stores only SHA-256."""
import argparse
import hashlib
import secrets
import uuid
from app import db
p=argparse.ArgumentParser()
p.add_argument('label')
p.add_argument('--account-id',type=uuid.UUID)
p.add_argument('--output',help='Write credential JSON to a new mode-0600 file')
a=p.parse_args()
token=secrets.token_urlsafe(48)
account=a.account_id or uuid.uuid4()
with db() as c:
    c.execute('INSERT INTO accounts(id,label) VALUES(%s,%s) ON CONFLICT DO NOTHING',(account,a.label))
    c.execute('INSERT INTO api_tokens(token_hash,account_id,label) VALUES(%s,%s,%s)',(hashlib.sha256(token.encode()).hexdigest(),account,a.label))
import json,os
result=json.dumps({'accountId':str(account),'token':token},indent=2)
if a.output:
    fd=os.open(a.output,os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600)
    with os.fdopen(fd,'w') as f: f.write(result+'\n')
else:
    print(result)
