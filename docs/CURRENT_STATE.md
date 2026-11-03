# Current state

Owner: Antigravity, branch `antigravity/catalog-client`.
Upstream baseline: tag 1.0.2. Fork: https://github.com/koltensaccount/finamp ; upstream remote retained.
Stable Finamp playback, queue, lyrics, normalization, offline download, and license intact.

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
   - Full Apple Music UI visual redesign (intentionally deferred until core functionality is complete).
