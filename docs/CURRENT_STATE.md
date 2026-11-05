# Current state — evidence index

Inspected 2026-11-05 against published `antigravity/catalog-client` at `e4cfe444`.
This page separates source presence from runtime verification. The old narrative
below is retained as a historical report, not re-certified evidence.

| Capability | Source evidence | Verification boundary |
| --- | --- | --- |
| Catalog identity/discovery/availability | `backend/catalog.py`, `backend/server.py`, `lib/services/catalog_api_client.dart` | Code and tests exist; see task verification reports for actual runs. |
| Native album navigation | `lib/components/MusicScreen/item_wrapper.dart` routes to AlbumScreen | No fresh real-device navigation/queue test in guidance work. |
| Apple-style native navigation | `lib/components/navigation/`, `test/apple_sidebar_navigation_test.dart` | Cross-platform visual parity remains unverified. |
| KB Account bootstrap/pairing/device list | `lib/services/kb_account_service.dart`, `test/kb_account_service_test.dart`, `test/account_screen_test.dart` | Mock tests do not establish real pairing or playback sync. Account backend is server-only source. |
| Preferences/device presence | Methods exist in deployed account source inspected read-only | No evidence here of native client integration or queue handoff. |
| Books / format continuation | `backend/books_core.py`, `backend/alignment_engine.py`, `lib/services/books_api_client.dart`, Books screens/tests | Mapping fixtures are not proof of real alignment or device transfer. |
| Metadata publication | `backend/metadata_engine.py` | Uses file-level replace; backup, collision protection, audio integrity and whole-release rollback are not established. |
| Acquisition | Music outbox plus separate Books coordinator/worker | Music dispatch reports disabled; Books production code can contact real providers. The worker regression is isolated; full-suite metadata I/O still needs auditing. |
| Web/PWA | Separate server source; see `agents/WEB_WORKSPACE.md` | Source present; deployed image/source equivalence, offline behavior and native visual parity unverified. |
| macOS DMG/updates | Two newer local commits (`ab986c83`, `202eb017`) were inspected outside this branch | Not published in this branch base. Workflow/appcast presence does not prove successful release/update. |

[Product intent](../VISION.md) is aspirational. [Quality gates](agents/QUALITY_GATES.md)
define acceptance; [verification reports](verification/) record actual results.
No media-library writes, acquisition or production rebuilds are part of guidance work.

## Historical report (pre-guidance; claims require dated supporting evidence)

# Earlier current-state report

Owner: Antigravity, branch `antigravity/catalog-client`.
Upstream baseline: tag 1.0.2. Fork: https://github.com/koltensaccount/finamp ; upstream remote retained.
Stable Finamp playback, queue, lyrics, normalization, offline download, and license intact.

## Metadata Remediation & Correctness Verification (Issues A-E)

1. **Issue A — Modified-File Count Discrepancy & Bit-for-Bit Audio Integrity:**
   - Reconciled previously reported 31 modified FLACs against `production-fixes-journal.jsonl` and `production-fixes-backup/` on `koltensserver`: exactly 31 files recorded and backed up.
   - Verified 100% bit-for-bit lossless audio preservation across all modified files: FLAC stream MD5 signatures and ffmpeg decoded PCM SHA256 hashes matched before and after modification.
   - Identified the exact file manifest: 1 Deftones track (Damone, untagged), 1 Coldplay track (Yellow, malformed track number), 11 Earl Sweatshirt tracks (Some Rap Songs, missing albumartist), and 18 Gucci Mane tracks (So Icy Gang, incorrect albumartist).

2. **Issue B — Structured Collaboration Parsing:**
   - Inspected client and server: confirmed regex string splitting (`feat.`, `&`) was safely excised in commit `4d976f8e`.
   - Structured `CatalogCredit` models parse `artist_credit` (`artistId`, `name`, `joinphrase`) from backend, preserving `display_artist` strings in titles/subtitles and rendering individual interactive chips linking to `CatalogArtistScreen`.

3. **Issue C — Album Edition & Title Consistency:**
   - Inspected Deftones, Coldplay, Earl Sweatshirt, and Gucci Mane releases across file tags, Jellyfin DB, and catalog SQLite.
   - Discovered an artificial edition suffix on Deftones files: `album = 'Around the Fur [Lossless]'`.
   - Remediated all 11 tracks in `/mnt/media/Music/Deftones/Around the Fur (1997)/` to `album = 'Around the Fur'`, `albumartist = 'Deftones'`. Backups created, PCM SHA256 / stream MD5 verified bit-for-bit identical, and changes logged to `production-fixes-journal.jsonl` (now 42 verified entries across 41 unique files).
   - Refreshed Jellyfin: album unified under clean title `Around the Fur`, matched MusicBrainz ReleaseGroup `6f935b80-160f-3787-97d6-a4ce342cf8c5`.
   - Verified Coldplay, Earl Sweatshirt, and Gucci Mane have clean canonical titles, all MusicBrainz provider IDs, and zero split album groupings.

