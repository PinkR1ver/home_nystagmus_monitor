"""Deployed API contract tests using explicitly synthetic data and temporary accounts."""
import hashlib, json, secrets, unittest, uuid
import httpx
from app import db

class IngestionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.accounts=[]; cls.clients=[]
        for i in range(2):
            aid=uuid.uuid4(); token=secrets.token_urlsafe(48)
            with db() as c:
                c.execute('INSERT INTO accounts(id,label) VALUES(%s,%s)',(aid,'synthetic-api-test'))
                c.execute('INSERT INTO api_tokens(token_hash,account_id,label) VALUES(%s,%s,%s)',(hashlib.sha256(token.encode()).hexdigest(),aid,'test'))
            cls.accounts.append(aid)
            cls.clients.append(httpx.Client(base_url='http://127.0.0.1:8789',headers={'Authorization':'Bearer '+token}))
    @classmethod
    def tearDownClass(cls):
        from app import ROOT
        for client in cls.clients: client.close()
        for aid in cls.accounts:
            with db() as c:
                rows=c.execute('SELECT storage_key FROM artifacts WHERE account_id=%s',(aid,)).fetchall()
                for row in rows: (ROOT/row['storage_key']).unlink(missing_ok=True)
                for table in ['reports','artifacts','records','api_tokens']:
                    c.execute(f'DELETE FROM {table} WHERE account_id=%s',(aid,))
                c.execute('DELETE FROM accounts WHERE id=%s',(aid,))
    def test_contract(self):
        a,b=self.clients; url='/v1/records/synthetic-contract'
        meta={'taskType':'eye','startedAt':'2026-09-21T00:00:00Z','durationSec':4,'context':{'synthetic':True}}
        self.assertEqual(httpx.get('http://127.0.0.1:8789/v1/records').status_code,401)
        self.assertEqual(a.put(url,json=meta).status_code,200)
        first=a.get(url).json()['revision']
        self.assertEqual(a.put(url,json=meta).json()['revision'],first)
        self.assertEqual(a.put(url,json={**meta,'durationSec':5}).status_code,409)
        self.assertEqual(b.get(url).status_code,404)
        self.assertEqual(b.get(url+'/artifacts/video.mp4').status_code,404)
        content=b'synthetic bytes, not a patient video'; h=hashlib.sha256(content).hexdigest()
        self.assertEqual(a.put(url+'/artifacts/video.mp4',content=content,headers={'X-Content-SHA256':'0'*64}).status_code,422)
        self.assertEqual(a.get(url).json()['artifacts'],[])
        self.assertEqual(a.put(url+'/artifacts/video.mp4',content=content,headers={'X-Content-SHA256':h}).status_code,200)
        self.assertTrue(a.put(url+'/artifacts/video.mp4',content=content,headers={'X-Content-SHA256':h}).json()['duplicate'])
        other=b'other'
        self.assertEqual(a.put(url+'/artifacts/video.mp4',content=other,headers={'X-Content-SHA256':hashlib.sha256(other).hexdigest()}).status_code,409)
        self.assertEqual(a.get(url+'/artifacts/video.mp4').content,content)
        report={'version':'test-v1','outcome':'unable_to_analyze','payload':{'unavailableReason':'synthetic test input','samples':[]}}
        self.assertEqual(a.put(url+'/client-report',json=report).status_code,200)
        self.assertEqual(a.put(url+'/client-report',json=report).status_code,200)
        self.assertEqual(a.put(url+'/client-report',json={**report,'outcome':'analyzed'}).status_code,409)
        commit={'artifacts':{'video.mp4':h},'reportVersion':'test-v1'}
        self.assertEqual(a.post(url+'/complete',json={**commit,'artifacts':{'video.mp4':'bad'}}).status_code,409)
        done=a.post(url+'/complete',json=commit)
        self.assertEqual(done.status_code,200); self.assertEqual(done.json()['status'],'complete')
        self.assertEqual(a.post(url+'/complete',json=commit).json()['revision'],done.json()['revision'])
        self.assertEqual(a.get(url).json()['reports'][0]['origin'],'client')
        cursor=a.get('/v1/records').json()['nextCursor']
        self.assertEqual(a.get('/v1/records',params={'after':cursor}).json()['records'],[])
        self.assertEqual(b.get('/v1/records').json()['records'],[])
        self.assertEqual(a.put(url+'/client-report',json={**report,'version':'new'}).status_code,409)
        self.assertEqual(a.post(url+'/archive').status_code,200)
        sync=a.get('/v1/records',params={'after':cursor}).json()
        self.assertEqual(sync['archivedRecordIds'],['synthetic-contract'])
        self.assertEqual(sync['records'],[])
        self.assertEqual(a.get(url+'/artifacts/video.mp4').status_code,410)
        self.assertIsNotNone(a.get(url).json()['artifacts'][0]['deleted_at'])
        self.assertEqual(a.put(url+'/client-report',json=report).status_code,409)
        self.assertEqual(a.post(url+'/archive').status_code,200)
    def test_befast_features_without_raw_media(self):
        a,b=self.clients; url='/v1/records/synthetic-befast'
        meta={'taskType':'befast','startedAt':'2026-09-23T00:00:00Z','durationSec':0,'context':{'synthetic':True,'sourceSessionId':'synthetic-befast'}}
        self.assertEqual(a.put(url,json=meta).status_code,200)
        self.assertEqual(a.post(url+'/complete',json={'artifacts':{}}).status_code,409)
        raw=b'forbidden raw media'
        self.assertEqual(a.put(url+'/artifacts/video.mp4',content=raw,headers={'X-Content-SHA256':hashlib.sha256(raw).hexdigest()}).status_code,422)
        report={'version':'befast-features-v1','outcome':'analyzed','payload':{'schemaVersion':1,'modules':[],'headache':{'answer':'UNABLE_TO_ANSWER','nrs':None}}}
        self.assertEqual(a.put(url+'/client-report',json=report).status_code,200)
        commit={'artifacts':{},'reportVersion':'befast-features-v1'}
        done=a.post(url+'/complete',json=commit)
        self.assertEqual(done.status_code,200)
        self.assertEqual(a.post(url+'/complete',json=commit).json()['revision'],done.json()['revision'])
        detail=a.get(url).json()
        self.assertEqual(detail['artifacts'],[])
        self.assertIsNone(detail['reports'][0]['payload']['headache']['nrs'])
        self.assertEqual(b.get(url).status_code,404)
        self.assertEqual(a.post(url+'/archive').status_code,200)
        self.assertEqual(a.get(url).json()['status'],'archived')

    def test_raw_only_imu_and_validation(self):
        a=self.clients[0]; url='/v1/records/synthetic-imu'
        meta={'taskType':'imu','startedAt':'2026-09-21T00:00:00Z','durationSec':2}
        self.assertEqual(a.put(url,json={**meta,'startedAt':'2026-09-21'}).status_code,422)
        self.assertEqual(a.put(url,json={**meta,'accountId':str(self.accounts[1])}).status_code,422)
        self.assertEqual(a.put(url,json=meta).status_code,200)
        raw=b'time_ms,ax,ay,az\n0,0,0,0\n'; h=hashlib.sha256(raw).hexdigest()
        self.assertEqual(a.put(url+'/artifacts/imu.csv',content=raw,headers={'X-Content-SHA256':h}).status_code,200)
        self.assertEqual(a.post(url+'/complete',json={'artifacts':{'imu.csv':h}}).status_code,200)
        self.assertEqual(a.get(url).json()['reports'],[])
        self.assertEqual(a.put(url+'/artifacts/evil.exe',content=raw,headers={'X-Content-SHA256':h}).status_code,422)

if __name__=='__main__': unittest.main(verbosity=2)
