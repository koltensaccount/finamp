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
 inv=sqlite3.connect('file:'+str(root/'inventory-v2.sqlite')+'?mode=ro',uri=True)
 baseline={p:(size,mtime) for p,size,mtime in inv.execute("SELECT path,size_bytes,mtime_ns FROM files WHERE scope='library'")}
 evidence={};verified=sqlite3.connect('file:'+str(root/'phase4-verified.sqlite')+'?mode=ro',uri=True)
 for path,category,raw in verified.execute('SELECT path,category,evidence FROM results'):
  ev=json.loads(raw);ev['category']=category
  if category=='verified_identity':
   try:
    stat=Path(path).stat()
    if (stat.st_size,stat.st_mtime_ns)!=baseline.get(path):ev['category']='ambiguous';ev['drift']='changed_since_inventory'
   except OSError:ev['category']='ambiguous';ev['drift']='source_unavailable'
  evidence[path.replace('/mnt/media/','/media/',1)]=ev
 for p, tags_raw in inv.execute("SELECT path, tags_json FROM files WHERE scope='library' AND tags_json IS NOT NULL"):
  jf_path = p.replace('/mnt/media/', '/media/', 1)
  if jf_path not in evidence:
   try:
    tags = json.loads(tags_raw)
    mb_track = (tags.get('musicbrainz_trackid') or tags.get('musicbrainz_recordingid') or [None])[0]
    mb_album = (tags.get('musicbrainz_albumid') or [None])[0]
    if mb_track or mb_album:
     evidence[jf_path] = {
      'category': 'verified_identity' if mb_track else 'ambiguous',
      'identifiers': {'recording': [mb_track] if mb_track else [], 'release': [mb_album] if mb_album else []},
      'release_track': None,
      'source': 'inventory_tags'
     }
   except Exception:
    pass
 jf=sqlite3.connect('file:'+str(Path.home()/'jellyfin/config/data/jellyfin.db')+'?mode=ro',uri=True)
 key=jf.execute('select AccessToken from ApiKeys limit 1').fetchone()
 if not key:key=jf.execute('select AccessToken from Devices where IsActive=1 order by DateLastActivity desc limit 1').fetchone()
 if not key:raise RuntimeError('no existing Jellyfin access')
 album_providers = {}
 try:
  album_url = 'http://127.0.0.1:8096/Items?Recursive=true&IncludeItemTypes=MusicAlbum&Fields=ProviderIds&Limit=2000'
  with urllib.request.urlopen(urllib.request.Request(album_url, headers={'X-Emby-Token': key[0]}), timeout=30) as response:
   albums_data = json.load(response)
  album_providers = {alb['Id']: alb.get('ProviderIds', {}) for alb in albums_data.get('Items', [])}
 except Exception:
  pass
 items=[];start=0
 while True:
  url='http://127.0.0.1:8096/Items?Recursive=true&IncludeItemTypes=Audio&Fields=Path,ProviderIds,AlbumArtists,ArtistItems,AlbumId,Album,IndexNumber,ParentIndexNumber&Limit=500&StartIndex='+str(start)
  with urllib.request.urlopen(urllib.request.Request(url,headers={'X-Emby-Token':key[0]}),timeout=30) as response:page=json.load(response)
  batch=page['Items'];items.extend(batch);start+=len(batch)
  if start>=page['TotalRecordCount']:break
  if not batch:raise RuntimeError('incomplete Jellyfin enumeration; prior index retained')
 # Snapshot must not accidentally merge a server-wide virtual item without a playable path.
 items=[i for i in items if i.get('Path') and not Path(i['Path']).name.startswith('._')]
 for it in items:
  alb_id = it.get('AlbumId')
  if alb_id and alb_id in album_providers:
   alb_p = album_providers[alb_id]
   prov = it.setdefault('ProviderIds', {})
   if 'MusicBrainzAlbum' not in prov and 'MusicBrainzAlbum' in alb_p:
    prov['MusicBrainzAlbum'] = alb_p['MusicBrainzAlbum']
   if 'MusicBrainzReleaseGroup' not in prov and 'MusicBrainzReleaseGroup' in alb_p:
    prov['MusicBrainzReleaseGroup'] = alb_p['MusicBrainzReleaseGroup']
  p = it.get('Path')
  if p and p not in evidence:
   prov = it.get('ProviderIds', {})
   mb_rec = prov.get('MusicBrainzRecording')
   mb_alb = prov.get('MusicBrainzAlbum')
   mb_trk = prov.get('MusicBrainzTrack')
   if mb_rec or mb_alb:
    evidence[p] = {
     'category': 'verified_identity' if mb_rec else 'ambiguous',
     'identifiers': {'recording': [mb_rec] if mb_rec else [], 'release': [mb_alb] if mb_alb else []},
     'release_track': mb_trk,
     'source': 'jellyfin_providerids'
    }
 c.sync(items,evidence)
 with c.db:
  for it in items:
   prov = it.get('ProviderIds', {})
   mb_alb = prov.get('MusicBrainzAlbum')
   mb_grp = prov.get('MusicBrainzReleaseGroup')
   mb_rec = prov.get('MusicBrainzRecording')
   mb_trk = prov.get('MusicBrainzTrack')
   dur = int(it.get('RunTimeTicks', 0) / 10000)
   disc = it.get('ParentIndexNumber') or 1
   pos = it.get('IndexNumber') or 0
   if mb_rec:
    c.db.execute('INSERT OR IGNORE INTO recordings VALUES(?,?,?)', (mb_rec, it.get('Name'), dur))
   if mb_grp:
    c.db.execute('''
        INSERT INTO release_groups(id, title, primary_type, first_date, secondary_types)
        VALUES(?,?,?,?,?)
        ON CONFLICT(id) DO UPDATE SET title=excluded.title
    ''', (mb_grp, it.get('Album'), 'Album', str(it.get('ProductionYear', ''))[:4], '[]'))
   server = it.get('ServerId', '')
   ident = it.get('Id', '')
   local_id = 'local:' + server + ':' + ident
   rec_id = mb_rec or local_id
   if mb_alb:
    c.db.execute('INSERT OR IGNORE INTO releases VALUES(?,?,?)', (mb_alb, mb_grp, it.get('Album')))
    trk_id = mb_trk or f"{mb_alb}:{disc}:{pos}"
    c.db.execute('INSERT OR IGNORE INTO release_tracks VALUES(?,?,?,?,?,?,?)', (trk_id, mb_alb, rec_id, disc, pos, it.get('Name'), dur))
   for art in it.get('AlbumArtists', []):
    art_mb = art.get('ProviderIds', {}).get('MusicBrainzArtist') or prov.get('MusicBrainzAlbumArtist') or prov.get('MusicBrainzArtist')
    if not art_mb and art.get('Name'):
     row = c.db.execute('SELECT id FROM artists WHERE lower(name)=lower(?)', (art['Name'].strip(),)).fetchone()
     if row: art_mb = row[0]
    if art_mb:
     c.db.execute('INSERT INTO artists(id, name) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET name=excluded.name', (art_mb, art.get('Name')))
     if mb_grp:
      c.db.execute("INSERT OR IGNORE INTO credits VALUES('group', ?, ?, 0, ?, '')", (mb_grp, art_mb, art.get('Name')))
   for art in it.get('ArtistItems', []):
    art_mb = art.get('ProviderIds', {}).get('MusicBrainzArtist') or prov.get('MusicBrainzArtist')
    if not art_mb and art.get('Name'):
     row = c.db.execute('SELECT id FROM artists WHERE lower(name)=lower(?)', (art['Name'].strip(),)).fetchone()
     if row: art_mb = row[0]
    if art_mb:
     c.db.execute('INSERT INTO artists(id, name) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET name=excluded.name', (art_mb, art.get('Name')))
     if rec_id:
      c.db.execute("INSERT OR IGNORE INTO credits VALUES('recording', ?, ?, 0, ?, '')", (rec_id, art_mb, art.get('Name')))
  for rel_id, in c.db.execute("SELECT id FROM releases").fetchall():
   c.reconcile_release(rel_id)
 try:
  from acquisition import AcquisitionDispatcher
  dispatcher = AcquisitionDispatcher(c)
  poll_res = dispatcher.poll_lifecycle()
  if poll_res.get('active_count', 0) > 0:
   summary['active_requests'] = poll_res['active_count']
 except Exception:
  pass
 summary={'jellyfin_audio_items':len(items),'public_recordings':c.db.execute("select count(*) from recordings where id not like 'local:%'").fetchone()[0],'confident_mappings':c.db.execute("select count(*) from mappings where confidence='verified'").fetchone()[0],'local_only_mappings':c.db.execute("select count(*) from mappings where confidence='local_identity'").fetchone()[0],'ambiguous_candidates':c.db.execute("select count(*) from mappings where confidence='ambiguous'").fetchone()[0]}
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
