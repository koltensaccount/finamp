# Next concrete task — Antigravity

Branch/worktree: create `antigravity/catalog-client` from Codex's reviewed branch.
Ownership: Flutter client integration only; coordinate before changing backend/.

1. Install/use pinned Flutter 3.47.7 and full Xcode. Run unmodified baseline with
   existing Finamp configuration; record simulator/device results honestly.
2. Add a typed catalog API client and one functional search route, retaining
   existing Jellyfin media, download and queue machinery. Catalog tracks with
   exactly one confident mapping resolve the returned Jellyfin item ID through
   existing API/model code; ambiguous results must not play automatically.
3. Album pages use release-group concepts and edition tracks. Missing items offer
   explicit album requests; single-song option explains unsupported behavior.
4. Display outbox queued state honestly; `dispatch_enabled:false` must never look
   like an active download. Preserve cached/offline navigation.

Expected files: new catalog client/models, existing search navigation touchpoint,
targeted widget/client tests, CURRENT_STATE update. No player rewrite or redesign.

Acceptance: build/test results recorded; one search result plays a mapped local
Jellyfin item; unavailable result submits a controlled request; ambiguity cannot
autoplay; offline Finamp downloads remain reachable without the public catalog.

Separate backend follow-up: scoped acquisition dispatcher with one controlled
request; do not enable broad Soularr monitoring as a substitute.
