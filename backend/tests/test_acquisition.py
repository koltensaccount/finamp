"""Tests for Acquisition Dispatcher and Lifecycle Manager."""
import json, os, sqlite3, sys, time, unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from catalog import Catalog
from acquisition import AcquisitionDispatcher

def mock_release(ident='edition-1', group='group-1'):
    tracks = [
        {
            'id': f'track-{ident}-1',
            'position': 1,
            'title': 'Track One',
            'length': 180000,
            'recording': {'id': f'rec-{ident}-1', 'title': 'Track One', 'length': 180000},
            'artist-credit': [{'name': 'Artist X', 'artist': {'id': 'art-1', 'name': 'Artist X'}}]
        },
        {
            'id': f'track-{ident}-2',
            'position': 2,
            'title': 'Track Two',
            'length': 200000,
            'recording': {'id': f'rec-{ident}-2', 'title': 'Track Two', 'length': 200000},
            'artist-credit': [{'name': 'Artist X', 'artist': {'id': 'art-1', 'name': 'Artist X'}}]
        }
    ]
    return {
        'id': ident,
        'title': 'Album Title',
        'release-group': {'id': group, 'title': 'Album Title', 'primary-type': 'Album', 'first-release-date': '2024-01-01'},
        'artist-credit': [{'artist': {'id': 'art-1', 'name': 'Artist X'}, 'name': 'Artist X'}],
        'media': [{'position': 1, 'tracks': tracks}]
    }

class MockLidarrClient:
    def __init__(self):
        self.artists = [{'id': 101, 'artistName': 'Artist X', 'foreignArtistId': 'art-1'}]
        self.albums = [{'id': 201, 'artistId': 101, 'title': 'Album Title', 'foreignAlbumId': 'group-1', 'monitored': False, 'statistics': {'percentOfTracks': 0}}]
        self.commands = []

    def get_artists(self):
        return self.artists

    def add_artist(self, payload):
        art = {'id': 102, 'artistName': payload['artistName'], 'foreignArtistId': payload['foreignArtistId']}
        self.artists.append(art)
        return art

    def get_artist_albums(self, artist_id):
        return [a for a in self.albums if a['artistId'] == artist_id]

    def update_album(self, album_id, payload):
        for a in self.albums:
            if a['id'] == album_id:
                a.update(payload)
                return a
        return payload

    def search_album(self, album_id):
        self.commands.append({'name': 'AlbumSearch', 'albumId': album_id})
        return {'id': 999, 'name': 'AlbumSearch', 'status': 'queued'}

    def get_album(self, album_id):
        for a in self.albums:
            if a['id'] == album_id:
                return a
        return {}

class MockSlskdClient:
    def __init__(self):
        self.downloads = []

    def get_downloads(self):
        return self.downloads

