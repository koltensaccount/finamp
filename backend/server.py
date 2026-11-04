"""Loopback authenticated catalog API; no acquisition dispatch is enabled."""
import argparse, json, os, time, urllib.request, urllib.parse, urllib.error, threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from catalog import Catalog, norm
from acquisition import AcquisitionDispatcher

LAST = 0

def _mb_get(url):
    global LAST
    time.sleep(max(0, 1.1 - (time.monotonic() - LAST)))
    req = urllib.request.Request(url, headers={'User-Agent': 'PersonalMusicCatalog/0.1 (local self-hosted development)'})
    with urllib.request.urlopen(req, timeout=12) as response:
        raw = response.read().decode()
    LAST = time.monotonic()
    return raw, json.loads(raw)

def provider(c, q):
    global LAST
    for kind in ('artist', 'release-group', 'recording'):
        url = 'https://musicbrainz.org/ws/2/' + kind + '?' + urllib.parse.urlencode({'query': q, 'limit': 20, 'fmt': 'json'})
        row = c.db.execute('SELECT * FROM http_cache WHERE url=?', (url,)).fetchone()
        if row and (time.time() - row['fetched_at'] < 86400 or row['retry_at'] > time.time()):
            continue
        try:
            raw, data = _mb_get(url)
            with c.db:
                c.db.execute('INSERT OR REPLACE INTO http_cache VALUES(?,?,?,?,?)', (url, 200, raw, time.time(), 0))
                if kind == 'artist':
                    for i, x in enumerate(data.get('artists', [])):
                        c.db.execute('INSERT INTO artists(id, name) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET name=excluded.name', (x['id'], x['name']))
                        c.db.execute('INSERT OR REPLACE INTO search_hits VALUES(?,?,?,?)', (norm(q), 'artist', x['id'], i))
                elif kind == 'release-group':
                    for i, x in enumerate(data.get('release-groups', [])):
                        sec = json.dumps(x.get('secondary-types') or [])
                        c.db.execute('''
                            INSERT INTO release_groups(id, title, primary_type, first_date, secondary_types)
                            VALUES(?,?,?,?,?)
                            ON CONFLICT(id) DO UPDATE SET
                                title=excluded.title,
                                primary_type=COALESCE(excluded.primary_type, release_groups.primary_type),
                                first_date=COALESCE(excluded.first_date, release_groups.first_date),
                                secondary_types=COALESCE(excluded.secondary_types, release_groups.secondary_types)
                        ''', (x['id'], x['title'], x.get('primary-type'), x.get('first-release-date'), sec))
                        c.credits('group', x['id'], x.get('artist-credit'))
                        c.db.execute('INSERT OR REPLACE INTO search_hits VALUES(?,?,?,?)', (norm(q), 'album', x['id'], i))
                else:
                    for i, x in enumerate(data.get('recordings', [])):
                        c.db.execute('INSERT OR REPLACE INTO recordings VALUES(?,?,?)', (x['id'], x['title'], x.get('length')))
                        c.credits('recording', x['id'], x.get('artist-credit'))
                        c.db.execute('INSERT OR REPLACE INTO search_hits VALUES(?,?,?,?)', (norm(q), 'track', x['id'], i))
        except Exception:
            LAST = time.monotonic()
            with c.db:
                if row:
                    c.db.execute('UPDATE http_cache SET retry_at=? WHERE url=?', (time.time() + 300, url))
                else:
                    c.db.execute('INSERT INTO http_cache VALUES(?,?,?,?,?)', (url, 0, '{}', 0, time.time() + 300))

def fetch_mb_release(c, release_id):
    url = f'https://musicbrainz.org/ws/2/release/{release_id}?inc=artist-credits+recordings+release-groups&fmt=json'
    row = c.db.execute('SELECT * FROM http_cache WHERE url=?', (url,)).fetchone()
    if row and row['status'] == 200:
        try:
            c.release(json.loads(row['payload']))
            c.reconcile_release(release_id)
            return
        except Exception:
            pass
    try:
        raw, data = _mb_get(url)
        with c.db:
            c.db.execute('INSERT OR REPLACE INTO http_cache VALUES(?,?,?,?,?)', (url, 200, raw, time.time(), 0))
            c.release(data)
        c.reconcile_release(release_id)
    except Exception:
        pass

