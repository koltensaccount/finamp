"""Persistent catalog identity graph and conservative local availability."""
import hashlib,json,sqlite3,time,unicodedata

SCHEMA='''
PRAGMA journal_mode=WAL;
CREATE TABLE IF NOT EXISTS artists(id TEXT PRIMARY KEY,name TEXT);
CREATE TABLE IF NOT EXISTS release_groups(id TEXT PRIMARY KEY,title TEXT,primary_type TEXT,first_date TEXT);
CREATE TABLE IF NOT EXISTS releases(id TEXT PRIMARY KEY,group_id TEXT,title TEXT);
CREATE TABLE IF NOT EXISTS recordings(id TEXT PRIMARY KEY,title TEXT,duration_ms INTEGER);
CREATE TABLE IF NOT EXISTS release_tracks(id TEXT PRIMARY KEY,release_id TEXT,recording_id TEXT,disc INTEGER,position INTEGER,title TEXT,duration_ms INTEGER);
CREATE TABLE IF NOT EXISTS credits(entity_type TEXT,entity_id TEXT,artist_id TEXT,position INTEGER,display_name TEXT,joinphrase TEXT,PRIMARY KEY(entity_type,entity_id,position));
CREATE TABLE IF NOT EXISTS local_items(server_id TEXT,item_id TEXT,path TEXT,payload TEXT,payload_hash TEXT,active INTEGER,PRIMARY KEY(server_id,item_id));
CREATE TABLE IF NOT EXISTS mappings(server_id TEXT,item_id TEXT,recording_id TEXT,release_track_id TEXT,confidence TEXT,evidence TEXT,PRIMARY KEY(server_id,item_id,recording_id));
CREATE TABLE IF NOT EXISTS requests(id INTEGER PRIMARY KEY,release_id TEXT,scope TEXT,state TEXT,origin TEXT,backend_id TEXT,created_at REAL);
CREATE TABLE IF NOT EXISTS http_cache(url TEXT PRIMARY KEY,status INTEGER,payload TEXT,fetched_at REAL,retry_at REAL);
CREATE TABLE IF NOT EXISTS sync_runs(id INTEGER PRIMARY KEY,started REAL,completed REAL,item_count INTEGER);
CREATE TABLE IF NOT EXISTS search_hits(query TEXT,kind TEXT,id TEXT,position INTEGER,PRIMARY KEY(query,kind,id));
'''
def norm(s):return ' '.join(unicodedata.normalize('NFKC',s or '').casefold().split())
class Catalog:
 def __init__(self,path):
  self.db=sqlite3.connect(path);self.db.row_factory=sqlite3.Row;self.db.executescript(SCHEMA)
 def credits(self,kind,ident,values):
  self.db.execute('DELETE FROM credits WHERE entity_type=? AND entity_id=?',(kind,ident))
  for i,v in enumerate(values or []):
   a=v.get('artist',{});aid=a.get('id')
   if not aid:continue
   self.db.execute('INSERT OR REPLACE INTO artists VALUES(?,?)',(aid,a.get('name',v.get('name',''))))
   self.db.execute('INSERT INTO credits VALUES(?,?,?,?,?,?)',(kind,ident,aid,i,v.get('name',a.get('name','')),v.get('joinphrase','')))
 def release(self,r):
  group=r.get('release-group',{});gid=group.get('id')
  if gid:
   self.db.execute('INSERT OR REPLACE INTO release_groups VALUES(?,?,?,?)',(gid,group.get('title',r.get('title')),group.get('primary-type'),group.get('first-release-date')))
   if group.get('artist-credit'):self.credits('group',gid,group['artist-credit'])
  self.db.execute('INSERT OR REPLACE INTO releases VALUES(?,?,?)',(r['id'],gid,r.get('title')))
  self.credits('release',r['id'],r.get('artist-credit'))
  if gid and not group.get('artist-credit'):self.credits('group',gid,r.get('artist-credit'))
  for medium in r.get('media',[]):
   for t in medium.get('tracks',[]):
    rec=t.get('recording',{});rid=rec.get('id')
    if not rid:continue
    self.db.execute('INSERT OR REPLACE INTO recordings VALUES(?,?,?)',(rid,rec.get('title',t.get('title')),rec.get('length',t.get('length'))))
    self.db.execute('INSERT OR REPLACE INTO release_tracks VALUES(?,?,?,?,?,?,?)',(t['id'],r['id'],rid,medium['position'],t['position'],t.get('title'),t.get('length',rec.get('length'))))
    self.credits('recording',rid,rec.get('artist-credit') or t.get('artist-credit'))
 def sync(self,items,evidence):
  """Complete API snapshot; only changed payloads rewritten; stale items deactivated."""
  with self.db:
   run=self.db.execute('INSERT INTO sync_runs(started) VALUES(?)',(time.time(),)).lastrowid
   seen=set();servers=set()
   for item in items:
    server=item['ServerId'];ident=item['Id'];servers.add(server);seen.add((server,ident))
    payload=json.dumps(item,sort_keys=True);digest=hashlib.sha256(payload.encode()).hexdigest()
    self.db.execute('INSERT INTO local_items VALUES(?,?,?,?,?,1) ON CONFLICT(server_id,item_id) DO UPDATE SET path=excluded.path,payload=excluded.payload,payload_hash=excluded.payload_hash,active=1 WHERE payload_hash!=excluded.payload_hash OR active=0',(server,ident,item.get('Path'),payload,digest))
    self.db.execute('DELETE FROM mappings WHERE server_id=? AND item_id=?',(server,ident))
    ev=evidence.get(item.get('Path'),{});ids=ev.get('identifiers',{});rid=(ids.get('recording') or [None])[0]
    # Audit verification confirms the entity semantics; Jellyfin IDs alone are hints.
    if ev.get('category')=='verified_identity' and rid:
     self.db.execute('INSERT OR REPLACE INTO mappings VALUES(?,?,?,?,?,?)',(server,ident,rid,ev.get('release_track'),'verified',json.dumps(ev)))
    else:
     rec_hint=item.get('ProviderIds',{}).get('MusicBrainzTrack') or rid
     if rec_hint:
      self.db.execute('INSERT OR REPLACE INTO mappings VALUES(?,?,?,?,?,?)',(server,ident,rec_hint,ev.get('release_track'),'ambiguous',json.dumps(ev)))
     # No MBID: permit candidates only with exact edition, position, credit/title and duration.
     rel=item.get('ProviderIds',{}).get('MusicBrainzAlbum') or (ids.get('release') or [None])[0]
     if rel:
      for tr in self.db.execute('SELECT * FROM release_tracks WHERE release_id=? AND disc=? AND position=?',(rel,item.get('ParentIndexNumber') or 1,item.get('IndexNumber') or 0)).fetchall():
       credit=[x[0] for x in self.db.execute("SELECT display_name FROM credits WHERE entity_type='recording' AND entity_id=? ORDER BY position",(tr['recording_id'],))]
       duration=item.get('RunTimeTicks',0)/10000
       if norm(item.get('Name'))==norm(tr['title']) and credit and {norm(x) for x in item.get('Artists',[])}=={norm(x) for x in credit} and tr['duration_ms'] and abs(duration-tr['duration_ms'])<=2000:
        self.db.execute('INSERT OR REPLACE INTO mappings VALUES(?,?,?,?,?,?)',(server,ident,tr['recording_id'],tr['id'],'ambiguous',json.dumps({'reason':'exact context secondary candidate; recording identity not yet verified'})))
     local_id='local:'+server+':'+ident
     self.db.execute('INSERT OR REPLACE INTO recordings VALUES(?,?,?)',(local_id,item.get('Name'),int(item.get('RunTimeTicks',0)/10000)))
     self.db.execute('INSERT OR REPLACE INTO mappings VALUES(?,?,?,?,?,?)',(server,ident,local_id,None,'local_identity',json.dumps({'reason':'playable Jellyfin identity; no public catalog equivalence claimed'})))
   for server in servers:
    for row in self.db.execute('SELECT item_id FROM local_items WHERE server_id=? AND active=1',(server,)).fetchall():
     if (server,row[0]) not in seen:self.db.execute('UPDATE local_items SET active=0 WHERE server_id=? AND item_id=?',(server,row[0]))
   self.db.execute('UPDATE sync_runs SET completed=?,item_count=? WHERE id=?',(time.time(),len(items),run))
   for request in self.db.execute("SELECT id,release_id FROM requests WHERE state NOT IN ('failed','available')").fetchall():
    album=self.album(request['release_id'])
    if album and album['ownership']=='full':self.db.execute("UPDATE requests SET state='available' WHERE id=?",(request['id'],))
 def availability(self,recording_id,release_id=None):
  rows=self.db.execute('SELECT m.*,l.payload FROM mappings m JOIN local_items l USING(server_id,item_id) WHERE recording_id=? AND active=1',(recording_id,)).fetchall()
  exact=[r for r in rows if r['confidence'] in ('verified','local_identity')];state='available' if exact else 'possibly_available' if rows else 'not_found'
  pending=False
  if release_id:pending=bool(self.db.execute("SELECT 1 FROM requests WHERE release_id=? AND state NOT IN ('failed','available')",(release_id,)).fetchone())
  else:pending=bool(self.db.execute("SELECT 1 FROM requests q JOIN release_tracks t ON q.release_id=t.release_id WHERE t.recording_id=? AND q.state NOT IN ('failed','available')",(recording_id,)).fetchone())
  if state=='not_found' and pending:state='pending'
  return {'state':state,'acquisition_pending':pending,'local_items':[{'server_id':r['server_id'],'item_id':r['item_id']} for r in exact],'playable_item_id':exact[0]['item_id'] if len(exact)==1 else None,'selection_required':len(exact)>1,'candidate_count':len(rows)}
 def album(self,release_id):
  release=self.db.execute('SELECT * FROM releases WHERE id=?',(release_id,)).fetchone()
  if not release:return None
  tracks=[]
  for t in self.db.execute('SELECT * FROM release_tracks WHERE release_id=? ORDER BY disc,position',(release_id,)):
   row=dict(t);row['availability']=self.availability(t['recording_id'],release_id);tracks.append(row)
  available=sum(t['availability']['state']=='available' for t in tracks)
  return {**dict(release),'tracks':tracks,'owned_tracks':available,'total_tracks':len(tracks),'ownership':'full' if tracks and available==len(tracks) else 'partial' if available else 'none'}
 def search(self,q):
  results=[]
  for table,kind in [('artists','artist'),('release_groups','album'),('recordings','track')]:
   column='name' if kind=='artist' else 'title'
   for r in self.db.execute('SELECT * FROM '+table+' WHERE '+column+' LIKE ? OR id IN (SELECT id FROM search_hits WHERE query=? AND kind=?) LIMIT 25',('%'+q+'%',norm(q),kind)):
    row=dict(r);row['kind']=kind
    if kind=='track':row['availability']=self.availability(r['id'])
    if kind=='album':row['edition_ids']=[x[0] for x in self.db.execute('SELECT id FROM releases WHERE group_id=?',(r['id'],))]
    results.append(row)
  return results
 def group(self,group_id):
  group=self.db.execute('SELECT * FROM release_groups WHERE id=?',(group_id,)).fetchone()
  if not group:return None
  editions=[self.album(r[0]) for r in self.db.execute('SELECT id FROM releases WHERE group_id=?',(group_id,))]
  return {**dict(group),'editions':editions}
 def artist(self,artist_id):
  artist=self.db.execute('SELECT * FROM artists WHERE id=?',(artist_id,)).fetchone()
  if not artist:return None
  groups=[dict(x) for x in self.db.execute("SELECT DISTINCT g.* FROM release_groups g JOIN credits c ON c.entity_id=g.id WHERE c.entity_type='group' AND c.artist_id=? ORDER BY first_date",(artist_id,))]
  recordings=[dict(x) for x in self.db.execute("SELECT DISTINCT r.* FROM recordings r JOIN credits c ON c.entity_id=r.id WHERE c.entity_type='recording' AND c.artist_id=?",(artist_id,))]
  return {**dict(artist),'albums':groups,'recordings':recordings}
 def request(self,release_id,scope='album',origin='explicit_user'):
  if scope!='album':raise ValueError('single-song acquisition is not supported by the current backend')
  if not self.db.execute('SELECT 1 FROM releases WHERE id=?',(release_id,)).fetchone():raise ValueError('unknown release')
  row=self.db.execute("SELECT id FROM requests WHERE release_id=? AND state NOT IN ('failed','available')",(release_id,)).fetchone()
  if row:return row[0]
  with self.db:return self.db.execute('INSERT INTO requests(release_id,scope,state,origin,created_at) VALUES(?,?,?,?,?)',(release_id,scope,'queued',origin,time.time())).lastrowid
