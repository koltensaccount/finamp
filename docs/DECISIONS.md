# Architectural & Operational Decisions

1. **Strict Album-Centric Acquisition**:
   - Single-song acquisition is intentionally rejected with HTTP 400. Requesting any track triggers the complete album edition acquisition in Lidarr/Soularr to keep library organization pristine and prevent fractured discographies.

2. **Durable, Explicit Request State Machine**:
   - States: `queued` -> `dispatched` -> `downloading` -> `imported` -> `available` (or `failed`).
   - Requests persist in `requests` table in `catalog.sqlite` with timestamps, progress floats, and detailed JSON (`details_json`).
   - Retries capped at 3 before setting `state='failed'` with clear `failure_reason`.

3. **Disabled-by-Default Dispatch Safety**:
   - Live acquisition dispatch is disabled by default (`dispatch_enabled: false`).
   - Requires explicit opt-in via `--dispatch` CLI flag or `CATALOG_DISPATCH_ENABLED=1` environment variable.
   - Dry-run mode (`--dry-run` or `CATALOG_DISPATCH_DRY_RUN=1`) logs actions without modifying Lidarr.

4. **Artist Resolution Contract (`/v1/artists/resolve`)**:
   - Uses deterministic hierarchy: direct MBID check -> `local_items.payload.ProviderIds` -> verified `mappings` -> exact catalog artist name match.
   - Provides Finamp Flutter client a rock-solid bridge from local Jellyfin `BaseItemId`s to online MusicBrainz artist discographies.

5. **Multi-Source Artist Enrichment**:
   - Combines MusicBrainz (canonical classification, country, disambiguation, genres), Deezer (high-res photography without auth tokens), and Wikipedia (concise biography extracts) into a single, cohesive payload on `GET /v1/artists/{id}`.
   - Fully backward-compatible with existing client models (`CatalogArtist.fromJson`).

6. **SQLite Concurrency & Data Integrity**:
   - Configured `PRAGMA busy_timeout = 30000;` and WAL mode across all catalog connections.
   - Replaced clobbering `INSERT OR REPLACE` with `INSERT INTO artists ... ON CONFLICT(id) DO UPDATE SET` to guarantee enriched artist metadata is never wiped during routine syncs.

7. **Zero Lossless Audio Frame Modification**:
   - Audio tag updates must preserve FLAC stream MD5 and decoded PCM `s32le` SHA-256 invariance. Pre-write backups stored in `production-fixes-backup/` with logging in `production-fixes-journal.jsonl`.
