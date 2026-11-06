# KB Music — cross-platform UX parity contract

Status: design/engineering acceptance contract, **not** a claim that every feature works.
Created 2026-11-06 for the user-requested Spotify-class polish of KB Music.
Implementation starting point: `codex/ux-parity-pass-20261106`, cut from `antigravity/catalog-client`.

## Product goal

KB Music is **one music-and-books product** across iPhone, iPad, macOS, and web, connected to one user's self-hosted services. Keep a native feel on each device without creating four divergent feature sets. Treat Apple Music as a quality reference for restraint and platform integration, Spotify as a usability reference for quick song actions, discovery and dense desktop music-library browsing. Do not copy another app pixel-for-pixel.

Avoid moving network/database decisions into UI widgets. Keep Jellyfin playback, catalog identity, Audiobookshelf/Books, offline downloads, lyrics, request workflow, and queue semantics intact. A gesture is just a second entrypoint to the **same** action as the menu item. No duplicated backend, music DB, playback engine, or favorite state.

## Shared behavior and naming

- Every platform exposes the same logical screen routes, entities, source labels, actions, and queue semantics: Home, Search, Library, Liked Songs, playlists, artists, albums, Now Playing, Queue, Lyrics, Books, EPUB Reader, Audiobook Now Playing, Settings/Account.
- One account/login and credentials storage model. Store secrets only through approved secure storage and server tokens. Never require retyping a server key on each device when account pairing is available.
- Favorite/unfavorite, add-to-queue, play-next, add-to-playlist, download, artist/album navigation, shuffle, repeat, speed, output routing, lyrics, and queue reorder must mean the same thing everywhere. If an action is unsupported, show a truthful disabled state and reason rather than a no-op.
- Show actual active Music **or** Books playback in the global mini-player; never show stale music when an audiobook is playing. Cross-device "playing on iPhone" handoff is a future functional capability to verify, not a label to fake.
- Native interaction mapping: mobile swipes/long press/haptics; iPad pointer+touch; macOS right-click/hover/shortcuts; web right-click/hover/keyboard and focus. All actions must be keyboard-accessible and announced by accessibility tools.

## Layout rules / design tokens

- Baseline accent: KB red `#FA2D48` where appropriate, neutral text and subtle dynamically derived artwork tones. Strong contrast, restrained gradients, no garish tinting or unrelated colors per screen.
- Typography: readable system-native hierarchy and truncation. Artwork, song metadata, scrubber and controls form a single compact Now Playing composition with bounded gaps. Large screens must not become stretched phone screens.
- Phone: touch targets >=44pt, compact rows, context sheet with sticky condensed item preview and clear hierarchy; no giant menu of equally weighted actions.
- iPad: adaptive split/sidebar, resizable content/queue views, compact popovers where appropriate; touch and pointer parity.
- macOS: sidebar + multi-column library tables, hover affordances, right-click anchored menus, keyboard navigation, sensible default/max window sizes, native menu bar/shortcuts, output controls.
- Web: responsive sidebar/compact mobile navigation, same tables and track gestures with pointer/focus equivalents; match typography, spacing, iconography, queue and playlist semantics. First locate the actual deployed web UI source — a `web/` Flutter target was not present in the inspected fork. Do not declare web parity complete merely because the Flutter widgets exist.
- Shared route/action descriptors and design tokens should be exported or mirrored by a versioned common contract, with screenshot/interaction parity checks. No divergent hand-written copies of business behavior.

## Liked Songs

- Mobile: search and genres; shared track row, configurable swipe-right favorite/unfavorite and swipe-left Add Next Up, menu and accessible fallback.
- Desktop/web: song number, title+artist, album, honest date column, duration, dense hover rows, sort and filters; sorting must preserve the right playback order.
- **Do not call Jellyfin `DateCreated` the "date liked".** It is library creation/import time, even when returned in a favorite-filtered query. Label current column "Added to library". Introduce authoritative `liked_at` server-side from favorite events (and any verifiable Spotify liked-date history) before adding Date Liked; keep unknown historical values unknown and reconcile server updates safely.
- Favorites must be backed by the same optimistic update/rollback provider on all screens; an accidental unlike should offer undo after stable server behavior is confirmed.

## Now Playing / Context actions

- Group album art, title/artist, scrubber, controls and secondary actions with sensible max artwork sizes and responsive layout. Preserve stream state through mini/full/lyrics/queue transitions; test long metadata, Dynamic Type, notches, rotation, short windows.
- Quick actions (Play Next, Add to Queue, Like, Add to Playlist) visually outrank rare actions. Separate track-specific actions from player-scoped shuffle/repeat/sleep timer, destructive Clear Queue/Delete From Server, and advanced options. No hidden functionality regressions.
- Desktop/web context menus should be anchored to the pointer/ellipsis, not full-screen mobile sheets; when not implemented yet, keep existing safe action path and mark outstanding work rather than adding fake menu items.
- A favorite gesture cannot fetch a queue slice or disrupt playback; ensure persisted swipe enums are backward compatible. Avoid swipes acting while page is scrolling horizontally.

## Cross-device acceptance matrix

| Check | iPhone | iPad | macOS | Web |
| --- | --- | --- | --- | --- |
| Now Playing balanced + mini-player transition | required | required | required | required |
| Favorite/queue actions with native interaction | swipe | touch + pointer | right-click + shortcuts | pointer + keyboard |
| Liked Songs sorting/search/genres | required | required | dense table | dense table |
| Actual liked date or honest unknown | required | required | required | required |
| Books active mini-player/chapters/offline as supported | required | required | required | required |
| No duplicate/split-brain playback state | required | required | required | required |
| Credential/account continuity | required | required | required | required |
| Navigation and layout screenshot parity | required | required | required | required |

Test with representative tracks (long album/artist names, collaborations, unavailable local catalog, offline titles), playlists, queue reorder + shuffle, active downloads, radio, Deeplink, and Book audio switching. Test cold start and device reconnection. Any platform not independently verified remains "unverified", not "passed".

## Scoped patch already written on this branch

- Portrait Now Playing: grouped bounded artwork/metadata/controls instead of separate space-evenly regions.
- Liked Songs: adaptive wide desktop hero/table, sort/filter by library-import date/name/artist/album/last played, shared mobile track-row gestures; dates explicitly label library import, not favorite time.
- Shared track swipe actions: favorite toggle added to enum and Hive adapter, rightward default on new profiles, existing queue action preserved.
- Track menu: compact preview/action rows and denser options, frequent actions moved up. **Pointer-anchored desktop menu is still to be implemented.**
- Empty "Your Likes (from \"\")" source label replaced by localized Favorites when source parameter is absent.

## Remaining issues

Run formatting, code generation, analyzer, unit/widget tests, simulator and actual device verification before merging. Ensure custom sort enum, generated adapter, and compact sheet all survive tests. Real `liked_at` syncing needs account/server design. Existing installed swipe preferences may intentionally override new defaults; migrate only default-value settings with clear tests and preserve user-customized choices. Find the current web source/deployment and deliver the parity work there; it is **not** proven to be generated from this Flutter fork.
