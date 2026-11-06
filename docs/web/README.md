# Existing PWA workflow changes

The PWA remains the existing server-side application; no replacement app or
repository was created. Its full source is not versioned in this fork. This
folder preserves the reviewed, narrow playback patch and expected before/after
SHA-256 hashes so the server-only changes are reviewable and recoverable.

Applied to the existing source on 2026-11-05 with hash guards and a local backup;
subsequently built from an allowlisted Docker context excluding environment files
and account databases, and deployed
after a loopback canary, with the prior container retained for rollback. Native compact controls live
in the Flutter source in this same change. The common target is in
[WORKFLOWS](../WORKFLOWS.md), not whichever client happens to have a feature first.

## Reproduction

Against a copy of the existing web workspace, verify every hash in
`patches/2026-11-05-playback-hashes.json` is the `before` hash. Apply
`patch -p1 < 2026-11-05-playback.patch`, then require all `after` hashes to match.
Do not apply blindly to newer files or run inherited Aubrey deployment scripts.

Run the actual source through the isolated player regression harness:

```sh
node scripts/web_player_regression.cjs /path/to/existing-web/src/context/player-context.tsx /path/to/typescript/lib/typescript.js
```

The harness uses the actual PlayerProvider with isolated React/audio/timer
adapters; it does not validate Safari, media decoding, background behavior or
server authorization. TypeScript 5.9.3 was used in this audit; dependencies were
reused from an existing local installation, not installed on the production host.
The initial six checks gave 2 pass/4 fail; the expanded post-patch suite has
14 passing checks, including music/book system actions and repeat/previous and shuffle permutation/anti-repeat behavior. Do not treat the local-like assertion as durable
favorite synchronization.

The actual server Docker build used npm ci and passed. A canary and production
root/manifest/service-worker health checks passed; natural track advancement,
visible shuffle order, selected-row Next and phone controls passed browser checks.
Before claiming full parity: test matched native/web visuals and real iPhone
lock-screen/headset/background behavior. Retain the saved image/container rollback. The app's
account-proxy access and placeholder Books reader are separate open blockers.

The PWA cache update prefers fresh navigation HTML, retains offline shell fallback,
and removes only obsolete KB Music caches. Four isolated cache tests pass.

## Recorded rollout

The exact build/rollout scripts used are retained in `rollout/`. They are
historical, guarded scripts with single-run IDs and `/tmp` inputs, not a generic
auto-updater. Do not rerun them blindly: inspect the current source/container,
recreate the hash inputs and review configuration before any subsequent rollout.
They exclude account/env files from the build context, use a loopback canary,
preserve the prior container, and roll back automatically on promotion failure.
No inherited Aubrey script or Compose configuration is used.

Pre-existing service-token literals in the PWA source remain an audited security
gap; excluding environment files does not remove those literals. No credential
rotation or claim of credential-free source is made by this change.
