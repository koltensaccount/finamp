"""Loopback authenticated catalog API; no acquisition dispatch is enabled."""
import argparse,json,os,time,urllib.request,urllib.parse,urllib.error,threading
from http.server import BaseHTTPRequestHandler,HTTPServer
from catalog import Catalog,norm
LAST=0
def provider(c,q):
 global LAST
 for kind in ('artist','release-group','recording'):
  url='https://musicbrainz.org/ws/2/'+kind+'?'+urllib.parse.urlencode({'query':q,'limit':20,'fmt':'json'})
  row=c.db.execute('select * from http_cache where url=?',(url,)).fetchone()
  if row and (time.time()-row['fetched_at']<86400 or row['retry_at']>time.time()):continue
  time.sleep(max(0,1.1-(time.monotonic()-LAST)))
  try:
   req=urllib.request.Request(url,headers={'User-Agent':'PersonalMusicCatalog/0.1 (local self-hosted development)'})
   with urllib.request.urlopen(req,timeout=8) as response:raw=response.read().decode();data=json.loads(raw)
   LAST=time.monotonic()
   with c.db:
    c.db.execute('INSERT OR REPLACE INTO http_cache VALUES(?,?,?,?,?)',(url,200,raw,time.time(),0))
    if kind=='artist':
     for i,x in enumerate(data.get('artists',[])):
      c.db.execute('INSERT OR REPLACE INTO artists VALUES(?,?)',(x['id'],x['name']));c.db.execute('INSERT OR REPLACE INTO search_hits VALUES(?,?,?,?)',(norm(q),'artist',x['id'],i))
    elif kind=='release-group':
     for i,x in enumerate(data.get('release-groups',[])):
      c.db.execute('INSERT OR REPLACE INTO release_groups VALUES(?,?,?,?)',(x['id'],x['title'],x.get('primary-type'),x.get('first-release-date')));c.credits('group',x['id'],x.get('artist-credit'))
      c.db.execute('INSERT OR REPLACE INTO search_hits VALUES(?,?,?,?)',(norm(q),'album',x['id'],i))
    else:
     for i,x in enumerate(data.get('recordings',[])):
      c.db.execute('INSERT OR REPLACE INTO recordings VALUES(?,?,?)',(x['id'],x['title'],x.get('length')));c.credits('recording',x['id'],x.get('artist-credit'))
      c.db.execute('INSERT OR REPLACE INTO search_hits VALUES(?,?,?,?)',(norm(q),'track',x['id'],i))
  except Exception:
   LAST=time.monotonic()
   with c.db:
    if row:c.db.execute('UPDATE http_cache SET retry_at=? WHERE url=?',(time.time()+300,url))
    else:c.db.execute('INSERT INTO http_cache VALUES(?,?,?,?,?)',(url,0,'{}',0,time.time()+300))
def fetch_mb_release(c, release_id):
 global LAST
 url = f'https://musicbrainz.org/ws/2/release/{release_id}?inc=artist-credits+recordings+release-groups&fmt=json'
 row = c.db.execute('SELECT * FROM http_cache WHERE url=?', (url,)).fetchone()
 if row and row['status'] == 200:
  try:
   c.release(json.loads(row['payload']))
   return
  except Exception:
   pass
 time.sleep(max(0, 1.1 - (time.monotonic() - LAST)))
 try:
  req = urllib.request.Request(url, headers={'User-Agent': 'PersonalMusicCatalog/0.1 (local self-hosted development)'})
  with urllib.request.urlopen(req, timeout=10) as response:
   raw = response.read().decode(); data = json.loads(raw)
  LAST = time.monotonic()
  with c.db:
   c.db.execute('INSERT OR REPLACE INTO http_cache VALUES(?,?,?,?,?)', (url, 200, raw, time.time(), 0))
   c.release(data)
 except Exception:
  LAST = time.monotonic()
