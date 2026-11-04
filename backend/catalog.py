"""Persistent catalog identity graph and conservative local availability."""
import hashlib, json, sqlite3, time, unicodedata

SCHEMA = '''
PRAGMA journal_mode=WAL;
CREATE TABLE IF NOT EXISTS artists(id TEXT PRIMARY KEY, name TEXT);
CREATE TABLE IF NOT EXISTS release_groups(id TEXT PRIMARY KEY, title TEXT, primary_type TEXT, first_date TEXT, secondary_types TEXT);
CREATE TABLE IF NOT EXISTS releases(id TEXT PRIMARY KEY, group_id TEXT, title TEXT);
CREATE TABLE IF NOT EXISTS recordings(id TEXT PRIMARY KEY, title TEXT, duration_ms INTEGER);
CREATE TABLE IF NOT EXISTS release_tracks(id TEXT PRIMARY KEY, release_id TEXT, recording_id TEXT, disc INTEGER, position INTEGER, title TEXT, duration_ms INTEGER);
CREATE TABLE IF NOT EXISTS credits(entity_type TEXT, entity_id TEXT, artist_id TEXT, position INTEGER, display_name TEXT, joinphrase TEXT, PRIMARY KEY(entity_type, entity_id, position));
CREATE TABLE IF NOT EXISTS local_items(server_id TEXT, item_id TEXT, path TEXT, payload TEXT, payload_hash TEXT, active INTEGER, PRIMARY KEY(server_id, item_id));
CREATE TABLE IF NOT EXISTS mappings(server_id TEXT, item_id TEXT, recording_id TEXT, release_track_id TEXT, confidence TEXT, evidence TEXT, PRIMARY KEY(server_id, item_id, recording_id));
CREATE TABLE IF NOT EXISTS requests(id INTEGER PRIMARY KEY, release_id TEXT, scope TEXT, state TEXT, origin TEXT, backend_id TEXT, created_at REAL);
CREATE TABLE IF NOT EXISTS http_cache(url TEXT PRIMARY KEY, status INTEGER, payload TEXT, fetched_at REAL, retry_at REAL);
CREATE TABLE IF NOT EXISTS sync_runs(id INTEGER PRIMARY KEY, started REAL, completed REAL, item_count INTEGER);
CREATE TABLE IF NOT EXISTS search_hits(query TEXT, kind TEXT, id TEXT, position INTEGER, PRIMARY KEY(query, kind, id));
'''

def norm(s):
    return ' '.join(unicodedata.normalize('NFKC', s or '').casefold().split())