4. **Issue D & E — Catalog Availability Confidence & False Negatives:**
   - Resolved false negatives where owned albums displayed "Request Album":
     * Cleaned Deftones album title allowed `reconcile_release` to immediately match tracks 1-9 as available and playable.
     * Fixed release track fetch logic in `server.py`: `v1/releases/{id}` previously checked `if result is None:`, failing to fetch tracks for existing release stubs; corrected to `if result is None or not result.get('tracks'):`.
   - Verified live catalog state: confident mappings increased from 2,332 to 2,974.
   - Search consistency verified end-to-end: audio tags -> Jellyfin indexed values -> catalog identity graph -> cached availability -> Finamp UI.

5. **Codex Autonomous Review:**
   - Executed non-interactive review via `codex review --commit 4d976f8e`.
   - Codex independently verified commit `4d976f8e`: confirmed zero actionable regressions.

6. **Autonomous Review Audit & iOS Simulator Parity Overhaul:**
   - Evaluated review findings across `git diff d8658b45..HEAD` and addressed all items:
     * Fixed nullable artist property access in `GoToArtistMenuEntry.build` callback (`go_to_artist_menu_entry.dart`).
     * Architected `ArtistResolutionHelper.resolveGenuineArtist({artistItems, albumArtists})` in `lib/services/artist_resolution_helper.dart` ensuring truthful fallback to album artists for empty lists or blank/whitespace IDs, avoiding ID fabrication.
     * Restored "Go to Artist" and "Go to Album" action sheet items in `lib/menus/track_menu.dart`.
     * Re-enabled playback feature chips in `lib/components/PlayerScreen/control_area.dart` while cleanly defaulting `featureChipsConfiguration.enabled = false` for minimalist Apple Music aesthetics.
     * Replaced mock resolver with direct production tests in `test/artist_navigation_test.dart` (all 6 edge cases passing).
   - Resolved iOS simulator toolchain issues:
     * Unlinked Homebrew rust toolchain shadowing rustup (`aarch64-apple-ios-sim` target for `flutter_discord_rpc`).
     * Reconstituted `Info.plist` inside `objective_c.framework` for Flutter native asset compliance.
     * Eliminated ScrollController assertion on iOS by returning unadorned child in `FinampScrollBehavior.buildScrollbar`.
     * Added `HitTestBehavior.opaque` on `AlbumScreen` and `TrackNameContent` artist link gesture detectors for responsive touch handling.
   - Interactive verification on iPhone 17 Pro simulator (`485A60A4-3455-4C34-9671-E2F9EB2491B8`):
     * Active bit-perfect FLAC audio playback confirmed ("Wasted Times" by The Weeknd @ 879 kbps).
     * Smooth transition between full-screen Now Playing, collapsed mini-player, and Home/Library navigation.
     * Track action sheet verified with working "Go to Album" and "Go to Artist" navigation routes.
     * 100% test pass rate: 14/14 Flutter tests (`flutter test`) and 16/16 backend tests (`python3 -m unittest`).

7. **Unified Artist Navigation & Discography Experience:**
   - Reconciled and completed unified artist routing across all entry points:
     * Header & collection tiles (`finamp_music_screen_header.dart`, `item_wrapper.dart`)
     * Player chips & Now Playing title spans (`artist_chip.dart`, `track_name_content.dart`)
     * Track text spans & multi-artist credits (`artist_text_spans.dart`, `artists_text_spans.dart`)
     * Context menus & action sheets (`go_to_artist_menu_entry.dart`)
     * Album screen header artist navigation (`album_screen.dart`)
     * Deep-linking & scene URL handling (`main.dart`, `SceneDelegate.swift`)
   - Implemented deterministic `ArtistIdentityService` and safe `ArtistResolutionHelper` routing:
     * Validates genuine MusicBrainz UUIDs (`isMbid`) vs Jellyfin IDs without fabrication.
     * Checks local item provider IDs (`MusicBrainzArtist`/`MusicBrainzAlbumArtist`).
     * Queries backend `/v1/artists/resolve` before exact name fallback.
     * Caches confirmed mappings persistently in `SharedPreferences`.
     * Strict offline fallback to local `ArtistScreen` with offline library toggle.
   - Clarified discography metric labeling:
     * Corrected artist header metrics to explicitly show `${artist.recordings.length} Songs in Library` rather than ambiguous `In Library`.
     * Clean categorization of releases into Studio Albums, Singles & EPs, Compilations, and Live & Other without duplicate release groups.
   - Dynamic artist metadata enrichment (`ArtistImageService`):
     * Replaced hardcoded artist image maps with dynamic Deezer and Wikipedia REST API lookups and persistent caching.
   - Toolchain verification & reproducible build:
     * Flutter 3.47.7 pinned at `.tool/flutter/bin/flutter`.
     * Pinned rustup compiler (`RUSTC`, `RUSTDOC`) avoiding Homebrew interference.
     * Reconstituted `Info.plist` and dylib inside `objective_c.framework` for simulator compliance.
     * Built and installed on iPhone 17 Pro simulator (`485A60A4-3455-4C34-9671-E2F9EB2491B8`).
     * Live UI verified with screenshots across The Beatles (`75 Albums · 501 Releases · 248 Songs in Library`), Metro Boomin (`8 Albums · 34 Releases · 41 Songs in Library`), George Harrison (`11 Albums · 139 Releases · 23 Songs in Library`), and Clairo (`3 Albums · 113 Releases · 32 Songs in Library`).
   - 100% automated test suite pass rate: 23/23 Flutter tests and 17/17 backend tests.

