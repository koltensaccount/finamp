"""Bounded actual-index examples; simulated import replay is explicitly labeled."""
import argparse,json,sqlite3
from catalog import Catalog
def main():
 p=argparse.ArgumentParser();p.add_argument('--database',required=True);a=p.parse_args();c=Catalog(a.database)
 cases={}
 for row in c.db.execute('SELECT id FROM releases'):
  album=c.album(row['id']);key={'full':'fully_owned','none':'not_found_in_index','partial':'partially_owned'}[album['ownership']]
  if key not in cases:cases[key]={'release_id':row['id'],'title':album['title'],'owned':album['owned_tracks'],'total':album['total_tracks'],'source':'live Jellyfin + cached MusicBrainz'}
 row=c.db.execute('SELECT group_id,count(*) FROM releases WHERE group_id IS NOT NULL GROUP BY group_id HAVING count(*)>1 LIMIT 1').fetchone()
 cases['multiple_editions']=dict(row) if row else {'status':'not represented in current cache; regression fixture covers it'}
 row=c.db.execute("SELECT entity_id,count(*) as artists FROM credits WHERE entity_type='recording' GROUP BY entity_id HAVING count(*)>1 LIMIT 1").fetchone();cases['collaboration']=dict(row) if row else None
 row=c.db.execute("SELECT item_id FROM mappings WHERE confidence='local_identity' LIMIT 1").fetchone();cases['unverified_or_missing_identifiers']=dict(row) if row else None
 # Replay existing real items through a detached SQLite copy. Never alter live evidence.
 row=c.db.execute("SELECT m.recording_id,l.payload FROM mappings m JOIN local_items l USING(server_id,item_id) WHERE m.confidence='verified' AND l.active=1 LIMIT 1").fetchone()
 if row:
  copy=Catalog(':memory:');c.db.backup(copy.db);copy.db.execute('UPDATE local_items SET active=0');before=copy.availability(row['recording_id'])['state'];obj=json.loads(row['payload']);mapping=c.db.execute('SELECT evidence FROM mappings WHERE recording_id=? AND confidence=\'verified\' LIMIT 1',(row['recording_id'],)).fetchone();copy.sync([obj],{obj['Path']:json.loads(mapping[0])});after=copy.availability(row['recording_id'])['state'];cases['import_transition']={'before':before,'after':after,'source':'controlled replay of actual API item; no acquisition or production import triggered'}
 print(json.dumps(cases,indent=2))
if __name__=='__main__':main()