class Catalog:
    def __init__(self, path):
        self.db = sqlite3.connect(path, timeout=30.0)
        self.db.row_factory = sqlite3.Row
        self.db.execute("PRAGMA busy_timeout = 30000;")
        self.db.executescript(SCHEMA)
        self._ensure_columns()

    def _ensure_columns(self):
        rg_cols = {c[1] for c in self.db.execute("PRAGMA table_info(release_groups)").fetchall()}
        if 'secondary_types' not in rg_cols:
            try:
                self.db.execute('ALTER TABLE release_groups ADD COLUMN secondary_types TEXT')
            except sqlite3.OperationalError:
                pass

        art_cols = {c[1] for c in self.db.execute("PRAGMA table_info(artists)").fetchall()}
        needed_art = {
            'disambiguation': 'TEXT',
            'type': 'TEXT',
            'country': 'TEXT',
            'image_url': 'TEXT',
            'banner_url': 'TEXT',
            'bio': 'TEXT',
            'genres': 'TEXT'
        }
        for col, col_type in needed_art.items():
            if col not in art_cols:
                try:
                    self.db.execute(f'ALTER TABLE artists ADD COLUMN {col} {col_type}')
                except sqlite3.OperationalError:
                    pass
        self.db.commit()

    def credits(self, kind, ident, values):
        self.db.execute('DELETE FROM credits WHERE entity_type=? AND entity_id=?', (kind, ident))
        for i, v in enumerate(values or []):
            a = v.get('artist', {})
            aid = a.get('id')
            if not aid:
                continue
            self.db.execute('INSERT INTO artists(id, name) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET name=excluded.name', (aid, a.get('name', v.get('name', ''))))
            self.db.execute('INSERT INTO credits VALUES(?,?,?,?,?,?)', (kind, ident, aid, i, v.get('name', a.get('name', '')), v.get('joinphrase', '')))

    def get_credits(self, entity_type, entity_id):
        rows = self.db.execute("SELECT artist_id, display_name, joinphrase FROM credits WHERE entity_type=? AND entity_id=? ORDER BY position", (entity_type, entity_id)).fetchall()
        credits_list = []
        display_parts = []
        for r in rows:
            name = r['display_name'] or ''
            joinphrase = r['joinphrase'] or ''
            credits_list.append({'artist_id': r['artist_id'], 'name': name, 'joinphrase': joinphrase})
            display_parts.append(name + joinphrase)
        return credits_list, ''.join(display_parts).strip()

    def reconcile_release(self, release_id):
        release = self.db.execute('SELECT * FROM releases WHERE id=?', (release_id,)).fetchone()
        if not release:
            return
        r_tracks = self.db.execute('SELECT * FROM release_tracks WHERE release_id=?', (release_id,)).fetchall()
        if not r_tracks:
            return
        unmapped = [t for t in r_tracks if not self.db.execute("SELECT 1 FROM mappings WHERE recording_id=? AND confidence='verified'", (t['recording_id'],)).fetchone()]
        if not unmapped:
            return
        candidates = []
        title = release['title']
        group_id = release['group_id']
        query = '''
            SELECT server_id, item_id, payload 
            FROM local_items 
            WHERE active=1 AND (
                payload LIKE ? 
                OR payload LIKE ? 
                OR payload LIKE ? 
                OR path LIKE ? 
                OR path LIKE ?
            )
        '''
        params = (
            f'%"Album": "%{title}%',
            f'%"{release_id}"%',
            f'%"{group_id}"%' if group_id else f'%"{release_id}"%',
            f'%/{title} %/%',
            f'%/{title}/%',
        )
        for row in self.db.execute(query, params).fetchall():
            candidates.append((row['server_id'], row['item_id'], json.loads(row['payload'])))
        to_insert = []
        for t in unmapped:
            rec_id = t['recording_id']
            matched = False
            for srv_id, it_id, d in candidates:
                disc = d.get('ParentIndexNumber') or 1
                pos = d.get('IndexNumber') or 0
                if disc == t['disc'] and pos == t['position']:
                    dur_ms = int(d.get('RunTimeTicks', 0) / 10000)
                    if norm(d.get('Name')) == norm(t['title']) or (not t['duration_ms'] or abs(dur_ms - t['duration_ms']) <= 4000):
                        to_insert.append((srv_id, it_id, rec_id, t['id'], 'verified', json.dumps({'reason': 'verified by album track position and duration'})))
                        matched = True
                        break
            if not matched:
                row = self.db.execute("SELECT server_id, item_id FROM local_items WHERE active=1 AND (payload LIKE ? OR payload LIKE ?) LIMIT 1",
                    (f'%"MusicBrainzTrack": "{rec_id}"%', f'%"musicbrainz_trackid": ["{rec_id}"]%')).fetchone()
                if row:
                    to_insert.append((row['server_id'], row['item_id'], rec_id, t['id'], 'verified', json.dumps({'reason': 'verified by MusicBrainzTrack hint'})))
        if to_insert:
            with self.db:
                self.db.executemany('INSERT OR REPLACE INTO mappings VALUES(?,?,?,?,?,?)', to_insert)

    def release(self, r):
        group = r.get('release-group', {})
        gid = group.get('id')
        if gid:
            sec = json.dumps(group.get('secondary-types') or [])
            self.db.execute('''
                INSERT INTO release_groups(id, title, primary_type, first_date, secondary_types)
                VALUES(?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET
                    title=excluded.title,
                    primary_type=COALESCE(excluded.primary_type, release_groups.primary_type),
                    first_date=COALESCE(excluded.first_date, release_groups.first_date),
                    secondary_types=COALESCE(excluded.secondary_types, release_groups.secondary_types)
            ''', (gid, group.get('title', r.get('title')), group.get('primary-type'), group.get('first-release-date'), sec))
            if group.get('artist-credit'):
                self.credits('group', gid, group['artist-credit'])
        self.db.execute('INSERT OR REPLACE INTO releases VALUES(?,?,?)', (r['id'], gid, r.get('title')))
        self.credits('release', r['id'], r.get('artist-credit'))
        if gid and not group.get('artist-credit'):
            self.credits('group', gid, r.get('artist-credit'))
        for medium in r.get('media', []):
            for t in medium.get('tracks', []):
                rec = t.get('recording', {})
                rid = rec.get('id')
                if not rid:
                    continue
                self.db.execute('INSERT OR REPLACE INTO recordings VALUES(?,?,?)', (rid, rec.get('title', t.get('title')), rec.get('length', t.get('length'))))
                self.db.execute('INSERT OR REPLACE INTO release_tracks VALUES(?,?,?,?,?,?,?)', (t['id'], r['id'], rid, medium['position'], t['position'], t.get('title'), t.get('length', rec.get('length'))))
                self.credits('recording', rid, rec.get('artist-credit') or t.get('artist-credit'))
        self.reconcile_release(r['id'])

    def sync(self, items, evidence):
        """Complete API snapshot; only changed payloads rewritten; stale items deactivated."""
        with self.db:
            run = self.db.execute('INSERT INTO sync_runs(started) VALUES(?)', (time.time(),)).lastrowid
            seen = set()
            servers = set()
            if not items:
                known = [r[0] for r in self.db.execute('SELECT DISTINCT server_id FROM local_items')]
                if len(known) > 1:
                    raise ValueError('empty multi-server snapshot requires explicit source scope')
                servers.update(known)
            for item in items:
                server = item['ServerId']
                ident = item['Id']
                servers.add(server)
                seen.add((server, ident))
                payload = json.dumps(item, sort_keys=True)
                digest = hashlib.sha256(payload.encode()).hexdigest()
                self.db.execute('INSERT INTO local_items VALUES(?,?,?,?,?,1) ON CONFLICT(server_id,item_id) DO UPDATE SET path=excluded.path,payload=excluded.payload,payload_hash=excluded.payload_hash,active=1 WHERE payload_hash!=excluded.payload_hash OR active=0', (server, ident, item.get('Path'), payload, digest))
                self.db.execute('DELETE FROM mappings WHERE server_id=? AND item_id=?', (server, ident))
                ev = evidence.get(item.get('Path'), {})
                ids = ev.get('identifiers', {})
                rid = (ids.get('recording') or [None])[0]
                if ev.get('category') == 'verified_identity' and rid:
                    self.db.execute('INSERT OR REPLACE INTO mappings VALUES(?,?,?,?,?,?)', (server, ident, rid, ev.get('release_track'), 'verified', json.dumps(ev)))
                elif ev.get('category') == 'ambiguous' and rid:
                    self.db.execute('INSERT OR REPLACE INTO mappings VALUES(?,?,?,?,?,?)', (server, ident, rid, ev.get('release_track'), 'ambiguous', json.dumps(ev)))
                else:
                    rel = (ids.get('release') or [None])[0]
                    if rel:
                        for tr in self.db.execute('SELECT * FROM release_tracks WHERE release_id=? AND disc=? AND position=?', (rel, item.get('ParentIndexNumber') or 1, item.get('IndexNumber') or 0)).fetchall():
                            credit = [x[0] for x in self.db.execute("SELECT display_name FROM credits WHERE entity_type='recording' AND entity_id=? ORDER BY position", (tr['recording_id'],))]
                            duration = item.get('RunTimeTicks', 0) / 10000
                            if norm(item.get('Name')) == norm(tr['title']) and credit and {norm(x) for x in item.get('Artists', [])} == {norm(x) for x in credit} and tr['duration_ms'] and abs(duration - tr['duration_ms']) <= 2000:
                                self.db.execute('INSERT OR REPLACE INTO mappings VALUES(?,?,?,?,?,?)', (server, ident, tr['recording_id'], tr['id'], 'ambiguous', json.dumps({'reason': 'exact context secondary candidate; recording identity not yet verified'})))
                    local_id = 'local:' + server + ':' + ident
                    self.db.execute('INSERT OR REPLACE INTO recordings VALUES(?,?,?)', (local_id, item.get('Name'), int(item.get('RunTimeTicks', 0) / 10000)))
                    self.db.execute('INSERT OR REPLACE INTO mappings VALUES(?,?,?,?,?,?)', (server, ident, local_id, None, 'local_identity', json.dumps({'reason': 'playable Jellyfin identity; no public catalog equivalence claimed'})))
            for server in servers:
                for row in self.db.execute('SELECT item_id FROM local_items WHERE server_id=? AND active=1', (server,)).fetchall():
                    if (server, row[0]) not in seen:
                        self.db.execute('UPDATE local_items SET active=0 WHERE server_id=? AND item_id=?', (server, row[0]))
            self.db.execute('UPDATE sync_runs SET completed=?,item_count=? WHERE id=?', (time.time(), len(items), run))
            for request in self.db.execute("SELECT id,release_id FROM requests WHERE state NOT IN ('failed','available')").fetchall():
                album = self.album(request['release_id'])
                if album and album['ownership'] == 'full':
                    self.db.execute("UPDATE requests SET state='available' WHERE id=?", (request['id'],))

    def availability(self, recording_id, release_id=None):
        rows = self.db.execute('SELECT m.*,l.payload FROM mappings m JOIN local_items l USING(server_id,item_id) WHERE recording_id=? AND active=1', (recording_id,)).fetchall()
        exact = [r for r in rows if r['confidence'] in ('verified', 'local_identity')]
        state = 'available' if exact else 'possibly_available' if rows else 'not_found'
        pending = False
        if release_id:
            pending = bool(self.db.execute("SELECT 1 FROM requests WHERE release_id=? AND state NOT IN ('failed','available')", (release_id,)).fetchone())
        else:
            pending = bool(self.db.execute("SELECT 1 FROM requests q JOIN release_tracks t ON q.release_id=t.release_id WHERE t.recording_id=? AND q.state NOT IN ('failed','available')", (recording_id,)).fetchone())
        if state == 'not_found' and pending:
            state = 'pending'
        return {
            'state': state,
            'acquisition_pending': pending,
            'local_items': [{'server_id': r['server_id'], 'item_id': r['item_id']} for r in exact],
            'playable_item_id': exact[0]['item_id'] if len(exact) == 1 else None,
            'selection_required': len(exact) > 1,
            'candidate_count': len(rows)
        }

    def album(self, release_id):
        self.reconcile_release(release_id)
        release = self.db.execute('SELECT * FROM releases WHERE id=?', (release_id,)).fetchone()
        if not release:
            return None
        tracks = []
        for t in self.db.execute('SELECT * FROM release_tracks WHERE release_id=? ORDER BY disc,position', (release_id,)):
            row = dict(t)
            row['availability'] = self.availability(t['recording_id'], release_id)
            c_list, disp = self.get_credits('recording', t['recording_id'])
            row['artist_credit'] = c_list
            row['display_artist'] = disp
            tracks.append(row)
        available = sum(t['availability']['state'] == 'available' for t in tracks)
        
        c_list, disp = self.get_credits('release', release_id)
        if not c_list and release['group_id']:
            c_list, disp = self.get_credits('group', release['group_id'])
            
        gid = release['group_id']
        image_url = f"https://coverartarchive.org/release-group/{gid}/front-250" if gid else f"https://coverartarchive.org/release/{release_id}/front-250"
        release_image_url = f"https://coverartarchive.org/release/{release_id}/front-250"
        
        return {
            **dict(release),
            'tracks': tracks,
            'owned_tracks': available,
            'total_tracks': len(tracks),
            'ownership': 'full' if tracks and available == len(tracks) else 'partial' if available else 'none',
            'artist_credit': c_list,
            'display_artist': disp,
            'image_url': image_url,
            'release_image_url': release_image_url,
            'group_image_url': image_url
        }

    def group_ownership(self, group_id):
        releases = self.db.execute('SELECT id FROM releases WHERE group_id=?', (group_id,)).fetchall()
        if not releases:
            return 'none'
        has_partial = False
        for rel in releases:
            rel_id = rel['id']
            tracks = self.db.execute('SELECT id, recording_id FROM release_tracks WHERE release_id=?', (rel_id,)).fetchall()
            if not tracks:
                continue
            total_tracks = len(tracks)
            owned_tracks = self.db.execute('''
                SELECT count(DISTINCT rt.id)
                FROM release_tracks rt
                JOIN mappings m ON m.recording_id = rt.recording_id AND m.confidence IN ('verified', 'local_identity')
                JOIN local_items l ON l.server_id = m.server_id AND l.item_id = m.item_id
                WHERE rt.release_id = ? AND l.active = 1
            ''', (rel_id,)).fetchone()[0]
            if owned_tracks == total_tracks and total_tracks > 0:
                return 'full'
            elif owned_tracks > 0:
                has_partial = True
        return 'partial' if has_partial else 'none'

    def group(self, group_id):
        group = self.db.execute('SELECT * FROM release_groups WHERE id=?', (group_id,)).fetchone()
        if not group:
            return None
        g_dict = dict(group)
        st_raw = g_dict.get('secondary_types')
        try:
            g_dict['secondary_types'] = json.loads(st_raw) if st_raw else []
        except Exception:
            g_dict['secondary_types'] = []

        editions = [self.album(r[0]) for r in self.db.execute('SELECT id FROM releases WHERE group_id=?', (group_id,))]
        c_list, disp = self.get_credits('group', group_id)
        
        # Sort editions: preferred (most owned tracks, most tracks) first
        editions.sort(key=lambda ed: (
            -ed.get('owned_tracks', 0),
            -len(ed.get('tracks', [])),
            ed.get('title', '')
        ))
        
        ownership = self.group_ownership(group_id)
        image_url = f"https://coverartarchive.org/release-group/{group_id}/front-250"
        
        return {
            **g_dict,
            'editions': editions,
            'artist_credit': c_list,
            'display_artist': disp,
            'ownership': ownership,
            'image_url': image_url
        }

    def search(self, q):
        results = []
        for table, kind in [('artists', 'artist'), ('release_groups', 'album'), ('recordings', 'track')]:
            column = 'name' if kind == 'artist' else 'title'
            for r in self.db.execute('SELECT * FROM ' + table + ' WHERE ' + column + ' LIKE ? OR id IN (SELECT id FROM search_hits WHERE query=? AND kind=?) LIMIT 25', ('%' + q + '%', norm(q), kind)):
                row = dict(r)
                row['kind'] = kind
                if kind == 'track':
                    row['availability'] = self.availability(r['id'])
                    c_list, disp = self.get_credits('recording', r['id'])
                    row['artist_credit'] = c_list
                    row['display_artist'] = disp
                elif kind == 'album':
                    row['edition_ids'] = [x[0] for x in self.db.execute('SELECT id FROM releases WHERE group_id=?', (r['id'],))]
                    row['image_url'] = f"https://coverartarchive.org/release-group/{r['id']}/front-250"
                    c_list, disp = self.get_credits('group', r['id'])
                    row['artist_credit'] = c_list
                    row['display_artist'] = disp
                    
                    st_raw = r['secondary_types'] if 'secondary_types' in r.keys() else None
                    try:
                        row['secondary_types'] = json.loads(st_raw) if st_raw else []
                    except Exception:
                        row['secondary_types'] = []
                        
                    row['ownership'] = self.group_ownership(r['id'])
                elif kind == 'artist':
                    row['artist_credit'] = [{'artist_id': r['id'], 'name': r['name'], 'joinphrase': ''}]
                    row['display_artist'] = r['name']
                results.append(row)
        return results

    def representative_release_for_recording(self, recording_id):
        """Return one deterministic, artwork-capable release for a recording.

        A recording may occur on an original album, later editions, singles, and
        compilations.  This deliberately chooses presentation artwork only; it
        never changes the availability result used for playback.
        """
        rows = self.db.execute('''
            SELECT rt.release_id, rel.group_id, rel.title AS release_title,
                   g.primary_type, g.first_date, g.secondary_types,
                   m.item_id, li.payload
            FROM release_tracks rt
            JOIN releases rel ON rel.id = rt.release_id
            LEFT JOIN release_groups g ON g.id = rel.group_id
            LEFT JOIN mappings m ON m.release_track_id = rt.id
                AND m.recording_id = rt.recording_id
                AND m.confidence IN ('verified', 'local_identity')
            LEFT JOIN local_items li ON li.server_id = m.server_id
                AND li.item_id = m.item_id AND li.active = 1
            WHERE rt.recording_id = ?
        ''', (recording_id,)).fetchall()

        def has_artwork(payload):
            if not payload:
                return False
            try:
                item = json.loads(payload)
            except (TypeError, json.JSONDecodeError):
                return False
            tags = item.get('ImageTags') or {}
            return bool(tags.get('Primary') or item.get('AlbumPrimaryImageTag') or item.get('ParentPrimaryImageTag'))

        def release_rank(row):
            try:
                secondary = json.loads(row['secondary_types'] or '[]')
            except (TypeError, json.JSONDecodeError):
                secondary = []
            secondary = {str(value).casefold() for value in secondary}
            primary = (row['primary_type'] or '').casefold()
            title = (row['release_title'] or '').casefold()
            is_studio_album = primary == 'album' and not secondary.intersection({
                'compilation', 'live', 'remix', 'dj-mix', 'soundtrack',
            })
            is_reissue = any(word in title for word in (
                'remaster', 'remastered', 'reissue', 'deluxe', 'expanded', 'anniversary',
            ))
            if is_studio_album and not is_reissue:
                category = 0
            elif is_studio_album:
                category = 1
            elif primary in ('single', 'ep'):
                category = 2
            elif 'compilation' in secondary:
                category = 3
            else:
                category = 4
            # A known Jellyfin image is the only artwork validity signal already
            # in the catalog. Within that set, follow the release hierarchy.
            # The stable date/title/id keys make all ties repeatable.
            return (
                0 if has_artwork(row['payload']) else 1,
                category,
                row['first_date'] or '9999-12-31',
                row['release_title'] or '',
                row['release_id'],
                row['item_id'] or '',
            )

        if not rows:
            return None
        selected = min(rows, key=release_rank)
        group_id = selected['group_id']
        return {
            'release_id': selected['release_id'],
            'image_url': (
                f'https://coverartarchive.org/release-group/{group_id}/front-250'
                if group_id else f"https://coverartarchive.org/release/{selected['release_id']}/front-250"
            ),
            'artwork_item_id': selected['item_id'] if has_artwork(selected['payload']) else None,
        }

    def artist(self, artist_id):
        artist = self.db.execute('SELECT * FROM artists WHERE id=?', (artist_id,)).fetchone()
        if not artist:
            return None
            
        raw_groups = [dict(x) for x in self.db.execute("""
            SELECT DISTINCT g.* 
            FROM release_groups g 
            JOIN credits c ON c.entity_id=g.id 
            WHERE c.entity_type='group' AND c.artist_id=?
            ORDER BY g.first_date ASC
        """, (artist_id,))]
        
        groups = []
        for g in raw_groups:
            gid = g['id']
            pt = g.get('primary_type') or 'Other'
            st_raw = g.get('secondary_types')
            try:
                st = json.loads(st_raw) if st_raw else []
            except Exception:
                st = []
                
            if pt == 'Album' and not st:
                if g.get('first_date'):
                    cat = 'album'
                else:
                    cat = 'other'
            elif pt == 'EP':
                cat = 'ep'
            elif pt == 'Single':
                cat = 'single'
            elif 'Compilation' in st:
                cat = 'compilation'
            elif 'Live' in st:
                cat = 'live'
            else:
                cat = 'other'
                
            ownership = self.group_ownership(gid)
            edition_ids = [x[0] for x in self.db.execute('SELECT id FROM releases WHERE group_id=?', (gid,))]
            c_list, disp = self.get_credits('group', gid)
            
            groups.append({
                'id': gid,
                'title': g['title'],
                'primary_type': pt,
                'secondary_types': st,
                'category': cat,
                'first_date': g.get('first_date'),
                'ownership': ownership,
                'edition_ids': edition_ids,
                'image_url': f"https://coverartarchive.org/release-group/{gid}/front-250",
                'artist_credit': c_list,
                'display_artist': disp,
                'kind': 'album'
            })
            
        cat_order = {'album': 0, 'ep': 1, 'single': 2, 'compilation': 3, 'live': 4, 'other': 5}
        groups.sort(key=lambda x: (cat_order.get(x['category'], 99), x.get('first_date') or '9999'))
        
        # Owned / available recordings for this artist
        recordings = []
        rec_rows = self.db.execute("""
            SELECT DISTINCT r.* 
            FROM recordings r 
            JOIN credits c ON c.entity_id=r.id 
            JOIN mappings m ON m.recording_id=r.id AND m.confidence IN ('verified', 'local_identity')
            JOIN local_items l ON l.server_id=m.server_id AND l.item_id=m.item_id AND l.active=1
            WHERE c.entity_type='recording' AND c.artist_id=?
            ORDER BY r.title COLLATE NOCASE, r.id
        """, (artist_id,)).fetchall()
        for r in rec_rows:
            rec = dict(r)
            rec['availability'] = self.availability(r['id'])
            representative = self.representative_release_for_recording(r['id'])
            if representative:
                rec.update(representative)
            rec['kind'] = 'track'
            c_list, disp = self.get_credits('recording', r['id'])
            rec['artist_credit'] = c_list
            rec['display_artist'] = disp
            recordings.append(rec)
            
        artist_data = dict(artist)
        if 'genres' in artist_data and artist_data['genres']:
            try:
                artist_data['genres'] = json.loads(artist_data['genres']) if isinstance(artist_data['genres'], str) else artist_data['genres']
            except Exception:
                artist_data['genres'] = []
        else:
            artist_data['genres'] = []

        if not artist_data.get('image_url') and groups:
            artist_data['image_url'] = groups[0].get('image_url')

        return {**artist_data, 'albums': groups, 'recordings': recordings}

    def resolve_artist(self, item_id=None, jellyfin_id=None, name=None):
        """
        Deterministically resolve a Jellyfin item ID, track ID, album ID, MusicBrainz ID,
        or artist name to a canonical MusicBrainz artist identity for navigation.
        Ambiguous names (multiple catalog artists with the same name) never resolve to a single artist.
        """
        target_id = item_id or jellyfin_id

        # 1. Direct MusicBrainz artist ID
        if target_id:
            art = self.db.execute('SELECT * FROM artists WHERE id=?', (target_id,)).fetchone()
            if art:
                return {'id': art['id'], 'artist_id': art['id'], 'name': art['name'], 'item_id': target_id, 'confidence': 'direct_mbid'}

            # 2. Local item (track) by Jellyfin ItemId
            loc = self.db.execute('SELECT server_id, item_id, payload FROM local_items WHERE item_id=?', (target_id,)).fetchone()
            if loc:
                try:
                    payload = json.loads(loc['payload'])
                except Exception:
                    payload = {}

                # A. Check ProviderIds for MusicBrainzArtist or MusicBrainzAlbumArtist
                pids = payload.get('ProviderIds') or {}
                mb_artist = pids.get('MusicBrainzArtist') or pids.get('MusicBrainzAlbumArtist')
                if mb_artist:
                    art = self.db.execute('SELECT name FROM artists WHERE id=?', (mb_artist,)).fetchone()
                    if art:
                        art_name = art['name']
                        if not name or art_name.strip().lower() == name.strip().lower():
                            return {'id': mb_artist, 'artist_id': mb_artist, 'name': art_name, 'item_id': target_id, 'confidence': 'verified'}

                # B. Check verified mappings
                m = self.db.execute("SELECT recording_id, confidence FROM mappings WHERE server_id=? AND item_id=?", (loc['server_id'], target_id)).fetchone()
                if m and m['recording_id'] and m['confidence'] in ('verified', 'local_identity'):
                    c = self.db.execute("SELECT c.artist_id, a.name FROM credits c JOIN artists a ON a.id=c.artist_id WHERE c.entity_type='recording' AND c.entity_id=? ORDER BY c.position LIMIT 1", (m['recording_id'],)).fetchone()
                    if c:
                        if not name or c['name'].strip().lower() == name.strip().lower():
                            return {'id': c['artist_id'], 'artist_id': c['artist_id'], 'name': c['name'], 'item_id': target_id, 'confidence': m['confidence']}

                # C. Check ArtistItems / AlbumArtists by exact name match against catalog artists (guarded against ambiguity)
                for k in ('ArtistItems', 'AlbumArtists'):
                    for a in (payload.get(k) or []):
                        aname = a.get('Name')
                        if aname and aname.strip():
                            if name and aname.strip().lower() != name.strip().lower():
                                continue
                            matching = self.db.execute('SELECT id, name FROM artists WHERE lower(name)=lower(?)', (aname.strip(),)).fetchall()
                            if len(matching) == 1:
                                return {'id': matching[0]['id'], 'artist_id': matching[0]['id'], 'name': matching[0]['name'], 'item_id': target_id, 'confidence': 'name_match'}
                            elif len(matching) > 1:
                                return {'id': None, 'artist_id': None, 'name': aname, 'item_id': target_id, 'confidence': 'ambiguous', 'candidates': [dict(m) for m in matching]}

            # 3. ItemId matches a Jellyfin Artist or Album ID nested inside local_items payloads
            loc2 = self.db.execute('SELECT payload FROM local_items WHERE payload LIKE ? LIMIT 1', (f'%"{target_id}"%',)).fetchone()
            if loc2:
                try:
                    payload = json.loads(loc2['payload'])
                    # Find which artist entry actually matches target_id
                    matched_name = None
                    for k in ('ArtistItems', 'AlbumArtists'):
                        for a in (payload.get(k) or []):
                            if a.get('Id') == target_id:
                                matched_name = a.get('Name')
                                break
                        if matched_name:
                            break

                    target_name = name or matched_name

                    pids = payload.get('ProviderIds') or {}
                    mb_artist = pids.get('MusicBrainzArtist') or pids.get('MusicBrainzAlbumArtist')
                    if mb_artist and target_name:
                        art = self.db.execute('SELECT name FROM artists WHERE id=?', (mb_artist,)).fetchone()
                        if art and art['name'].strip().lower() == target_name.strip().lower():
                            return {'id': mb_artist, 'artist_id': mb_artist, 'name': art['name'], 'item_id': target_id, 'confidence': 'verified'}

                    if target_name and target_name.strip():
                        matching = self.db.execute('SELECT id, name FROM artists WHERE lower(name)=lower(?)', (target_name.strip(),)).fetchall()
                        if len(matching) == 1:
                            return {'id': matching[0]['id'], 'artist_id': matching[0]['id'], 'name': matching[0]['name'], 'item_id': target_id, 'confidence': 'name_match'}
                        elif len(matching) > 1:
                            return {'id': None, 'artist_id': None, 'name': target_name, 'item_id': target_id, 'confidence': 'ambiguous', 'candidates': [dict(m) for m in matching]}
                except Exception:
                    pass

        # 4. Name-only resolution (must strictly check for uniqueness; never return first of multiple)
        if name and name.strip():
            matching = self.db.execute('SELECT id, name FROM artists WHERE lower(name)=lower(?)', (name.strip(),)).fetchall()
            if len(matching) == 1:
                return {'id': matching[0]['id'], 'artist_id': matching[0]['id'], 'name': matching[0]['name'], 'confidence': 'name_match'}
            elif len(matching) > 1:
                return {'id': None, 'artist_id': None, 'name': name.strip(), 'confidence': 'ambiguous', 'candidates': [dict(m) for m in matching]}

        return None

    def request(self, release_id, scope='album', origin='explicit_user'):
        if scope != 'album':
            raise ValueError('single-song acquisition is not supported by the current backend')
        if not self.db.execute('SELECT 1 FROM releases WHERE id=?', (release_id,)).fetchone():
            raise ValueError('unknown release')
        row = self.db.execute("SELECT id FROM requests WHERE release_id=? AND state NOT IN ('failed','available')", (release_id,)).fetchone()
        if row:
            return row[0]
        with self.db:
            return self.db.execute('INSERT INTO requests(release_id,scope,state,origin,created_at) VALUES(?,?,?,?,?)', (release_id, scope, 'queued', origin, time.time())).lastrowid