class AcquisitionTests(unittest.TestCase):
    def setUp(self):
        self.c = Catalog(':memory:')
        self.c.release(mock_release())
        self.c.db.commit()
        self.lidarr = MockLidarrClient()
        self.slskd = MockSlskdClient()
        self.dispatcher = AcquisitionDispatcher(
            self.c,
            dispatch_enabled=True,
            lidarr_client=self.lidarr,
            slskd_client=self.slskd
        )

    def test_single_song_request_rejected(self):
        with self.assertRaises(ValueError):
            self.dispatcher.submit_request('edition-1', scope='song')

    def test_request_deduplication(self):
        req1 = self.dispatcher.submit_request('edition-1')
        req2 = self.dispatcher.submit_request('edition-1')
        self.assertEqual(req1['id'], req2['id'])
        self.assertEqual(req1['state'], req2['state'])

    def test_already_owned_short_circuit(self):
        # Mark all tracks owned in a single snapshot
        items = []
        ev = {}
        for i in [1, 2]:
            p = f'/media/Music/Artist X/Album Title/{i}.flac'
            items.append({
                'ServerId': 'srv',
                'Id': f'local-{i}',
                'Path': p,
                'Name': f'Track {i}',
                'Artists': ['Artist X'],
                'Album': 'Album Title',
                'IndexNumber': i,
                'ParentIndexNumber': 1,
                'RunTimeTicks': 1800000000 if i == 1 else 2000000000
            })
            ev[p] = {'category': 'verified_identity', 'identifiers': {'recording': [f'rec-edition-1-{i}']}}
        self.c.sync(items, ev)

        self.assertEqual(self.c.album('edition-1')['ownership'], 'full')
        # Submitting request should immediately mark available
        req = self.dispatcher.submit_request('edition-1')
        self.assertEqual(req['state'], 'available')
        self.assertEqual(req['progress'], 1.0)
        # Lidarr should not have been called
        self.assertEqual(len(self.lidarr.commands), 0)

    def test_dry_run_mode(self):
        dry_dispatcher = AcquisitionDispatcher(
            self.c,
            dispatch_enabled=True,
            dry_run=True,
            lidarr_client=self.lidarr,
            slskd_client=self.slskd
        )
        req = dry_dispatcher.submit_request('edition-1')
        self.assertEqual(req['state'], 'queued')
        self.assertEqual(len(self.lidarr.commands), 0)

    def test_full_lifecycle_progression(self):
        # 1. Submit request -> dispatched to Lidarr
        req = self.dispatcher.submit_request('edition-1')
        self.assertEqual(req['state'], 'dispatched')
        self.assertEqual(req['backend_id'], '201')
        self.assertEqual(len(self.lidarr.commands), 1)

        # 2. Simulate transfer starting in SLSKD -> downloading
        self.slskd.downloads = [{
            'username': 'Barnalks',
            'directories': [{
                'directory': 'Artist X - Album Title',
                'files': [{'state': 'Completed, Succeeded'}, {'state': 'Downloading'}]
            }]
        }]
        self.dispatcher.poll_lifecycle()
        updated_req = self.dispatcher.get_request(req['id'])
        self.assertEqual(updated_req['state'], 'downloading')
        self.assertEqual(updated_req['progress'], 0.5)

        # 3. Simulate Lidarr import completion -> imported
        for a in self.lidarr.albums:
            if a['id'] == 201:
                a['statistics'] = {'percentOfTracks': 100, 'trackFileCount': 2}
        self.slskd.downloads = []
        self.dispatcher.poll_lifecycle()
        updated_req = self.dispatcher.get_request(req['id'])
        self.assertEqual(updated_req['state'], 'imported')

        # 4. Simulate Jellyfin indexing files -> available
        items = []
        ev = {}
        for i in [1, 2]:
            p = f'/media/Music/Artist X/Album Title/{i}.flac'
            items.append({
                'ServerId': 'srv',
                'Id': f'jf-local-{i}',
                'Path': p,
                'Name': f'Track {i}',
                'Artists': ['Artist X'],
                'Album': 'Album Title',
                'IndexNumber': i,
                'ParentIndexNumber': 1,
                'RunTimeTicks': 1800000000 if i == 1 else 2000000000
            })
            ev[p] = {'category': 'verified_identity', 'identifiers': {'recording': [f'rec-edition-1-{i}']}}
        self.c.sync(items, ev)

        self.dispatcher.poll_lifecycle()
        updated_req = self.dispatcher.get_request(req['id'])
        self.assertEqual(updated_req['state'], 'available')
        self.assertEqual(updated_req['progress'], 1.0)

    def test_dispatch_exact_mbid_match(self):
        # Album in Lidarr has foreignAlbumId matching MB release group
        self.lidarr.albums = [
            {'id': 301, 'artistId': 101, 'title': 'Some Different Title', 'foreignAlbumId': 'group-1', 'monitored': False, 'statistics': {}},
            {'id': 302, 'artistId': 101, 'title': 'Album Title', 'foreignAlbumId': 'other-group', 'monitored': False, 'statistics': {}}
        ]
        req = self.dispatcher.submit_request('edition-1')
        self.assertEqual(req['state'], 'dispatched')
        self.assertEqual(req['backend_id'], '301')

    def test_dispatch_nested_release_mbid_match(self):
        # Album in Lidarr matches via nested release foreignReleaseId
        self.lidarr.albums = [
            {
                'id': 401, 'artistId': 101, 'title': 'Album Title Box Set',
                'foreignAlbumId': 'unrelated-group',
                'releases': [{'id': 901, 'foreignReleaseId': 'edition-1', 'title': 'Album Title'}],
                'monitored': False, 'statistics': {}
            }
        ]
        req = self.dispatcher.submit_request('edition-1')
        self.assertEqual(req['state'], 'dispatched')
        self.assertEqual(req['backend_id'], '401')

    def test_dispatch_ambiguous_candidate_refusal(self):
        # Two albums with same title and no matching MBID
        self.lidarr.albums = [
            {'id': 501, 'artistId': 101, 'title': 'Album Title', 'foreignAlbumId': 'non-matching-1', 'monitored': False, 'statistics': {}},
            {'id': 502, 'artistId': 101, 'title': 'Album Title', 'foreignAlbumId': 'non-matching-2', 'monitored': False, 'statistics': {}}
        ]
        req = self.dispatcher.submit_request('edition-1')
        self.assertEqual(req['state'], 'failed')
        self.assertIn('Ambiguous album identity', req.get('failure_reason', ''))

    def test_dispatch_substring_title_rejected(self):
        # Only substring title present (e.g. Deluxe Edition) without MBID
        self.lidarr.albums = [
            {'id': 601, 'artistId': 101, 'title': 'Album Title (Deluxe Remaster)', 'foreignAlbumId': 'non-matching', 'monitored': False, 'statistics': {}}
        ]
        req = self.dispatcher.submit_request('edition-1')
        # Substring should not match exact title "Album Title"
        self.assertNotEqual(req['state'], 'dispatched')

    def test_soulseek_requires_artist_and_album(self):
        req = self.dispatcher.submit_request('edition-1')
        self.assertEqual(req['state'], 'dispatched')

        # Download from a different artist with matching album title should NOT match
        self.slskd.downloads = [{
            'username': 'OtherUser',
            'directories': [{
                'directory': 'Artist Y - Album Title',
                'files': [{'state': 'Downloading'}]
            }]
        }]
        self.dispatcher.poll_lifecycle()
        req_check = self.dispatcher.get_request(req['id'])
        self.assertEqual(req_check['state'], 'dispatched')

        # Download with both artist and album matches
        self.slskd.downloads = [{
            'username': 'OtherUser',
            'directories': [{
                'directory': 'Artist X - Album Title [FLAC]',
                'files': [{'state': 'Downloading'}]
            }]
        }]
        self.dispatcher.poll_lifecycle()
        req_check = self.dispatcher.get_request(req['id'])
        self.assertEqual(req_check['state'], 'downloading')

    def test_no_imported_if_zero_track_files(self):
        req = self.dispatcher.submit_request('edition-1')
        for a in self.lidarr.albums:
            if a['id'] == 201:
                # 100% percentOfTracks but 0 track files (e.g. empty stub)
                a['statistics'] = {'percentOfTracks': 100, 'trackFileCount': 0}
        self.dispatcher.poll_lifecycle()
        req_check = self.dispatcher.get_request(req['id'])
        # Should not have transitioned to imported
        self.assertNotEqual(req_check['state'], 'imported')

    def test_recovery_after_restart(self):
        # Create a dispatched request in DB
        self.c.db.execute("""
            INSERT INTO requests(release_id, scope, state, origin, backend_id, created_at, updated_at)
            VALUES ('edition-1', 'album', 'dispatched', 'explicit_user', '201', ?, ?)
        """, (time.time() - 100, time.time() - 50))
        self.c.db.commit()

        # New dispatcher instance simulating restart
        new_dispatcher = AcquisitionDispatcher(
            self.c,
            dispatch_enabled=True,
            lidarr_client=self.lidarr,
            slskd_client=self.slskd
        )
        active = new_dispatcher.get_active_requests()
        self.assertEqual(len(active), 1)
        self.assertEqual(active[0]['state'], 'dispatched')

if __name__ == '__main__':
    unittest.main()
