import unittest, json, sqlite3
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from catalog import Catalog

class DiscographyTests(unittest.TestCase):
    def setUp(self):
        self.c = Catalog(':memory:')
        self.artist_id = 'art-1'
        self.c.db.execute("INSERT INTO artists VALUES(?, 'The Example')", (self.artist_id,))

        # Studio Album (primary_type=Album, no secondary types)
        self.c.db.execute("INSERT INTO release_groups VALUES('g-studio', 'Studio Album', 'Album', '1965-01-01', '[]')")
        self.c.db.execute("INSERT INTO credits VALUES('group', 'g-studio', ?, 0, 'The Example', '')", (self.artist_id,))

        # EP (primary_type=EP)
        self.c.db.execute("INSERT INTO release_groups VALUES('g-ep', 'My EP', 'EP', '1966-01-01', '[]')")
        self.c.db.execute("INSERT INTO credits VALUES('group', 'g-ep', ?, 0, 'The Example', '')", (self.artist_id,))

        # Single (primary_type=Single)
        self.c.db.execute("INSERT INTO release_groups VALUES('g-single', 'Hit Single', 'Single', '1964-01-01', '[]')")
        self.c.db.execute("INSERT INTO credits VALUES('group', 'g-single', ?, 0, 'The Example', '')", (self.artist_id,))

        # Compilation (primary_type=Album, secondary_types=['Compilation'])
        self.c.db.execute("INSERT INTO release_groups VALUES('g-comp', 'Greatest Hits', 'Album', '1970-01-01', '[\"Compilation\"]')")
        self.c.db.execute("INSERT INTO credits VALUES('group', 'g-comp', ?, 0, 'The Example', '')", (self.artist_id,))

        # Live (primary_type=Album, secondary_types=['Live'])
        self.c.db.execute("INSERT INTO release_groups VALUES('g-live', 'Live at Arena', 'Album', '1968-01-01', '[\"Live\"]')")
        self.c.db.execute("INSERT INTO credits VALUES('group', 'g-live', ?, 0, 'The Example', '')", (self.artist_id,))

        # Releases under g-studio
        self.c.db.execute("INSERT INTO releases VALUES('rel-1', 'g-studio', 'Studio Album')")
        self.c.db.execute("INSERT INTO release_tracks VALUES('rt-1', 'rel-1', 'rec-1', 1, 1, 'Track 1', 200000)")
        self.c.db.execute("INSERT INTO recordings VALUES('rec-1', 'Track 1', 200000)")
        self.c.db.execute("INSERT INTO credits VALUES('recording', 'rec-1', ?, 0, 'The Example', '')", (self.artist_id,))

        # Owned item mapping for rec-1
        self.c.db.execute("INSERT INTO local_items VALUES('srv', 'item-1', '/music/1.flac', '{}', 'hash1', 1)")
        self.c.db.execute("INSERT INTO mappings VALUES('srv', 'item-1', 'rec-1', 'rt-1', 'verified', '{}')")

    def test_artist_categories_and_ordering(self):
        res = self.c.artist(self.artist_id)
        self.assertIsNotNone(res)
        self.assertEqual(res['name'], 'The Example')
        albums = res['albums']
        self.assertEqual(len(albums), 5)
        cats = [a['category'] for a in albums]
        self.assertEqual(cats, ['album', 'ep', 'single', 'compilation', 'live'])
        self.assertEqual(albums[0]['id'], 'g-studio')
        self.assertEqual(albums[0]['ownership'], 'full')
        self.assertTrue(albums[0]['image_url'].startswith('https://coverartarchive.org/release-group/g-studio/front-250'))

    def test_recordings_only_include_owned(self):
        res = self.c.artist(self.artist_id)
        recs = res['recordings']
        self.assertEqual(len(recs), 1)
        self.assertEqual(recs[0]['id'], 'rec-1')
        self.assertEqual(recs[0]['availability']['state'], 'available')

if __name__ == '__main__':
    unittest.main()
