import unittest
from test_catalog import Catalog, item, release

class ReconciliationIdentityTests(unittest.TestCase):
    def setUp(self):
        self.c = Catalog(":memory:")
        self.c.release(release())
        self.c.db.commit()
    def reconcile_candidate(self, candidate, album='Album'):
        data = release()
        data['title'] = album
        self.c.release(data)
        self.c.sync([candidate], {})
        self.c.reconcile_release('edition')
        return self.c.availability('recording')

    def test_short_album_name_does_not_match_prefix(self):
        candidate = {**item(), 'Album': '1000 gecs', 'Name': '745 sticky', 'Artists': ['100 gecs']}
        self.assertEqual(self.reconcile_candidate(candidate, '1')['state'], 'not_found')

    def test_same_duration_and_position_do_not_override_title(self):
        self.assertEqual(self.reconcile_candidate({**item(), 'Name': 'Wrong song'})['state'], 'not_found')

    def test_same_album_title_does_not_override_artist(self):
        self.assertEqual(self.reconcile_candidate({**item(), 'Artists': ['Unrelated artist']})['state'], 'not_found')

    def test_matching_identity_remains_playable(self):
        self.assertEqual(self.reconcile_candidate(item())['playable_item_id'], 'local')

    def test_stale_duration_only_mapping_cannot_be_offered(self):
        import json
        wrong = {**item(), 'Name': '745 sticky', 'Artists': ['100 gecs'], 'Album': '1000 gecs'}
        self.c.sync([wrong], {})
        self.c.db.execute('INSERT OR REPLACE INTO mappings VALUES(?,?,?,?,?,?)',
            ('server', 'local', 'recording', 'track-edition', 'local_identity',
             json.dumps({'reason': 'matched local track position and duration'})))
        result = self.c.availability('recording')
        self.assertEqual(result['local_items'], [])
        self.assertIsNone(result['playable_item_id'])
