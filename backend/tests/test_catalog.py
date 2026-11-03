import sys,unittest,tempfile
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from catalog import Catalog
def release(ident='edition',group='album',extra=False):
 tracks=[{'id':'track-'+ident,'position':1,'title':'Song','length':100000,'recording':{'id':'recording','title':'Song','length':100000},'artist-credit':[{'name':'A','artist':{'id':'artist-a','name':'A'},'joinphrase':' feat. '},{'name':'B','artist':{'id':'artist-b','name':'B'}}]}]
 if extra:tracks.append({'id':'bonus-track','position':2,'title':'Bonus','recording':{'id':'bonus','title':'Bonus'}})
 return {'id':ident,'title':'Album','release-group':{'id':group,'title':'Album'},'artist-credit':[{'artist':{'id':'artist-a','name':'A'},'name':'A'}],'media':[{'position':1,'tracks':tracks}]}
def item(ident='local',path='/media/Music/song.flac'):
 return {'ServerId':'server','Id':ident,'Path':path,'Name':'Song','Artists':['A','B'],'Album':'Album','IndexNumber':1,'ParentIndexNumber':1,'RunTimeTicks':1000000000}
def evidence():return {'/media/Music/song.flac':{'category':'verified_identity','identifiers':{'recording':['recording']},'release_track':'track-edition'}}
class Tests(unittest.TestCase):
 def setUp(self):self.c=Catalog(':memory:');self.c.release(release());self.c.db.commit()
 def test_fully_owned(self):
  self.c.sync([item()],evidence());self.assertEqual(self.c.album('edition')['ownership'],'full')
 def test_absent(self):self.assertEqual(self.c.availability('recording')['state'],'not_found')
 def test_partial(self):
  self.c.release(release(extra=True));self.c.sync([item()],evidence());self.assertEqual(self.c.album('edition')['ownership'],'partial')
 def test_editions_and_shared_recording(self):
  self.c.release(release('other'));self.c.sync([item()],evidence());self.assertEqual(self.c.album('other')['owned_tracks'],1)
  self.assertEqual(self.c.db.execute('select count(*) from release_groups').fetchone()[0],1)
  self.assertEqual(self.c.db.execute('select count(*) from recordings').fetchone()[0],1)
 def test_collaboration(self):
  self.assertEqual(self.c.db.execute("select count(*) from credits where entity_type='recording'").fetchone()[0],2)
 def test_missing_ids_does_not_match_title(self):
  self.c.sync([item()],{});self.assertEqual(self.c.availability('recording')['state'],'not_found')
  self.assertEqual(self.c.availability('local:server:local')['state'],'available')
 def test_import_transition(self):
  request=self.c.request('edition');self.assertEqual(self.c.availability('recording','edition')['state'],'pending')
  self.c.sync([item()],evidence());self.assertEqual(self.c.availability('recording','edition')['state'],'available')
 def test_ambiguous_never_autoplays(self):
  ev=evidence();ev['/media/Music/song.flac']['category']='ambiguous';self.c.sync([item()],ev)
  self.assertEqual(self.c.availability('recording')['state'],'possibly_available');self.assertIsNone(self.c.availability('recording')['playable_item_id'])
 def test_multiple_files_require_choice(self):
  second=item('other');self.c.sync([item(),second],evidence());self.assertTrue(self.c.availability('recording')['selection_required']);self.assertIsNone(self.c.availability('recording')['playable_item_id'])
 def test_song_request_rejected_and_album_idempotent(self):
  with self.assertRaises(ValueError):self.c.request('edition','song')
  self.assertEqual(self.c.request('edition'),self.c.request('edition'))
 def test_inactive_never_available(self):
  self.c.sync([item()],evidence());self.c.db.execute('update local_items set active=0');self.assertEqual(self.c.availability('recording')['state'],'not_found')
if __name__=='__main__':unittest.main()
