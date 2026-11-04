import unittest, json, sqlite3
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from catalog import Catalog

class DiscographyTests(unittest.TestCase):
    def setUp(self):
        self.c = Catalog(':memory:')
        self.artist_id = 'art-1'
        self.c.db.execute("INSERT INTO artists (id, name) VALUES(?, 'The Example')", (self.artist_id,))

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

    def test_resolve_artist_by_mapping_and_name(self):
        # 1. Resolve by local mapping item_id
        resolved = self.c.resolve_artist(jellyfin_id='item-1')
        self.assertIsNotNone(resolved)
        self.assertEqual(resolved['id'], self.artist_id)
        self.assertEqual(resolved['name'], 'The Example')
        self.assertEqual(resolved['confidence'], 'verified')

        # 2. Resolve by unique name match
        resolved_name = self.c.resolve_artist(name='the example')
        self.assertIsNotNone(resolved_name)
        self.assertEqual(resolved_name['id'], self.artist_id)
        self.assertEqual(resolved_name['confidence'], 'name_match')

        # 3. Ambiguous name match (multiple artists share same name) never returns single id
        self.c.db.execute("INSERT INTO artists (id, name) VALUES('art-duplicate', 'The Example')")
        ambiguous = self.c.resolve_artist(name='the example')
        self.assertIsNotNone(ambiguous)
        self.assertEqual(ambiguous['confidence'], 'ambiguous')
        self.assertIsNone(ambiguous['id'])
        self.assertEqual(len(ambiguous['candidates']), 2)

        # 4. Unknown name returns None
        self.assertIsNone(self.c.resolve_artist(name='Nonexistent Artist'))

    def test_featured_artist_never_steals_primary_track_provider_id(self):
        # A track with primary artist 'The Example' (MBID: art-1) and featured artist 'Collaborator' (JF ID: jf-collab)
        import json
        payload = json.dumps({
            'Name': 'Collab Track',
            'ProviderIds': {'MusicBrainzArtist': self.artist_id},
            'ArtistItems': [
                {'Id': 'jf-primary', 'Name': 'The Example'},
                {'Id': 'jf-collab', 'Name': 'Collaborator'}
            ]
        })
        self.c.db.execute("INSERT INTO artists (id, name) VALUES('art-collab', 'Collaborator')")
        self.c.db.execute("INSERT INTO local_items VALUES('srv', 'item-collab-track', '/music/collab.flac', ?, 'hash-collab', 1)", (payload,))

        # Resolving for Collaborator's Jellyfin ID must resolve to Collaborator (art-collab), NOT The Example (art-1)
        res = self.c.resolve_artist(jellyfin_id='jf-collab')
        self.assertIsNotNone(res)
        self.assertEqual(res['id'], 'art-collab')
        self.assertEqual(res['name'], 'Collaborator')

    def test_resolving_track_id_with_featured_artist_name_does_not_trust_unmatched_provider_id(self):
        # Track has an unknown primary provider ID, but a cataloged featured artist name is requested
        import json
        payload = json.dumps({
            'Name': 'Track With Unknown Primary Provider',
            'ProviderIds': {'MusicBrainzArtist': 'unknown-mbid-999'},
            'ArtistItems': [
                {'Id': 'jf-primary-unknown', 'Name': 'Unknown Primary'},
                {'Id': 'jf-collab-2', 'Name': 'Known Collab'}
            ]
        })
        self.c.db.execute("INSERT INTO artists (id, name) VALUES('art-known-collab', 'Known Collab')")
        self.c.db.execute("INSERT INTO local_items VALUES('srv', 'item-unknown-primary', '/music/track2.flac', ?, 'hash2', 1)", (payload,))

        # Querying by track ID with name='Known Collab' must resolve to art-known-collab, NEVER unknown-mbid-999
        res = self.c.resolve_artist(item_id='item-unknown-primary', name='Known Collab')
        self.assertIsNotNone(res)
        self.assertEqual(res['id'], 'art-known-collab')
        self.assertEqual(res['name'], 'Known Collab')

if __name__ == '__main__':
    unittest.main()