def _hydrate_group_data(c, data):
    gid = data.get('id')
    if not gid:
        return
    sec = json.dumps(data.get('secondary-types') or [])
    c.db.execute('''
        INSERT INTO release_groups(id, title, primary_type, first_date, secondary_types)
        VALUES(?,?,?,?,?)
        ON CONFLICT(id) DO UPDATE SET
            title=excluded.title,
            primary_type=COALESCE(excluded.primary_type, release_groups.primary_type),
            first_date=COALESCE(excluded.first_date, release_groups.first_date),
            secondary_types=COALESCE(excluded.secondary_types, release_groups.secondary_types)
    ''', (gid, data.get('title'), data.get('primary-type'), data.get('first-release-date'), sec))
    if data.get('artist-credit'):
        c.credits('group', gid, data['artist-credit'])
    for rel in data.get('releases', []):
        c.db.execute('INSERT OR IGNORE INTO releases VALUES(?,?,?)', (rel['id'], gid, rel.get('title')))
        if rel.get('artist-credit'):
            c.credits('release', rel['id'], rel['artist-credit'])

def fetch_mb_group(c, group_id):
    url = f'https://musicbrainz.org/ws/2/release-group/{group_id}?inc=artists+releases&fmt=json'
    row = c.db.execute('SELECT * FROM http_cache WHERE url=?', (url,)).fetchone()
    if row and row['status'] == 200 and (time.time() - row['fetched_at'] < 86400 * 7):
        try:
            data = json.loads(row['payload'])
            with c.db:
                _hydrate_group_data(c, data)
            return
        except Exception:
            pass
    try:
        raw, data = _mb_get(url)
        with c.db:
            c.db.execute('INSERT OR REPLACE INTO http_cache VALUES(?,?,?,?,?)', (url, 200, raw, time.time(), 0))
            _hydrate_group_data(c, data)
    except Exception:
        pass

def _hydrate_artist_release_groups(c, artist_id, data):
    for rg in data.get('release-groups', []):
        gid = rg['id']
        sec = json.dumps(rg.get('secondary-types') or [])
        c.db.execute('''
            INSERT INTO release_groups(id, title, primary_type, first_date, secondary_types)
            VALUES(?,?,?,?,?)
            ON CONFLICT(id) DO UPDATE SET
                title=excluded.title,
                primary_type=COALESCE(excluded.primary_type, release_groups.primary_type),
                first_date=COALESCE(excluded.first_date, release_groups.first_date),
                secondary_types=COALESCE(excluded.secondary_types, release_groups.secondary_types)
        ''', (gid, rg.get('title'), rg.get('primary-type'), rg.get('first-release-date'), sec))
        if rg.get('artist-credit'):
            c.credits('group', gid, rg['artist-credit'])
        # Guarantee group is credited to this artist
        has_credit = c.db.execute("SELECT 1 FROM credits WHERE entity_type='group' AND entity_id=? AND artist_id=?", (gid, artist_id)).fetchone()
        if not has_credit:
            c.db.execute("INSERT OR IGNORE INTO credits VALUES('group',?,?,?,(SELECT name FROM artists WHERE id=?),'')", (gid, artist_id, 999, artist_id))

