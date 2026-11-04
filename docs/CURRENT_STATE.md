# Current State — Production Acquisition & End-to-End Catalog Verification

Owner: Codex & Antigravity, branch `codex/catalog-identity`. Upstream baseline: tag 1.0.2.
Fork: https://github.com/koltensaccount/finamp ; upstream remote retained.
Flutter client working tree (`work/finamp-catalog-client`) on branch `antigravity/catalog-client` was kept completely untouched.

## 1. Verified Infrastructure State

- **Music Library Size**: 9,743 indexed Jellyfin audio items across 684 reconstructed album entities in `/mnt/media/Music`.
- **Display Title Cleanup**: 277 FLAC files across 20 multi-disc albums cleaned with zero lossless audio degradation (bit-for-bit stream MD5 and decoded PCM `s32le` SHA-256 verified; pre-write backups in `production-fixes-backup/` with logging in `production-fixes-journal.jsonl`).
- **Jellyfin Favorites Synchronization**: 1,306 total favorites on active user account `music` (`F6CF8A7A-5D89-48FE-8D8A-A63826C68C07`). Additively synchronized 315 exact Spotify liked songs; zero existing favorites touched.
- **Beatles Preferred Mix Invariance**: Verified bit-for-bit preservation of original mono and stereo mixes; no unvetted overwrites.

## 2. End-to-End Acquisition Pipeline (`acquisition.py`)

- **Scoped Acquisition Dispatcher**: Implemented in `backend/acquisition.py`, driving end-to-end request-to-playback workflow through Lidarr (port 8686), Soularr (Docker), SLSKD (port 5030), Jellyfin (port 8096), and catalog backend (:8765).
- **Strict Invariants**:
  - *Album-Centric*: Single-song requests are explicitly rejected with HTTP 400 (`single-song acquisition is not supported by the current backend`).
  - *Already-Owned Short Circuit*: If an album is already 100% owned, transitions immediately to `available` with progress 1.0 without dispatching duplicate searches.
  - *Idempotent Deduplication*: Resubmitting an active request returns the existing request record.
  - *Safe Default*: Live dispatch is disabled by default (`dispatch_enabled: false`) and requires explicit opt-in via `--dispatch` or `CATALOG_DISPATCH_ENABLED=1`.
- **Durable Lifecycle Transitions**:
  `queued` -> `dispatched` -> `downloading` (with transfer file progress) -> `imported` -> `available` (post-Jellyfin library update and catalog reconciliation), or `failed` with recorded `failure_reason` after 3 retries.
- **Restart Recovery**: Restarts safely resume in-flight requests without duplicate dispatch or state regression.
- **Automatic Lifecycle Polling**: Integrated into `refresh.py` loop so background SLSKD/Lidarr completions advance request states automatically.

## 3. Real-World Acquisition Verification

1. **G Herbo — *PTSD* (2020)**:
   - Full 28-track dual-disc album acquired end-to-end via Soularr and SLSKD from user `Barnalks`.
   - Downloaded Albums Scan successfully imported all 28 tracks into `/mnt/media/Music/G Herbo/PTSD (2020)/` across `Digital Media 01` (14 tracks) and `Digital Media 02` (14 tracks).
   - Reconciled into `local_items` in `catalog.sqlite` and active in Jellyfin.
2. **Neutral Milk Hotel — *In the Aeroplane Over the Sea* (1998)**:
   - Request 4 submitted via `POST /v1/requests` for canonical release `318eb89c-49e6-392b-ac28-708b08f89586`.
   - Dispatched live to Lidarr: added artist `Neutral Milk Hotel` (Lidarr Artist ID 1340), matched album `In the Aeroplane Over the Sea` (Lidarr Album ID 21758), set monitored status (11/11 tracks), and triggered `AlbumSearch`.
   - Request state progressed to `dispatched` with full details JSON.

## 4. Enhanced Artist Identity & Metadata Contract

- **`GET /v1/artists/resolve?item_id={itemId}`**:
  - Deterministically resolves any Jellyfin track item ID, album ID, artist ID, or MusicBrainz UUID to canonical MusicBrainz artist identity and display name (`confidence: exact`).
  - Enables the Finamp Flutter client to navigate directly from downloaded/local items to rich online catalog pages (`/catalog/artist`) without heuristics or string guessing.
- **`GET /v1/artists/{id}` Enrichment**:
  - Enriched with high-resolution artist photography from Deezer API.
  - Enriched with artist biography from Wikipedia REST API summary.
  - Canonical MusicBrainz metadata: Type (e.g. `Group`), Country (`GB`, `US`), Disambiguation, and parsed Genres list.
  - Complete discography grouping (`albums`, `eps`, `singles`, `compilations`, `live`, `other`) with local ownership status (`full`, `partial`, `none`).
- **`GET /v1/requests` & `GET /v1/requests/{id}`**:
  - Exposes active request list and detailed status with progress, backend IDs, and failure reasons.

## 5. Verification & Tests

- 22/22 unit tests pass across `test_catalog.py`, `test_http.py`, and `test_acquisition.py` both locally and deployed on server `koltensserver`.
- SQLite concurrency fixed: `PRAGMA busy_timeout = 30000;`, safe column migrations, and non-clobbering `INSERT ... ON CONFLICT(id) DO UPDATE SET`.
