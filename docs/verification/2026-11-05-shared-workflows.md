# Verification: shared workflow map and first playback corrections

Date: 2026-11-05. Native source base: published `202eb017`; guidance branch
contains the independent upstream changes via a non-destructive merge.

## Acceptance and source changes

- Per user clarification, choose efficient, effective task workflows and align
  both clients. Neither existing client is the automatic standard.
- Inventory: 61 task contracts; 52 native screens, 16 menus, 23 menu entries,
  9 menu helpers, 45 settings controls; 33 web UI/state/API files. Dynamic/native
  OS menus and actual behavior are not certified from file presence.
- Native compact music controls: Previous / Play-Pause / Next, named and 44×44.
  Existing Finamp playback engine/system controls remain in place.
- Existing PWA: bind track-end behavior to current queue/mode; update queue cursor
  on row selection; cancel/replace actual timers; add compact Previous; music
  system actions use track skip while audiobook seek remains contextual; preserve
  actual playing/paused state through presence heartbeats.
- Shuffle now changes real upcoming order, preserves current/history and all entries, restores remaining linear order when disabled, and uses one fresh permutation path for explicit album Shuffle. Four shuffle regressions cover edge random draws and repeated requests. Native source already invokes its real shuffle engine; it was not replaced.
- Web source is still server-only. A five-file patch and pre/post hashes are
  preserved in docs/web; it was applied with hash guards and backups to that
  source. Backup: `.kb-source-backups/20261105T234658Z`; final event-callback refinement backup `.kb-source-backups/20261105T234913Z`. Final shuffle update backup: `.kb-source-backups/20261105T235318Z`. A later guarded rollout is recorded below.

## Results

| Gate | Result | Evidence |
| --- | --- | --- |
| Live pre-fix audit | pass (audit observations) | Home/album navigation preserves active original queue; explicit Next works; non-final track stops at completion; wrong EPUB text; reload loses queue. These do not mean product acceptance passed. |
| iPhone reported controls | fail before patch | User physical screenshot shows 10-second seek buttons, not music track skip. No post-patch physical iPhone test. |
| Web isolated player tests | pass after source patch | `node scripts/web_player_regression.cjs <actual-player-context.tsx> <typescript.js>`: initially 2 pass/4 fail, after 6 pass/0 fail, then expanded to 14 passing checks including music/book system actions, repeat-all and Previous behavior. Covers explicit/natural Next, repeat-one, selected-row cursor, canceled timer, local-like state and shuffle behavior. |
| Native widget regression | pass | Targeted compact-control/player-motion tests: 4 pass. Initial 44px test caught Material's default 48px padded target causing overflow; fixed via explicit touch-target style and rerun. |
| Full native tests | pass | `flutter test`, pinned 3.47.7: 82 tests passed. |
| Native changed-file analysis | pass | Targeted `flutter analyze --no-pub` for the two changed component files and new widget test: no issues. Deprecated color API calls in the touched component were updated without changing alpha values. |
| Web TypeScript | pass with dependency caveat | `tsc --noEmit --project <web>/tsconfig.json`: exit 0 using existing local Next 16.4.2 / TypeScript 5.9.3 dependencies. This is not a clean locked production build. |
| Web lint | partial | Changed player/mini-player files pass. Auth context retains a pre-existing set-state-in-effect lint error and unused catch warnings. No clean full lint claim. |
| API authorization audit | fail | No-cookie/no-bearer GETs to Books, Jellyfin Items and catalog requests return 200 through the deployed PWA. Tailscale limits reachability; no write probes performed. |
| Source installation | pass | All touched source hashes matched, backups created, installed after-hashes matched. Running image was not rebuilt/restarted. |
| Full UI comparison | blocked | Responsive browser captures exist. Installed native app was signed out; no authenticated native/physical iPad side-by-side comparison. |
| Native macOS debug build | pass | `flutter build macos --debug --no-pub`, pinned Rust/Rustdoc and Flutter 3.47.7: compiled KB Music.app. Existing plugin/Swift Package Manager and build-script warnings remain. That debug artifact was not installed; the later release installation is recorded below. |
| Web optimized compilation | partial | Webpack production build exits 0 using existing local Next 16.4.2 dependencies. Default Turbopack fails because reused node_modules resolves outside isolated root; standalone tracing warns about external dependencies. Not a clean locked deployable artifact. |
| Web locked production build and rollout | pass | Allowlisted source context excluded .env.local/account databases. Server Docker npm-ci build passed; loopback canary and production root/manifest/new-service-worker checks passed. Previous container retained for rollback; mounts and credentials unchanged. |
| Post-deploy browser playback | pass | Existing sign-in restored. Seeking Charmer to its end automatically started Disappeared; visible queue shuffle retained 11 entries and current/history; selecting Labrador then Next followed the shuffled next row Living a Lie. Phone mini-player exposes Previous / Play-Pause / Next. Playback paused after tests. |
| macOS DMG | pass | Release 1.0.4 (205; supersedes 204), universal x86_64/arm64; codesign deep/strict, hdiutil verify, read-only mount, bundle/version/binary comparison and Applications link all passed. Ad-hoc signed, not Apple-notarized. |
| Physical iPhone / full parity | blocked | No real iPhone lock-screen/headset/background or authenticated native/web visual parity claim. |
| Media integrity / live acquisition | not_applicable | No media-library writes, requests, worker starts, migrations or destructive operations. |