def fetch_mb_artist(c, artist_id, force=False):
    # Ensure artist details are present
    artist_row = c.db.execute('SELECT * FROM artists WHERE id=?', (artist_id,)).fetchone()
    has_image = bool(artist_row and 'image_url' in artist_row.keys() and artist_row['image_url'])
    if not artist_row or force or not has_image:
        a_url = f'https://musicbrainz.org/ws/2/artist/{artist_id}?inc=url-rels+tags+genres&fmt=json'
        try:
            _, a_data = _mb_get(a_url)
            name = a_data.get('name') or ''
            art_type = a_data.get('type')
            country = a_data.get('country')
            disambiguation = a_data.get('disambiguation')
            genres = [g['name'] for g in a_data.get('genres', [])]

            relations = a_data.get('relations', [])
            deezer_artist_id = None
            wiki_title = None

            for r in relations:
                rtype = r.get('type')
                rurl = r.get('url', {}).get('resource', '')
                if 'deezer.com/artist/' in rurl:
                    parts = rurl.rstrip('/').split('/')
                    if parts and parts[-1].isdigit():
                        deezer_artist_id = parts[-1]
                elif rtype == 'wikipedia' or 'wikipedia.org/wiki/' in rurl:
                    wiki_title = rurl.split('/wiki/')[-1]
                elif not wiki_title and ('wikidata.org/wiki/Q' in rurl or rtype == 'wikidata'):
                    qid = rurl.split('/')[-1]
                    try:
                        wd_url = f'https://www.wikidata.org/wiki/Special:EntityData/{qid}.json'
                        wd_req = urllib.request.Request(wd_url, headers={'User-Agent': 'PersonalMusicCatalog/0.1'})
                        with urllib.request.urlopen(wd_req, timeout=5) as wd_resp:
                            wd_data = json.loads(wd_resp.read().decode())
                            sitelink = wd_data.get('entities', {}).get(qid, {}).get('sitelinks', {}).get('enwiki', {}).get('title')
                            if sitelink:
                                wiki_title = urllib.parse.quote(sitelink.replace(' ', '_'))
                    except Exception:
                        pass

            # Deezer artist photo
            image_url = None
            if deezer_artist_id:
                try:
                    dz_url = f'https://api.deezer.com/artist/{deezer_artist_id}'
                    dz_req = urllib.request.Request(dz_url, headers={'User-Agent': 'PersonalMusicCatalog/0.1'})
                    with urllib.request.urlopen(dz_req, timeout=5) as dz_resp:
                        dz_data = json.loads(dz_resp.read().decode())
                        image_url = dz_data.get('picture_xl') or dz_data.get('picture_big')
                except Exception:
                    pass

            if not image_url:
                try:
                    dz_url = 'https://api.deezer.com/search/artist?' + urllib.parse.urlencode({'q': f'"{name}"'})
                    dz_req = urllib.request.Request(dz_url, headers={'User-Agent': 'PersonalMusicCatalog/0.1'})
                    with urllib.request.urlopen(dz_req, timeout=5) as dz_resp:
                        dz_data = json.loads(dz_resp.read().decode())
                        dz_items = dz_data.get('data', [])
                        for item in dz_items:
                            if item.get('name', '').strip().lower() == name.strip().lower():
                                image_url = item.get('picture_xl') or item.get('picture_big')
                                break
                except Exception:
                    pass

            # Wikipedia bio
            bio = None
            if not wiki_title:
                wiki_title = urllib.parse.quote(name.replace(' ', '_'))

            try:
                w_url = f'https://en.wikipedia.org/api/rest_v1/page/summary/{wiki_title}'
                w_req = urllib.request.Request(w_url, headers={'User-Agent': 'PersonalMusicCatalog/0.1'})
                with urllib.request.urlopen(w_req, timeout=5) as w_resp:
                    w_data = json.loads(w_resp.read().decode())
                    if w_data.get('type') != 'disambiguation':
                        bio = w_data.get('extract')
                        if not image_url:
                            image_url = w_data.get('thumbnail', {}).get('source')
            except Exception:
                pass

            with c.db:
                c.db.execute('''
                    INSERT INTO artists(id, name, disambiguation, type, country, genres, image_url, bio)
                    VALUES(?,?,?,?,?,?,?,?)
                    ON CONFLICT(id) DO UPDATE SET
                        name=excluded.name,
                        disambiguation=COALESCE(excluded.disambiguation, artists.disambiguation),
                        type=COALESCE(excluded.type, artists.type),
                        country=COALESCE(excluded.country, artists.country),
                        genres=COALESCE(excluded.genres, artists.genres),
                        image_url=COALESCE(excluded.image_url, artists.image_url),
                        bio=COALESCE(excluded.bio, artists.bio)
                ''', (a_data['id'], name, disambiguation, art_type, country, json.dumps(genres), image_url, bio))
            c.db.commit()
        except Exception:
            pass

    offset = 0
    total_count = None
    limit = 100
    max_pages = 5  # up to 500 release groups

    while total_count is None or (offset < total_count and offset < limit * max_pages):
        page_url = f'https://musicbrainz.org/ws/2/release-group?artist={artist_id}&inc=artist-credits&limit={limit}&offset={offset}&fmt=json'
        cached_row = c.db.execute('SELECT * FROM http_cache WHERE url=?', (page_url,)).fetchone()
        if cached_row and cached_row['status'] == 200 and not force and (time.time() - cached_row['fetched_at'] < 86400 * 7):
            try:
                data = json.loads(cached_row['payload'])
                with c.db:
                    _hydrate_artist_release_groups(c, artist_id, data)
                total_count = data.get('release-group-count', 0)
                offset += limit
                continue
            except Exception:
                pass

        try:
            raw, data = _mb_get(page_url)
            with c.db:
                c.db.execute('INSERT OR REPLACE INTO http_cache VALUES(?,?,?,?,?)', (page_url, 200, raw, time.time(), 0))
                _hydrate_artist_release_groups(c, artist_id, data)
            total_count = data.get('release-group-count', 0)
            offset += limit
        except Exception:
            break

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def dispatch(self):
        if self.headers.get('Authorization') != 'Bearer ' + os.environ['CATALOG_API_TOKEN']:
            self.send_error(401)
            return
        route = urllib.parse.urlsplit(self.path)
        c = Catalog(self.server.database)
        try:
            parts = route.path.strip('/').split('/')
            q = urllib.parse.parse_qs(route.query)
            if route.path == '/v1/search':
                text = q.get('q', [''])[0][:200]
                cached_results = c.search(text)
                if not cached_results or q.get('refresh') == ['true']:
                    provider(c, text)
                    cached_results = c.search(text)
                result = {'results': cached_results, 'cached': True}
            elif parts[:2] == ['v1', 'releases'] and len(parts) == 3:
                release_id = parts[2]
                result = c.album(release_id)
                if result is None or not result.get("tracks"):
                    fetch_mb_release(c, release_id)
                    result = c.album(release_id)
            elif parts[:2] == ['v1', 'albums'] and len(parts) == 3:
                group_id = parts[2]
                result = c.group(group_id)
                if result is None or not result.get('editions'):
                    fetch_mb_group(c, group_id)
                    result = c.group(group_id)
                if result and result.get('editions'):
                    has_tracks = any(len(ed.get('tracks', [])) > 0 for ed in result['editions'])
                    if not has_tracks:
                        best_ed = result['editions'][0]
                        for ed in result['editions']:
                            if ed.get('owned_tracks', 0) > 0:
                                best_ed = ed
                                break
                        fetch_mb_release(c, best_ed['id'])
                        result = c.group(group_id)
            elif parts[:2] == ['v1', 'artists'] and len(parts) == 3 and parts[2] == 'resolve':
                item_id = q.get('item_id', [None])[0] or q.get('jellyfin_id', [None])[0]
                name = q.get('name', [None])[0]
                if not item_id and not name:
                    raise ValueError('item_id or name query parameter required')
                result = c.resolve_artist(item_id=item_id, name=name)
                if result is None:
                    self.send_error(404)
                    return
            elif parts[:2] == ['v1', 'artists'] and len(parts) == 3:
                artist_id = parts[2]
                fetch_mb_artist(c, artist_id, force=bool(q.get('refresh') == ['true']))
                result = c.artist(artist_id)
            elif parts[:2] == ['v1', 'recordings'] and len(parts) == 4 and parts[3] == 'availability':
                result = c.availability(parts[2])
            elif route.path == '/v1/requests' and self.command == 'POST':
                size = int(self.headers.get('Content-Length', 0))
                if size > 8192:
                    raise ValueError('request too large')
                body = json.loads(self.rfile.read(size))
                disp = AcquisitionDispatcher(c, dispatch_enabled=getattr(self.server, 'dispatch_enabled', False), dry_run=getattr(self.server, 'dry_run', False))
                result = disp.submit_request(body['release_id'], body.get('scope', 'album'), origin=body.get('origin', 'explicit_user'))
            elif route.path == '/v1/requests' and self.command == 'GET':
                disp = AcquisitionDispatcher(c, dispatch_enabled=getattr(self.server, 'dispatch_enabled', False), dry_run=getattr(self.server, 'dry_run', False))
                result = {'requests': disp.get_all_requests()}
            elif parts[:2] == ['v1', 'requests'] and len(parts) == 3:
                disp = AcquisitionDispatcher(c, dispatch_enabled=getattr(self.server, 'dispatch_enabled', False), dry_run=getattr(self.server, 'dry_run', False))
                try:
                    req_id = int(parts[2])
                    result = disp.get_request(req_id)
                except ValueError:
                    result = None
            else:
                self.send_error(404)
                return

            if result is None:
                self.send_error(404)
                return
            raw = json.dumps(result).encode()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)
        except (ValueError, KeyError, json.JSONDecodeError):
            self.send_error(400)
        finally:
            c.db.close()

    do_GET = dispatch
    do_POST = dispatch

def serve(database, port, dispatch=False, dry_run=False):
    if not os.environ.get('CATALOG_API_TOKEN'):
        raise RuntimeError('CATALOG_API_TOKEN required')
    server = HTTPServer(('127.0.0.1', port), Handler)
    server.database = database
    server.dispatch_enabled = dispatch
    server.dry_run = dry_run
    server.serve_forever()

if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('--database', required=True)
    p.add_argument('--port', type=int, default=8765)
    p.add_argument('--dispatch', action='store_true', default=False)
    p.add_argument('--dry-run', action='store_true', default=False)
    a = p.parse_args()
    serve(a.database, a.port, dispatch=a.dispatch, dry_run=a.dry_run)
