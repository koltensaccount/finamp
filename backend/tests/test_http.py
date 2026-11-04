import json,os,sys,tempfile,threading,unittest,urllib.request,urllib.error
from pathlib import Path
from http.server import HTTPServer
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from catalog import Catalog
from server import Handler
from test_catalog import release,item,evidence
class HTTPTests(unittest.TestCase):
 def test_search_request_and_import_slice(self):
  with tempfile.TemporaryDirectory() as tmp:
   path=str(Path(tmp)/'catalog.sqlite');c=Catalog(path);c.release(release());c.db.commit();c.db.close()
   old=os.environ.get('CATALOG_API_TOKEN');os.environ['CATALOG_API_TOKEN']='controlled-test-only'
   s=HTTPServer(('127.0.0.1',0),Handler);s.database=path;t=threading.Thread(target=s.serve_forever,daemon=True);t.start()
   def call(route,body=None,auth=True):
    headers={'Authorization':'Bearer controlled-test-only'} if auth else {}
    req=urllib.request.Request('http://127.0.0.1:'+str(s.server_port)+route,data=json.dumps(body).encode() if body is not None else None,headers=headers)
    with urllib.request.urlopen(req) as response:return json.load(response)
   try:
    with self.assertRaises(urllib.error.HTTPError) as exc:call('/v1/search?q=Song',auth=False)
    self.assertEqual(exc.exception.code,401)
    self.assertEqual(call('/v1/search?q=Song')['results'][0]['availability']['state'],'not_found')
    request=call('/v1/requests',{'release_id':'edition','scope':'album'});self.assertFalse(request['dispatch_enabled'])
    self.assertEqual(call('/v1/requests/'+str(request['id']))['state'],'queued')
    c=Catalog(path);c.sync([item()],evidence());c.db.close()
    self.assertEqual(call('/v1/recordings/recording/availability')['playable_item_id'],'local')
    self.assertEqual(call('/v1/requests/'+str(request['id']))['state'],'available')
   finally:
    s.shutdown();s.server_close();t.join()
    if old is None:os.environ.pop('CATALOG_API_TOKEN',None)
    else:os.environ['CATALOG_API_TOKEN']=old
