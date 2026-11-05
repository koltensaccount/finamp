# Existing web/PWA workspace

Inspected read-only on 2026-11-05: the Ubuntu server's existing `kb-music-web`
source directory (in its login user's home), not a new application or repository.
It has no `.git` directory. No separate matching GitHub repository was found;
that is a discovery result, not a requirement to create one.

## Source owners and deployment provenance

- Next.js 16.4.2 / React 19.3.0 source: `src/app`, `src/components/views/`,
  `src/context/player-context.tsx`, `src/context/auth-context.tsx`,
  `src/context/device-context.tsx`, and `src/app/globals.css`.
- Server proxy routes: `src/app/api/account/[[...path]]/route.ts`, catalog/Books/
  Jellyfin proxies, image and range-stream routes. Account implementation also
  lives separately in the server catalog-index workspace. Never copy secrets.
- Native parity: compare these views with Flutter at a recorded revision; CSS
  hardcoded colors/layouts and Flutter theme code are independent, not proven
  shared tokens. Album detail and navigation callbacks exist; the reported
  album-shuffle regression still needs runtime verification across entry points.
- Running Docker container `kb-music-web` uses local image `kb-music-web`,
  working directory `/app`, and a SQLite bind mount. Compose project labels
  were absent. Do not infer it is managed by the adjacent Compose file.
- Dockerfile builds a standalone Next app with Node 22 and serves on port 3300.
  Current `docker-compose.yml` and `scripts/auto-update.sh` still target
  **Aubrey Rankings**, including its database and port 3200. They are inherited
  artifacts, not a verified KB Music deploy path. Never run them for KB Music.
- Source presence and running image are independently observed; build provenance,
  launch command, image/source equality and active auto-update mechanism remain
  unverified. No container rebuild/restart, Compose command, or migration was run.
- Package test/lint/build scripts exist, but tests include inherited Aubrey tests.
  Passing those alone cannot certify music, Books, account, or PWA behavior.

## Common guidance without competing visions

The server workspace receives a generated `.kb-guidance/` snapshot from this
repository, with canonical `VISION.md`, `AGENTS.md`, scoped guides, supporting
docs and a SHA-256 manifest tied to a Git revision. Its root AGENTS preserves
the generated Next.js warning and adds web-specific routing to that snapshot.
GEMINI/CLAUDE/Copilot adapters reference the same root. Do not hand-edit the
snapshot; change the canonical repository and regenerate it.

Generate locally (does not connect to a server or deploy):

```sh
python3 scripts/export_web_guidance.py --output /tmp/kb-guidance-bundle
python3 scripts/export_web_guidance.py --verify /tmp/kb-guidance-bundle/.kb-guidance
```

Before transferring, compare existing AGENTS/adapters and preserve unrelated
rules. Back up replaced guidance locally on the server, install only the
snapshot/adapters, and verify the manifest there. Review `WEB_ENTRYPOINT.md` in
the bundle as the section to append to root AGENTS; never replace Next's block.
Record installed revision and hashes in the task evidence. Future cross-client
changes must verify the web snapshot's revision and refresh it if stale; a local
snapshot cannot track Git changes automatically. This workflow is deliberately
separate from product deployment and media processing.

## PWA-specific acceptance

Read the actual version's Next docs before implementation, retain generated
agent rules, and apply the shared quality gates. Album/title navigation must
preserve queue/playback, independent Play/Shuffle controls must work, and web
must visually match native on corresponding phone/tablet/desktop screens.
Check standalone Safari, MediaSession/background limits, range seeking, session
revocation and offline behavior with real services. Do not claim native offline
parity where browser capabilities differ. Do not assume device registration or
presence endpoints provide queue transfer. Record blocked gates honestly.