def fetch_mb_group(c, group_id):
 global LAST
 url = f'https://musicbrainz.org/ws/2/release-group/{group_id}?inc=artists+releases&fmt=json'
 row = c.db.execute('SELECT * FROM http_cache WHERE url=?', (url,)).fetchone()
 if row and row['status'] == 200:
  try:
   data = json.loads(row['payload'])
   gid = data.get('id')
   with c.db:
    c.db.execute('INSERT OR REPLACE INTO release_groups VALUES(?,?,?,?)', (gid, data.get('title'), data.get('primary-type'), data.get('first-release-date')))
    if data.get('artist-credit'): c.credits('group', gid, data['artist-credit'])
    for rel in data.get('releases', []):
     c.db.execute('INSERT OR REPLACE INTO releases VALUES(?,?,?)', (rel['id'], gid, rel.get('title')))
     if rel.get('artist-credit'): c.credits('release', rel['id'], rel['artist-credit'])
   return
  except Exception:
   pass
 time.sleep(max(0, 1.1 - (time.monotonic() - LAST)))
 try:
  req = urllib.request.Request(url, headers={'User-Agent': 'PersonalMusicCatalog/0.1 (local self-hosted development)'})
  with urllib.request.urlopen(req, timeout=10) as response:
   raw = response.read().decode(); data = json.loads(raw)
  LAST = time.monotonic()
  with c.db:
   c.db.execute('INSERT OR REPLACE INTO http_cache VALUES(?,?,?,?,?)', (url, 200, raw, time.time(), 0))
   gid = data.get('id')
   c.db.execute('INSERT OR REPLACE INTO release_groups VALUES(?,?,?,?)', (gid, data.get('title'), data.get('primary-type'), data.get('first-release-date')))
   if data.get('artist-credit'): c.credits('group', gid, data['artist-credit'])
   for rel in data.get('releases', []):
    c.db.execute('INSERT OR REPLACE INTO releases VALUES(?,?,?)', (rel['id'], gid, rel.get('title')))
    if rel.get('artist-credit'): c.credits('release', rel['id'], rel['artist-credit'])
 except Exception:
  LAST = time.monotonic()
class Handler(BaseHTTPRequestHandler):
 def log_message(self,*args):pass
 def dispatch(self):
  if self.headers.get('Authorization')!='Bearer '+os.environ['CATALOG_API_TOKEN']:self.send_error(401);return
  route=urllib.parse.urlsplit(self.path);c=Catalog(self.server.database)
  try:
   parts=route.path.strip('/').split('/');q=urllib.parse.parse_qs(route.query)
   if route.path=='/v1/search':
    text=q.get('q',[''])[0][:200]
    if q.get('refresh')==['true']:provider(c,text)
    result={'results':c.search(text),'cached':True}
   elif parts[:2]==['v1','releases'] and len(parts)==3:
    result=c.album(parts[2])
    if result is None:
     fetch_mb_release(c, parts[2])
     result=c.album(parts[2])
   elif parts[:2]==['v1','albums'] and len(parts)==3:
    result=c.group(parts[2])
    if result is None or not result.get('editions'):
     fetch_mb_group(c, parts[2])
     result=c.group(parts[2])
     if result and result.get('editions'):
      for ed in result['editions']:
       if not ed.get('tracks'):
        fetch_mb_release(c, ed['id'])
      result=c.group(parts[2])
   elif parts[:2]==['v1','artists'] and len(parts)==3:result=c.artist(parts[2])
   elif parts[:2]==['v1','recordings'] and len(parts)==4 and parts[3]=='availability':result=c.availability(parts[2])
   elif route.path=='/v1/requests' and self.command=='POST':
    size=int(self.headers.get('Content-Length',0))
    if size>8192:raise ValueError('request too large')
    body=json.loads(self.rfile.read(size));ident=c.request(body['release_id'],body.get('scope','album'));result={'id':ident,'state':'queued','dispatch_enabled':False}
   elif parts[:2]==['v1','requests'] and len(parts)==3:
    row=c.db.execute('SELECT * FROM requests WHERE id=?',(parts[2],)).fetchone();result=dict(row) if row else None
   else:self.send_error(404);return
   if result is None:self.send_error(404);return
   raw=json.dumps(result).encode();self.send_response(200);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(raw)));self.end_headers();self.wfile.write(raw)
  except (ValueError,KeyError,json.JSONDecodeError):self.send_error(400)
  finally:c.db.close()
 do_GET=dispatch
 do_POST=dispatch
def serve(database,port):
 if not os.environ.get('CATALOG_API_TOKEN'):raise RuntimeError('CATALOG_API_TOKEN required')
 server=HTTPServer(('127.0.0.1',port),Handler);server.database=database;server.serve_forever()
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--database',required=True);p.add_argument('--port',type=int,default=8765);a=p.parse_args();serve(a.database,a.port)
