"""Read-only Jellyfin and audit reconciliation; writes only the catalog index."""
import argparse,hashlib,json,sqlite3,urllib.request,time
from pathlib import Path
from catalog import Catalog
def refresh(a):
 root=a.audit;c=Catalog(a.database)
 cache=sqlite3.connect('file:'+str(root/'matching-v1.sqlite')+'?mode=ro',uri=True)
 with c.db:
  for raw, in cache.execute('SELECT body_json FROM api_cache WHERE status=200'):
   payload=json.loads(raw)
   if payload.get('id') and payload.get('media'):c.release(payload)
 evidence={};verified=sqlite3.connect('file:'+str(root/'phase4-verified.sqlite')+'?mode=ro',uri=True)
 for path,category,raw in verified.execute('SELECT path,category,evidence FROM results'):
  ev=json.loads(raw);ev['category']=category;evidence[path.replace('/mnt/media/','/media/',1)]=ev
 jf=sqlite3.connect('file:'+str(Path.home()/'jellyfin/config/data/jellyfin.db')+'?mode=ro',uri=True)
 key=jf.execute('select AccessToken from ApiKeys limit 1').fetchone()
 if not key:key=jf.execute('select AccessToken from Devices where IsActive=1 order by DateLastActivity desc limit 1').fetchone()
 if not key:raise RuntimeError('no existing Jellyfin access')
 items=[];start=0
 while True:
  url='http://127.0.0.1:8096/Items?Recursive=true&IncludeItemTypes=Audio&Fields=Path,ProviderIds,AlbumArtists,ArtistItems&Limit=500&StartIndex='+str(start)
  with urllib.request.urlopen(urllib.request.Request(url,headers={'X-Emby-Token':key[0]}),timeout=30) as response:page=json.load(response)
  batch=page['Items'];items.extend(batch);start+=len(batch)
  if start>=page['TotalRecordCount']:break
  if not batch:raise RuntimeError('incomplete Jellyfin enumeration; prior index retained')
 # Snapshot must not accidentally merge a server-wide virtual item without a playable path.
 items=[i for i in items if i.get('Path') and not Path(i['Path']).name.startswith('._')]
 c.sync(items,evidence)
 summary={'jellyfin_audio_items':len(items),'public_recordings':c.db.execute("select count(*) from recordings where id not like 'local:%'").fetchone()[0],'confident_mappings':c.db.execute("select count(*) from mappings where confidence='verified'").fetchone()[0],'local_only_mappings':c.db.execute("select count(*) from mappings where confidence='local_identity'").fetchone()[0],'ambiguous_candidates':c.db.execute("select count(*) from mappings where confidence='ambiguous'").fetchone()[0]}
 inv=sqlite3.connect('file:'+str(root/'inventory-v2.sqlite')+'?mode=ro',uri=True)
 old={p.replace('/mnt/media/','/media/',1) for p, in inv.execute("select path from files where scope='library'")};current={i['Path'] for i in items}
 summary.update(new_since_inventory=len(current-old),inventory_paths_not_in_jellyfin=len(old-current))
 print(json.dumps(summary));Path(a.database).with_suffix('.summary.json').write_text(json.dumps(summary,indent=2))
if __name__=='__main__':
 ap=argparse.ArgumentParser();ap.add_argument('--audit',type=Path,default=Path.home()/'music-metadata-audit');ap.add_argument('--database',required=True);ap.add_argument('--watch',action='store_true');a=ap.parse_args()
 while True:
  try:refresh(a)
  except Exception as exc:
   if not a.watch:raise
   print(json.dumps({'sync_failed':type(exc).__name__,'prior_index_preserved':True}),flush=True)
  if not a.watch:break
  time.sleep(300)
