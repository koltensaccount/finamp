# Shared workflow checklist

Choose the simplest effective task workflow; neither native nor web is the automatic standard. Align both to a shared contract.

This records the pre-fix audit baseline; tested source fixes are tracked in the task verification report.

This is the common target, not a mandate to duplicate every existing button. Native status is source evidence unless explicitly tested. Use fixture accounts/media for mutations; do not exercise acquisition, deletion or security changes on production merely to check parity.

61 task contracts. Each must be checked on relevant native and web platforms. A presence flag is not a passing behavior test.

## Account and onboarding

| ID | Task | Current web evidence | Acceptance check |
| --- | --- | --- | --- |
| KB-001 | Sign in and bootstrap | live-pass | Use one account; connect services without exposing provider/admin keys |
| KB-002 | Pair another device | contract-gap | Generate/approve/poll a short-lived code; establish the target session |
| KB-003 | Restore/refresh session | partial | Restore valid sessions; refresh expiry; reject revoked sessions |
| KB-004 | List, rename, revoke devices | partial | Identify real devices and persist management actions |
| KB-005 | Sign out / account isolation | live-fail | Remove session and private client state; reject all protected API calls |
| KB-006 | Advanced server connection | not-exposed | Offer advanced server setup without burdening normal onboarding |

## Browse and discovery

| ID | Task | Current web evidence | Acceptance check |
| --- | --- | --- | --- |
| KB-007 | Home and recommendations | partial | Real, explainable library-driven sections; no fabricated personalization |
| KB-008 | Library categories | source-present | Browse albums/artists/tracks/playlists and preserve position/back stack |
| KB-009 | Open album from every entry | live-pass-home | Album/title opens details; queue and playback remain unchanged |
| KB-010 | Open artist | partial | Resolve actual identity; do not use name search as ownership evidence |
| KB-011 | Album editions/discography | partial | Explicit edition choice and chronology; album-concept differs from owned edition |
| KB-012 | Unified search | partial | One search experience across public catalog and owned media with honest availability |
| KB-013 | Search history | not-found | Real viewed/search activity, persist/clear without seeded recents |
| KB-014 | Genres and browsing filters | partial | Task-focused filtering/sort; consistent semantics across clients |
| KB-015 | Back / refresh / deep links | partial | Back restores prior route; reload/deep link reconstructs intended screen |

## Music playback and system controls

| ID | Task | Current web evidence | Acceptance check |
| --- | --- | --- | --- |
| KB-016 | Play album / selected track | live-pass | Explicit Play starts ordered playable tracks at the selected position |
| KB-017 | Pause / resume / seek | live-pass | Controls match the actual audio state; seek preserves chosen track |
| KB-018 | Previous / next inside app | partial-mini | Previous restarts after threshold or moves back; Next advances one track |
| KB-019 | Automatic next at track end | live-and-test-fail | Advance to next queued item, including while backgrounded; stop only at queue end |
| KB-020 | Repeat off / one / all | test-fail | One repeats current; all wraps; off stops at queue end |
| KB-021 | Shuffle | source-fail | Shuffle upcoming only; preserve current/history; off restores remaining linear order; explicit Shuffle starts a fresh permutation without an immediate identical repeat when alternatives exist. Preserve every entry. |
| KB-022 | Queue row selection | test-fail | Selecting a row updates active cursor; Next/Previous continue from it |
| KB-023 | Queue add / next / remove / clear | partial | Maintain current identity/cursor and predictable subsequent playback |
| KB-024 | Queue restore after reload | live-fail | Restore queue, item, position and modes per account; avoid unwanted autoplay |
| KB-025 | Sleep timer replace / cancel | test-fail | Only the current timer may pause; canceled/replaced timers cannot fire |
| KB-026 | Playback speed | source-present | Correct rate and clear indication, respecting music/book context |
| KB-027 | Music lock-screen / headset | user-iphone-fail | Music exposes previous/next track, seek and actual playback state |
| KB-028 | Audio interruption / background | physical-test-needed | Calls/headphones/network interruptions preserve state and recover predictably |
| KB-029 | Lyrics and credits | not-found | Real synchronized lyrics and attributable full ordered credits |
| KB-030 | Volume / output / normalization | partial | Accessible volume and honest output/quality; platform-specific audio options explicit |
| KB-031 | Playback history / reporting | not-found | Record actual listening once; preserve offline reporting and prevent duplicates |

## Collection actions and menus

| ID | Task | Current web evidence | Acceptance check |
| --- | --- | --- | --- |
| KB-032 | Favorite / unfavorite | source-fail | Persist to account/library and show failures; reloading/other clients agree |
| KB-033 | Playlist create / edit / add / remove | not-found | Same durable playlist operations; navigation never starts playback |
| KB-034 | Mix / radio | partial | Explicit actions from track/album/artist with real resulting queue |
| KB-035 | Track / album / artist context menu | not-equivalent | Expose task-relevant navigation, queue, collection and download actions consistently |
| KB-036 | Sharing and exports | not-found | Portable deep links/state exports without exposing credentials |
| KB-037 | Deletion actions | decision-needed | Only explicit scoped deletion; safe confirmation/recovery, never automatic matching cleanup |

