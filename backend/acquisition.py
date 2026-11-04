"""
Scoped Acquisition Dispatcher & Lifecycle Manager for Finamp Catalog.
Drives end-to-end request-to-playback workflow through Lidarr, Soularr, SLSKD, and Jellyfin.
"""
import json, logging, os, sqlite3, sys, time, urllib.error, urllib.parse, urllib.request
from pathlib import Path

logger = logging.getLogger("acquisition")
logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")

class RealLidarrClient:
    def __init__(self, base_url, api_key):
        self.base_url = base_url.rstrip('/')
        self.api_key = api_key

    def _req(self, method, endpoint, payload=None):
        url = f"{self.base_url}/api/v1/{endpoint}"
        headers = {"X-Api-Key": self.api_key, "Content-Type": "application/json"}
        data = json.dumps(payload).encode("utf-8") if payload is not None else None
        req = urllib.request.Request(url, data=data, headers=headers, method=method)
        with urllib.request.urlopen(req, timeout=15) as resp:
            content = resp.read().decode("utf-8")
            return json.loads(content) if content else {}

    def get_artists(self):
        return self._req("GET", "artist")

    def add_artist(self, payload):
        return self._req("POST", "artist", payload)

    def get_artist_albums(self, artist_id):
        return self._req("GET", f"album?artistId={artist_id}")

    def update_album(self, album_id, payload):
        return self._req("PUT", f"album/{album_id}", payload)

    def search_album(self, album_id):
        return self._req("POST", "command", {"name": "AlbumSearch", "albumIds": [album_id]})

    def get_album(self, album_id):
        return self._req("GET", f"album/{album_id}")

class RealSlskdClient:
    def __init__(self, base_url, api_key):
        self.base_url = base_url.rstrip('/')
        self.api_key = api_key

    def get_downloads(self):
        url = f"{self.base_url}/api/v0/transfers/downloads"
        headers = {"X-API-KEY": self.api_key}
        req = urllib.request.Request(url, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=10) as resp:
                content = resp.read().decode("utf-8")
                return json.loads(content) if content else []
        except Exception as e:
            logger.warning(f"Error querying SLSKD downloads: {e}")
            return []

class RealJellyfinClient:
    def __init__(self, base_url, token):
        self.base_url = base_url.rstrip('/')
        self.token = token

    def refresh_library(self):
        url = f"{self.base_url}/Library/Media/Updated"
        req = urllib.request.Request(url, headers={"X-Emby-Token": self.token}, method="POST")
        try:
            with urllib.request.urlopen(req, timeout=10) as resp:
                return resp.status
        except Exception as e:
            logger.warning(f"Error refreshing Jellyfin library: {e}")
            return None

