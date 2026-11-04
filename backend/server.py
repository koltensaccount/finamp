"""Loopback authenticated catalog API; no acquisition dispatch is enabled."""
import argparse, hashlib, hmac, json, os, time, urllib.request, urllib.parse, urllib.error, threading
from http.server import BaseHTTPRequestHandler, HTTPServer
try:
    from catalog import Catalog, norm
except ImportError:
    from backend.catalog import Catalog, norm
try:
    from books_core import BooksCore
except ImportError:
    from backend.books_core import BooksCore

LAST = 0

def generate_media_ticket(secret: str, path: str, expires_at: int) -> str:
    message = f"{path}:{expires_at}".encode("utf-8")
    return hmac.new(secret.encode("utf-8"), message, hashlib.sha256).hexdigest()

def verify_auth_and_ticket(headers, path: str, query_params: dict, secret: str) -> bool:
    if not secret:
        return False
    auth = headers.get('Authorization')
    if auth == 'Bearer ' + secret:
        return True

    ticket_list = query_params.get('ticket')
    expires_list = query_params.get('expires')
    if ticket_list and expires_list:
        try:
            expires_at = int(expires_list[0])
            if time.time() <= expires_at:
                expected = generate_media_ticket(secret, path, expires_at)
                if hmac.compare_digest(expected, ticket_list[0]):
                    return True
        except (ValueError, TypeError):
            pass
    return False

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

            # Deezer artist photo
            image_url = None
            try:
                dz_url = 'https://api.deezer.com/search/artist?' + urllib.parse.urlencode({'q': name})
                dz_req = urllib.request.Request(dz_url, headers={'User-Agent': 'PersonalMusicCatalog/0.1'})
                with urllib.request.urlopen(dz_req, timeout=5) as dz_resp:
                    dz_data = json.loads(dz_resp.read().decode())
                    dz_items = dz_data.get('data', [])
                    if dz_items:
                        image_url = dz_items[0].get('picture_xl') or dz_items[0].get('picture_big')
            except Exception:
                pass

            # Wikipedia bio
            bio = None
            try:
                w_title = urllib.parse.quote(name.replace(' ', '_'))
                w_url = f'https://en.wikipedia.org/api/rest_v1/page/summary/{w_title}'
                w_req = urllib.request.Request(w_url, headers={'User-Agent': 'PersonalMusicCatalog/0.1'})
                with urllib.request.urlopen(w_req, timeout=5) as w_resp:
                    w_data = json.loads(w_resp.read().decode())
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
        route = urllib.parse.urlsplit(self.path)
        q = urllib.parse.parse_qs(route.query)
        secret = os.environ.get('CATALOG_API_TOKEN', '')
        if not verify_auth_and_ticket(self.headers, route.path, q, secret):
            self.send_error(401)
            return
        c = Catalog(self.server.database)
        try:
            parts = route.path.strip('/').split('/')
            if route.path == '/v1/search':
                text = q.get('q', [''])[0][:200]
                cached_results = c.search(text)
                if not cached_results or q.get('refresh') == ['true']:
                    provider(c, text)
                    cached_results = c.search(text)
                result = {'results': cached_results, 'cached': True}
            elif route.path == '/v1/ticket' and self.command == 'GET':
                target_path = q.get('path', [''])[0]
                ttl = int(q.get('ttl', [86400])[0])
                expires = int(time.time()) + ttl
                sig = generate_media_ticket(secret, target_path, expires)
                result = {
                    'path': target_path,
                    'ticket': sig,
                    'expires': expires,
                    'query_params': f"ticket={sig}&expires={expires}"
                }
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
                ident = c.request(body['release_id'], body.get('scope', 'album'), origin=body.get('origin', 'explicit_user'))
                row = c.db.execute('SELECT state FROM requests WHERE id=?', (ident,)).fetchone()
                state = row['state'] if row else 'queued'
                result = {'id': ident, 'state': state, 'dispatch_enabled': False}
            elif route.path == '/v1/requests' and self.command == 'GET':
                rows = c.db.execute('SELECT * FROM requests ORDER BY created_at DESC LIMIT 50').fetchall()
                result = {'requests': [dict(r) for r in rows]}
            elif parts[:2] == ['v1', 'requests'] and len(parts) == 3:
                row = c.db.execute('SELECT * FROM requests WHERE id=?', (parts[2],)).fetchone()
                result = dict(row) if row else None
            elif parts[:2] == ['v1', 'books']:
                books = getattr(self.server, 'books', None)
                if not books:
                    books = BooksCore(os.environ.get('BOOKS_DATABASE', 'books.sqlite'))
                    self.server.books = books

                if len(parts) == 2 and self.command == 'GET':
                    result = {
                        'books': books.list_books(
                            query=q.get('q', [None])[0],
                            format_filter=q.get('format', [None])[0],
                            user_id=q.get('user_id', ['default'])[0]
                        )
                    }
                elif len(parts) == 3 and parts[2] == 'requests':
                    if self.command == 'GET':
                        result = {'requests': books.list_requests(state=q.get('state', [None])[0])}
                    elif self.command == 'POST':
                        size = int(self.headers.get('Content-Length', 0))
                        body = json.loads(self.rfile.read(size)) if size > 0 else {}
                        result = books.request_book(**body)
                elif len(parts) == 4 and parts[2] == 'requests':
                    if self.command == 'GET':
                        result = books.get_request(parts[3])
                elif len(parts) == 5 and parts[2] == 'requests' and parts[4] == 'verify' and self.command == 'POST':
                    result = books.verify_request_metadata(parts[3])
                elif len(parts) == 5 and parts[2] == 'requests' and parts[4] == 'state' and self.command == 'POST':
                    size = int(self.headers.get('Content-Length', 0))
                    body = json.loads(self.rfile.read(size)) if size > 0 else {}
                    result = books.update_request_state(parts[3], **body)
                elif len(parts) == 3 and parts[2] == 'sync' and self.command == 'POST':
                    abs_url = os.environ.get('ABS_URL', 'http://127.0.0.1:13378')
                    abs_token = os.environ.get('ABS_TOKEN', 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VySWQiOiI0M2IwZjY1NS0xZjc3LTQ1ZDAtYTFlMC1hNWEyN2MzNzE3NjEiLCJ1c2VybmFtZSI6InJvb3QiLCJpYXQiOjE3NzM5NTI4OTF9.GbOc3bhWXnr8-r9ewGul2OBVgs2s_HWbKjAkvJW0qV0')
                    result = books.sync_from_abs(abs_url, abs_token)
                elif len(parts) == 3 and self.command == 'GET':
                    result = books.get_book(parts[2], user_id=q.get('user_id', ['default'])[0])
                elif len(parts) == 4 and parts[3] == 'progress':
                    if self.command == 'GET':
                        bk = books.get_book(parts[2], user_id=q.get('user_id', ['default'])[0])
                        result = bk['progress'] if bk else None
                    elif self.command == 'POST':
                        size = int(self.headers.get('Content-Length', 0))
                        body = json.loads(self.rfile.read(size)) if size > 0 else {}
                        result = books.update_progress(parts[2], **body)
                elif len(parts) == 4 and parts[3] == 'annotations':
                    if self.command == 'GET':
                        result = {'annotations': books.get_annotations(parts[2], user_id=q.get('user_id', ['default'])[0])}
                    elif self.command == 'POST':
                        size = int(self.headers.get('Content-Length', 0))
                        body = json.loads(self.rfile.read(size)) if size > 0 else {}
                        result = books.add_annotation(parts[2], **body)
                elif len(parts) == 5 and parts[3] == 'annotations' and self.command == 'DELETE':
                    result = books.delete_annotation(parts[4], user_id=q.get('user_id', ['default'])[0])
                elif len(parts) == 4 and parts[3] == 'alignment':
                    if self.command == 'GET':
                        result = books.get_alignment(parts[2])
                    elif self.command == 'POST':
                        size = int(self.headers.get('Content-Length', 0))
                        body = json.loads(self.rfile.read(size)) if size > 0 else {}
                        result = books.store_alignment(parts[2], **body)
                elif len(parts) == 5 and parts[3] == 'align' and parts[4] == 'audio-to-cfi' and self.command == 'GET':
                    try:
                        track = int(q.get('track', [1])[0])
                        sec = float(q.get('sec', [0.0])[0])
                        result = books.map_audio_to_reading_location(parts[2], track, sec)
                    except (ValueError, TypeError):
                        self.send_error(400)
                        return
                elif len(parts) == 5 and parts[3] == 'align' and parts[4] == 'cfi-to-audio' and self.command == 'GET':
                    cfi = q.get('cfi', [''])[0]
                    result = books.map_reading_location_to_audio(parts[2], cfi)
                elif len(parts) == 4 and parts[3] == 'epub' and self.command == 'GET':
                    bk = books.get_book(parts[2])
                    if not bk:
                        self.send_error(404)
                        return
                    epub_ed = next((ed for ed in bk.get('editions', []) if ed.get('format') == 'epub'), None)
                    if not epub_ed or not epub_ed.get('assets'):
                        self.send_error(404)
                        return
                    asset = epub_ed['assets'][0]
                    abs_item_id = asset.get('abs_item_id')
                    abs_url = os.environ.get('ABS_URL', 'http://127.0.0.1:13378')
                    abs_token = os.environ.get('ABS_TOKEN', 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VySWQiOiI0M2IwZjY1NS0xZjc3LTQ1ZDAtYTFlMC1hNWEyN2MzNzE3NjEiLCJ1c2VybmFtZSI6InJvb3QiLCJpYXQiOjE3NzM5NTI4OTF9.GbOc3bhWXnr8-r9ewGul2OBVgs2s_HWbKjAkvJW0qV0')
                    req = urllib.request.Request(f'{abs_url}/api/items/{abs_item_id}/ebook', headers={'Authorization': f'Bearer {abs_token}'})
                    with urllib.request.urlopen(req, timeout=15) as resp:
                        epub_bytes = resp.read()
                    self.send_response(200)
                    self.send_header('Content-Type', 'application/epub+zip')
                    self.send_header('Content-Length', str(len(epub_bytes)))
                    self.end_headers()
                    self.wfile.write(epub_bytes)
                    return
                elif len(parts) == 4 and parts[3] == 'cover' and self.command == 'GET':
                    bk = books.get_book(parts[2])
                    if not bk:
                        self.send_error(404)
                        return
                    abs_item_id = None
                    for ed in bk.get('editions', []):
                        for a in ed.get('assets', []):
                            if a.get('abs_item_id'):
                                abs_item_id = a['abs_item_id']
                                break
                        if abs_item_id:
                            break
                    if not abs_item_id:
                        self.send_error(404)
                        return
                    abs_url = os.environ.get('ABS_URL', 'http://127.0.0.1:13378')
                    abs_token = os.environ.get('ABS_TOKEN', 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VySWQiOiI0M2IwZjY1NS0xZjc3LTQ1ZDAtYTFlMC1hNWEyN2MzNzE3NjEiLCJ1c2VybmFtZSI6InJvb3QiLCJpYXQiOjE3NzM5NTI4OTF9.GbOc3bhWXnr8-r9ewGul2OBVgs2s_HWbKjAkvJW0qV0')
                    req = urllib.request.Request(f'{abs_url}/api/items/{abs_item_id}/cover', headers={'Authorization': f'Bearer {abs_token}'})
                    try:
                        with urllib.request.urlopen(req, timeout=10) as resp:
                            img_bytes = resp.read()
                            content_type = resp.headers.get('Content-Type', 'image/jpeg')
                        self.send_response(200)
                        self.send_header('Content-Type', content_type)
                        self.send_header('Content-Length', str(len(img_bytes)))
                        self.send_header('Cache-Control', 'public, max-age=86400')
                        self.end_headers()
                        self.wfile.write(img_bytes)
                        return
                    except Exception:
                        self.send_error(404)
                        return
                elif len(parts) == 5 and parts[3] == 'audio' and self.command == 'GET':
                    try:
                        track_num = int(parts[4])
                    except ValueError:
                        self.send_error(400)
                        return
                    bk = books.get_book(parts[2])
                    if not bk:
                        self.send_error(404)
                        return
                    audio_ed = next((ed for ed in bk.get('editions', []) if ed.get('format') == 'audiobook'), None)
                    if not audio_ed or not audio_ed.get('assets'):
                        self.send_error(404)
                        return
                    asset = next((a for a in audio_ed['assets'] if a.get('track_number') == track_num), None)
                    if not asset or not asset.get('abs_item_id') or not asset.get('abs_file_ino'):
                        self.send_error(404)
                        return
                    abs_url = os.environ.get('ABS_URL', 'http://127.0.0.1:13378')
                    abs_token = os.environ.get('ABS_TOKEN', 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VySWQiOiI0M2IwZjY1NS0xZjc3LTQ1ZDAtYTFlMC1hNWEyN2MzNzE3NjEiLCJ1c2VybmFtZSI6InJvb3QiLCJpYXQiOjE3NzM5NTI4OTF9.GbOc3bhWXnr8-r9ewGul2OBVgs2s_HWbKjAkvJW0qV0')
                    upstream_url = f"{abs_url}/api/items/{asset['abs_item_id']}/file/{asset['abs_file_ino']}"
                    upstream_headers = {'Authorization': f'Bearer {abs_token}'}
                    if 'Range' in self.headers:
                        upstream_headers['Range'] = self.headers['Range']
                    req = urllib.request.Request(upstream_url, headers=upstream_headers)
                    try:
                        with urllib.request.urlopen(req, timeout=30) as resp:
                            self.send_response(resp.status)
                            for h in ('Content-Type', 'Content-Length', 'Content-Range', 'Accept-Ranges'):
                                if h in resp.headers:
                                    self.send_header(h, resp.headers[h])
                            self.end_headers()
                            while chunk := resp.read(65536):
                                self.wfile.write(chunk)
                            return
                    except urllib.error.HTTPError as e:
                        self.send_error(e.code)
                        return
                else:
                    self.send_error(404)
                    return
            elif parts[:2] == ['v1', 'tasks']:
                if not hasattr(self.server, 'books') or self.server.books is None:
                    books = BooksCore(os.environ.get('BOOKS_DATABASE', 'books.sqlite'))
                    self.server.books = books
                else:
                    books = self.server.books

                if len(parts) == 2:
                    if self.command == 'GET':
                        result = {'tasks': books.list_tasks(state=q.get('state', [None])[0], priority=q.get('priority', [None])[0])}
                    elif self.command == 'POST':
                        size = int(self.headers.get('Content-Length', 0))
                        body = json.loads(self.rfile.read(size)) if size > 0 else {}
                        result = books.enqueue_task(**body)
                elif len(parts) == 3 and parts[2] == 'process-next' and self.command == 'POST':
                    result = books.process_next_task()
                elif len(parts) == 3 and self.command == 'GET':
                    result = books.get_task(parts[2])
                else:
                    self.send_error(404)
                    return
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
    do_DELETE = dispatch

def serve(database, port, dispatch=False, dry_run=False):
    if not os.environ.get('CATALOG_API_TOKEN'):
        raise RuntimeError('CATALOG_API_TOKEN required')
    server = HTTPServer(('127.0.0.1', port), Handler)
    server.database = database
    server.books = BooksCore(os.environ.get('BOOKS_DATABASE', 'books.sqlite'))
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