## Deployment drift during audit

The running image changed independently during the audit, from initial
`5bba8f3d4efd3fbcd1f2dd3040ecf860279a546fb060fcf98398e66c93b81f4a`
to `b751b6ef8e58001fab453720db4958f17f143e2916dff2d475144aed69bcd6c4`
(started 23:30:44 UTC, before our guarded source installations). No rebuild or
container restart was performed by this task. Final source hashes for all five
patched files were rechecked. The two no-auth read checks for Books/catalog
still returned 200 on the later image. Other initial UI observations are dated
evidence, not recertification of every later image path.

Guidance/workflow checks and five checker regressions pass, including rejection
of a newly added native menu that is absent from the workflow inventory.

## Guarded rollout and macOS artifact

Final web source revision: `b78f4a27c3e6d5a678a1d5816df6230fc3ba4863`.
Final running image: `sha256:6d732fce7c1d8dfa6e7c32d19ad68b91080420ba9b87d162252c86abbc72501c`.
Rollback container retained: `kb-music-web-before-workflows-20261106T000944Z`.
No inherited Aubrey Compose/update scripts were run; no media/account migration,
credential rotation, acquisition or deletion occurred.

A cached old client initially hit a ChunkLoadError. One Reload restored the app
and existing sign-in. The cache update now prefers current navigation HTML and
preserves only the app's intended offline shell; four isolated cache tests pass.
This one-time transition is not represented as a seamless update pass.

The first 1.0.4 (204) preview passed static DMG/signature checks but failed its
initial runtime launch under hardened library validation. A corrected ad-hoc
signature opened successfully; user then reported silent sign-in dismissal.
Build 205 includes the root-navigation correction below. The final artifact and
installed-binary hashes are recorded in the adjacent delivery manifest/receipt.
Bundle identifier remains `com.unicornsonlsd.finamp`; minimum macOS 12.0;
architectures x86_64 and arm64. A separately identified iOS-on-Mac app does not
automatically share its local data with this native build.

Common agent policy snapshot `49959b3b` (22 files) was installed and hash-verified
in the existing web workspace, retaining generated Next.js guidance.

## Open blockers and limits

The audit identifies account-enforcement gaps, placeholder book content and
unsupported paired-sync claims, absent cross-device queue transfer, nonpersistent
web queue/favorites, optimistic request/metadata claims, offline gaps and unproven
publishing rollback. These were not silently marked fixed by the player patch.
No public report includes credential values or private library manifests.

This is a first tested correction and preview release, not full ecosystem parity.
Canonical workflow inventory is a pre-fix audit snapshot; runtime and patch
results live in this report so evidence is not overwritten retroactively.

## Native sign-in correction (build 205)

User reported that password submission dismissed the sheet without feedback.
The login flow owns a nested navigator that does not register the library route.
Successful sign-in now returns a typed result from the root-hosted sheet and
replaces the root login route with library setup. Pairing uses the same root
navigator. Failed requests retain the form and visible error; disposed forms are
not updated. Incomplete account sessions are rejected before persistence.
Three added widget regressions cover success through nested navigation, HTTP401,
and malformed HTTP200. Full Flutter suite: **85 passed**. Test requests use fixture
credentials and mocked services; this does not prove production authentication.

The personal ad-hoc macOS preview requires the app-scoped
`com.apple.security.cs.disable-library-validation` entitlement for embedded
Flutter/Isar libraries. The first build passed static signature verification but
failed at launch under hardened library validation. The corrected preview keeps
system settings unchanged; signed/notarized release requirements remain separate.
See [Apple entitlement documentation](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.cs.disable-library-validation).

Reproducible preview packaging: `python3 scripts/package_macos_preview.py --app
<release-app> --output <delivery-directory>`. This deliberately produces only a
personal ad-hoc preview. UI/test files analyze cleanly; account service retains
the pre-existing unused `_storeDeleteAll` warning.

Installed build 205 from the final DMG; preserved account/download/media data and
retained the previous app as a backup. CUA runtime verification reached
authenticated Home with loaded albums/favorites using the existing saved session.
The fixed fresh-password navigation path is widget-tested, not repeated against
production. Final DMG SHA-256:
`84afaa9513b5a01957247cde783456fd745a8dbe9689ab7c5f257327e96dff5a`.
Source revision: `cd7cffb40d1e25759f19d09ce70e9edf67759209`.