## Offline and acquisition

| ID | Task | Current web evidence | Acceptance check |
| --- | --- | --- | --- |
| KB-038 | Download music / monitor / lock / remove | not-found | Retain native offline; PWA browser limits explicit; safe progress and removal |
| KB-039 | Connection loss and retry | source-gap | Show outage honestly; preserve cached/local data and avoid silent empty-success |
| KB-040 | Request album / status | source-fail | Confirm server acceptance; show real state and disabled dispatch; failure must not say requested |
| KB-041 | Identity and availability | partial | Do not infer ownership from title; distinguish ambiguous/no candidate/partial/full |
| KB-042 | Metadata and media safety | backend-source-gap | Staging/backups/audio integrity/atomic logical rollout/rollback before publishing |
| KB-043 | Spotify reconciliation | not-established | Reviewable identity/version mappings; retain unmatched items; no invented sources |

## Books and audiobooks

| ID | Task | Current web evidence | Acceptance check |
| --- | --- | --- | --- |
| KB-044 | Browse work / edition / formats | partial | Trustworthy title/author/narrator/cover and exact availability |
| KB-045 | Read actual EPUB | live-fail | Render the selected EPUB chapters; never unrelated placeholder prose |
| KB-046 | Reading controls and contents | partial | Chapter navigation, font/theme, contents and meaningful reading position |
| KB-047 | Listen selected chapter | source-fail | Chapter selection changes audio position/track instead of restarting the whole book |
| KB-048 | Reading/listening progress | source-gap | Persist actual position per account; define offline/reconnect conflict rules |
| KB-049 | Read here / listen here | source-fail | Use evidenced edition alignment, expose uncertainty; never advertise an unimplemented handoff |
| KB-050 | Bookmarks / annotations | not-found | Persist and recover actual locations; expose supported operations |
| KB-051 | Book offline downloads | not-found | Actual asset storage, integrity and offline continuation; browser limits explicit |
| KB-052 | Request book and status | partial | Request correct format with validated response and real lifecycle |

## Device continuity

| ID | Task | Current web evidence | Acceptance check |
| --- | --- | --- | --- |
| KB-053 | Truthful device awareness | source-fail | Current state, stale-device handling, account isolation and accurate paused/playing |
| KB-054 | Remote controls / queue handoff | not-found | Transfer queue/item/position/modes with acknowledgement, source stop and failure recovery |
| KB-055 | Preference sync | local-only | Shared preferences round-trip through account; platform-only preferences remain scoped |

## Quality, settings and operations

| ID | Task | Current web evidence | Acceptance check |
| --- | --- | --- | --- |
| KB-056 | Shared visual language | no-shared-contract | Same shared tokens/interaction semantics; platform-adaptive layouts, not forced identical geometry |
| KB-057 | Accessibility / keyboard / text size | source-gap | Named controls, keyboard entry/focus, readable scaling and screen-reader routes |
| KB-058 | Settings groups | not-equivalent | Expose useful user tasks consistently; hide implementation plumbing; platform-only options documented |
| KB-059 | Error / loading / empty / artwork states | partial | Each state distinct, useful and recoverable with truthful data |
| KB-060 | Logs / bug report | source-present | Real diagnostic submission with privacy filtering and visible failures |
| KB-061 | Release / deploy / rollback | unversioned-source-gap | Versioned sources, reproducible builds, tested updates and safe rollback |

## Evidence record per task

For each platform record **pass / fail / blocked / intentionally different**, tested source/image revision, device/OS/browser, steps, actual vs expected, and screenshot/log/test. An intentional difference needs a product reason, equivalent outcome and no silent capability loss.

Audio minimum fixture: ordered queue A→B→C→D; explicit Next; natural ended; Previous at 1s/5s; repeat off/one/all; selected queue row C then Next D; shuffle completeness; cancel/replace sleep timer; reload recovery; media error; background/lock-screen/headset. Music uses previous/next-track semantics; books may use contextual seek semantics.

## Source coverage

| Kind | Count |
| --- | --- |
| Native settings control | 45 |
| Native menu | 16 |
| Native menu support component | 9 |
| Native menu entry | 23 |
| Native screen | 52 |
| Web UI/state/API files | 33 |

All paths, hashes, routes and composed native menu entries are in `agents/workflow-parity.json`. This file-level inventory prevents whole screens/menus being overlooked; it does not certify every dynamic menu branch.

## Repeatable player regressions

`../../scripts/web_player_regression.cjs` loads the actual web PlayerProvider TSX with TypeScript and isolated React/audio stubs. The audit run found 2 passing and 4 failing checks: auto-next, repeat-one, queue selection cursor and canceled sleep timer. These are component-contract tests, not Safari or physical-device tests. The expanded patched-source suite now has 14 passing checks, including shuffle permutations and anti-repeat behavior. Retain the physical iPhone checks.