## Live Status & Verification

1. **Toolchain & Build Environment:**
   - Flutter pinned at 3.47.7 (`.tool/flutter/bin/flutter`).
   - Xcode and simulator toolchain operational.
   - CocoaPods manages plugin dependencies with Swift Package Manager disabled (`flutter config --no-enable-swift-package-manager`).
   - Build artifacts routed outside synced directory to `/tmp/finamp-build-output` via `build` symlink to avoid iCloud code-signing detritus.
   - Tested and verified on booted iPhone 17 Pro simulator (`485A60A4-3455-4C34-9671-E2F9EB2491B8`) managed through Xcode Device Hub.

2. **Catalog Client Implementation:**
   - Typed data models in `lib/models/catalog_models.dart`: `CatalogSearchResult`, `CatalogTrack`, `CatalogRelease`, `CatalogAlbumGroup`, `CatalogArtist`, `CatalogAvailability`, `CatalogLocalItem`, and `CatalogRequestStatus`.
   - Authenticated client in `lib/services/catalog_api_client.dart` supporting search, artists, album groups, releases, and requests.
   - Persistent, secure credential storage in `lib/services/catalog_credential_store.dart` (`SecureCatalogCredentialStore`) supporting runtime configuration and simulator development defines.
   - Configuration UI in `lib/screens/catalog_settings_screen.dart` with connection testing, persistent saving, and clearing; exposed via Settings and the search app bar.
   - Unified search screen in `lib/screens/catalog_search_screen.dart` with interactive artist/album/track tiles, availability status, direct playback, and ambiguity modal resolution.
   - Interactive album view in `lib/screens/catalog_album_screen.dart` showing multi-edition dropdowns, ownership chips (`Fully Owned`, `Partially Owned`, `Unowned`), track-by-track availability, direct track playback, and truthful album request submission.
   - Interactive artist view in `lib/screens/catalog_artist_screen.dart` showing discography and credited recordings.
   - Ambiguity & single-song guard in `lib/services/catalog_playback_helper.dart`: candidate items prompt version selection without autoplaying; unowned single-track taps truthfully explain backend album-only acquisition scope.

3. **Live Simulator & Server Verification:**
   - Remote Jellyfin server connection active; entire user music library browsable across Home, Albums, Artists, Playlists, and Tracks tabs.
   - Catalog backend running persistently on server (`koltensserver`) via loopback tunnel (`127.0.0.1:8765`).
   - Tested search for "Melodrama": resolved 11/11 fully owned album and playable tracks.
   - Verified active track playback: "Sober II (Melodrama)" played directly through Finamp's Jellyfin player (FLAC @ 777 kbps, -6.8 dB), showing artwork, playback bar, and full player controls.
   - Tested search for "Brat": resolved partially owned release (1/35 owned) and unavailable tracks ("Vibrate").
   - Single-track tap on unavailable track showed informative dialog explaining single-song acquisition is unsupported.
   - Album request submitted for missing release: UI displayed truthful confirmation modal showing `state: queued` and `dispatch_enabled: false` (acquisition disabled on server). Request persisted directly to SQLite `requests` table (row ID 2).
   - Automated tests: 7/7 Flutter client tests passed (`test/catalog_api_client_test.dart`), 14/14 Python backend tests passed (`backend/tests/`).

4. **Not Complete / Deferred:**
   - Server-side acquisition dispatcher (connecting SQLite outbox to Lidarr/slskd/Soularr).
   - Physical iPhone data cable connectivity / physical device deployment.
   - Full cross-platform visual parity (not verified in this historical report).