class AcquisitionDispatcher:
    def __init__(self, catalog, dispatch_enabled=False, dry_run=False,
                 lidarr_client=None, slskd_client=None, jellyfin_client=None):
        self.c = catalog
        self.dispatch_enabled = dispatch_enabled or (os.environ.get("CATALOG_DISPATCH_ENABLED", "0") in ("1", "true", "True"))
        self.dry_run = dry_run or (os.environ.get("CATALOG_DISPATCH_DRY_RUN", "0") in ("1", "true", "True"))

        lidarr_url = os.environ.get("LIDARR_URL", "http://127.0.0.1:8686")
        lidarr_key = os.environ.get("LIDARR_API_KEY", "8caa7cceb8a5463b977b10928c424d6e")
        slskd_url = os.environ.get("SLSKD_URL", "http://127.0.0.1:5030")
        slskd_key = os.environ.get("SLSKD_API_KEY", "dKFTvjXGZxosAGrisUwGzuaAgSpN")
        jf_url = os.environ.get("JELLYFIN_URL", "http://127.0.0.1:8096")
        jf_token = os.environ.get("JELLYFIN_TOKEN", "b00648d43061428bb88da32778c1b5fd")

        self.lidarr = lidarr_client or RealLidarrClient(lidarr_url, lidarr_key)
        self.slskd = slskd_client or RealSlskdClient(slskd_url, slskd_key)
        self.jellyfin = jellyfin_client or RealJellyfinClient(jf_url, jf_token)

        self.last_dispatch_time = 0.0
        self._ensure_schema()

    def _ensure_schema(self):
        cols = [c[1] for c in self.c.db.execute("PRAGMA table_info(requests)").fetchall()]
        needed = {
            "updated_at": "REAL",
            "retry_count": "INTEGER DEFAULT 0",
            "failure_reason": "TEXT",
            "progress": "REAL DEFAULT 0.0",
            "details_json": "TEXT"
        }
        for col, col_type in needed.items():
            if col not in cols:
                try:
                    self.c.db.execute(f"ALTER TABLE requests ADD COLUMN {col} {col_type};")
                except sqlite3.OperationalError:
                    pass
        self.c.db.commit()

    def submit_request(self, release_id, scope='album', origin='explicit_user'):
        if scope != 'album':
            raise ValueError('single-song acquisition is not supported by the current backend')

        # Check if already 100% owned locally
        try:
            alb = self.c.album(release_id)
            if alb and alb.get('ownership') == 'full':
                now = time.time()
                row = self.c.db.execute("SELECT id FROM requests WHERE release_id=?", (release_id,)).fetchone()
                if row:
                    req_id = row[0]
                    self.c.db.execute("UPDATE requests SET state='available', progress=1.0, updated_at=? WHERE id=?", (now, req_id))
                else:
                    req_id = self.c.db.execute(
                        "INSERT INTO requests(release_id, scope, state, origin, created_at, updated_at, progress) VALUES(?,?,?,?,?,?,?)",
                        (release_id, scope, 'available', origin, now, now, 1.0)
                    ).lastrowid
                self.c.db.commit()
                return self.get_request(req_id)
        except Exception:
            pass

        # Deduplication check
        existing = self.c.db.execute(
            "SELECT id FROM requests WHERE release_id=? AND state NOT IN ('failed', 'available')",
            (release_id,)
        ).fetchone()
        if existing:
            return self.get_request(existing[0])

        now = time.time()
        req_id = self.c.db.execute(
            "INSERT INTO requests(release_id, scope, state, origin, created_at, updated_at, progress) VALUES(?,?,?,?,?,?,?)",
            (release_id, scope, 'queued', origin, now, now, 0.0)
        ).lastrowid
        self.c.db.commit()

        if self.dispatch_enabled and not self.dry_run:
            self.dispatch_single_request(req_id)

        return self.get_request(req_id)

    def dispatch_single_request(self, request_id):
        row = self.c.db.execute("SELECT * FROM requests WHERE id=?", (request_id,)).fetchone()
        if not row:
            return False

        req = dict(row)
        release_id = req["release_id"]

        # Ensure release metadata exists
        rel = self.c.db.execute("SELECT * FROM releases WHERE id=?", (release_id,)).fetchone()
        if not rel:
            logger.warning(f"Release {release_id} not found in catalog database.")
            return False

        group_id = rel["group_id"]
        title = rel["title"]

        # Fetch credits
        c_list, disp_artist = self.c.get_credits('release', release_id)
        if not c_list and group_id:
            c_list, disp_artist = self.c.get_credits('group', group_id)

        artist_name = disp_artist or (c_list[0]['name'] if c_list else "")
        artist_mbid = c_list[0]['artist_id'] if c_list else ""

        if not artist_name:
            self.c.db.execute("UPDATE requests SET state='failed', failure_reason='Unknown artist', updated_at=? WHERE id=?", (time.time(), request_id))
            self.c.db.commit()
            return False

        if self.dry_run:
            logger.info(f"[DRY-RUN] Would dispatch request {request_id} for {artist_name} - {title}")
            return True

        # Communicate with Lidarr
        try:
            artists = self.lidarr.get_artists()
            art_match = None
            for a in artists:
                if (artist_mbid and a.get('foreignArtistId') == artist_mbid) or (a.get('artistName', '').lower() == artist_name.lower()):
                    art_match = a
                    break

            if not art_match:
                logger.info(f"Adding artist '{artist_name}' to Lidarr...")
                art_match = self.lidarr.add_artist({
                    "artistName": artist_name,
                    "foreignArtistId": artist_mbid or "",
                    "qualityProfileId": 2, # Lossless
                    "metadataProfileId": 1, # Standard
                    "rootFolderPath": "/data/Music",
                    "monitored": True,
                    "monitorNewItems": "none",
                    "addOptions": {
                        "monitor": "none",
                        "searchForMissingAlbums": False
                    }
                })

            artist_id = art_match["id"]
            albums = self.lidarr.get_artist_albums(artist_id)
            target_alb = None
            clean_target = title.lower().split("(")[0].strip()

            for alb in albums:
                alb_clean = alb.get("title", "").lower().split("(")[0].strip()
                if clean_target == alb_clean or clean_target in alb_clean or alb_clean in clean_target:
                    target_alb = alb
                    break

            if not target_alb:
                logger.warning(f"Target album '{title}' not found in Lidarr artist discography.")
                retries = req.get("retry_count", 0) + 1
                if retries >= 3:
                    self.c.db.execute("UPDATE requests SET state='failed', failure_reason='Album not in Lidarr discography', updated_at=? WHERE id=?", (time.time(), request_id))
                else:
                    self.c.db.execute("UPDATE requests SET retry_count=?, updated_at=? WHERE id=?", (retries, time.time(), request_id))
                self.c.db.commit()
                return False

            lidarr_album_id = target_alb["id"]
            if not target_alb.get("monitored"):
                target_alb["monitored"] = True
                self.lidarr.update_album(lidarr_album_id, target_alb)

            # Trigger AlbumSearch
            self.lidarr.search_album(lidarr_album_id)
            self.last_dispatch_time = time.time()

            details = {
                "artist_name": artist_name,
                "album_title": title,
                "lidarr_artist_id": artist_id,
                "lidarr_album_id": lidarr_album_id
            }

            self.c.db.execute("""
                UPDATE requests 
                SET state='dispatched', backend_id=?, details_json=?, updated_at=? 
                WHERE id=?
            """, (str(lidarr_album_id), json.dumps(details), time.time(), request_id))
            self.c.db.commit()
            logger.info(f"Successfully dispatched request {request_id} ({artist_name} - {title}) to Lidarr.")
            return True

        except Exception as e:
            logger.exception(f"Error dispatching request {request_id}: {e}")
            retries = req.get("retry_count", 0) + 1
            state = 'failed' if retries >= 3 else 'queued'
            self.c.db.execute("UPDATE requests SET state=?, retry_count=?, failure_reason=?, updated_at=? WHERE id=?", (state, retries, str(e), time.time(), request_id))
            self.c.db.commit()
            return False

    def poll_lifecycle(self):
        active = self.get_active_requests()
        if not active:
            return {"active_count": 0}

        slskd_downloads = self.slskd.get_downloads()

        for req in active:
            req_id = req["id"]
            release_id = req["release_id"]
            state = req["state"]
            lidarr_album_id = int(req["backend_id"]) if req.get("backend_id") else None
            details = json.loads(req["details_json"]) if req.get("details_json") else {}

            target_title = details.get("album_title", "").lower().split("(")[0].strip()

            # 1. State: dispatched -> downloading
            if state == 'dispatched':
                match_found = False
                progress = 0.0
                for u in slskd_downloads:
                    for d in u.get("directories", []):
                        d_name = d.get("directory", "").lower()
                        if target_title and target_title in d_name:
                            match_found = True
                            files = d.get("files", [])
                            if files:
                                succ = sum(1 for f in files if "succeeded" in f.get("state", "").lower())
                                progress = round(succ / len(files), 2)
                            break
                    if match_found:
                        break

                if match_found:
                    self.c.db.execute("UPDATE requests SET state='downloading', progress=?, updated_at=? WHERE id=?", (progress, time.time(), req_id))
                    self.c.db.commit()
                    continue

                # Check if already imported
                if lidarr_album_id:
                    try:
                        alb_data = self.lidarr.get_album(lidarr_album_id)
                        if alb_data.get("statistics", {}).get("percentOfTracks", 0) == 100:
                            self.c.db.execute("UPDATE requests SET state='imported', progress=1.0, updated_at=? WHERE id=?", (time.time(), req_id))
                            self.c.db.commit()
                            continue
                    except Exception:
                        pass

            # 2. State: downloading -> imported
            elif state == 'downloading':
                downloading_now = False
                progress = req.get("progress", 0.0)
                for u in slskd_downloads:
                    for d in u.get("directories", []):
                        d_name = d.get("directory", "").lower()
                        if target_title and target_title in d_name:
                            downloading_now = True
                            files = d.get("files", [])
                            if files:
                                succ = sum(1 for f in files if "succeeded" in f.get("state", "").lower())
                                progress = round(succ / len(files), 2)
                            break

                if downloading_now:
                    self.c.db.execute("UPDATE requests SET progress=?, updated_at=? WHERE id=?", (progress, time.time(), req_id))
                    self.c.db.commit()
                else:
                    # Transfer ended, check if Lidarr has imported
                    if lidarr_album_id:
                        try:
                            alb_data = self.lidarr.get_album(lidarr_album_id)
                            pct = alb_data.get("statistics", {}).get("percentOfTracks", 0)
                            if pct == 100:
                                self.c.db.execute("UPDATE requests SET state='imported', progress=1.0, updated_at=? WHERE id=?", (time.time(), req_id))
                                self.c.db.commit()
                                continue
                        except Exception:
                            pass

            # 3. State: imported -> available
            elif state == 'imported':
                # Trigger Jellyfin refresh
                self.jellyfin.refresh_library()
                self.c.reconcile_release(release_id)
                try:
                    alb = self.c.album(release_id)
                    if alb and alb.get("ownership") == 'full':
                        self.c.db.execute("UPDATE requests SET state='available', progress=1.0, updated_at=? WHERE id=?", (time.time(), req_id))
                        self.c.db.commit()
                        logger.info(f"Request {req_id} ({release_id}) is now fully AVAILABLE!")
                except Exception:
                    pass

        return {"active_count": len(self.get_active_requests())}

    def get_request(self, request_id):
        row = self.c.db.execute("SELECT * FROM requests WHERE id=?", (request_id,)).fetchone()
        if not row:
            return None
        res = dict(row)
        res["dispatch_enabled"] = self.dispatch_enabled
        return res

    def get_all_requests(self, limit=100):
        rows = self.c.db.execute("SELECT * FROM requests ORDER BY created_at DESC LIMIT ?", (limit,)).fetchall()
        return [dict(r) for r in rows]

    def get_active_requests(self):
        rows = self.c.db.execute("SELECT * FROM requests WHERE state NOT IN ('available', 'failed') ORDER BY created_at").fetchall()
        return [dict(r) for r in rows]
