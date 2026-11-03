# Current state

Owner: Codex, branch `codex/catalog-identity`. Upstream baseline: tag 1.0.2.
Fork: https://github.com/koltensaccount/finamp ; upstream remote retained.
No playback/UI source was changed. Stable baseline/license remain intact.

Implemented: SQLite identity graph; cache ingestion; read-only Jellyfin sync;
hash-based incremental updates; five-minute standalone watcher; conservative
availability; album edition/partial ownership; ordered artist credits; local
provisional identities; authenticated loopback catalog HTTP API; request outbox
with acquisition disabled; actual evidence demonstrations and regression tests.

Initial live index: 8,976 Jellyfin Audio items; 2,332 verified public mappings;
6,644 local-only playable identities; 945 ambiguous candidate links. Catalog
contains 3,117 public recordings from existing expanded release evidence.
26 live paths added after the old inventory all exist: BEAUTIFUL DAY (15) and
99 Luftballons (11). No old inventory paths are absent from Jellyfin.

The 9,226 backup count was all files, not audio: 8,951 audio-looking paths
include one macOS `._…flac` resource fork. Actual audio at that snapshot: 8,950.
275 other files include artwork, Finder metadata and other sidecars. The mapping
refresh excludes resource forks. No new audio audit was required.

Live examples: Melodrama fully mapped (11/11); Revenge partially mapped (6/8);
The Life of Pablo has zero confident mappings in the current evidence, which
does NOT certify physical absence. Multiple editions and collaboration credits
are represented. Missing-ID and import transitions are covered by tests; a
real API item was also replayed through an isolated in-memory import transition.
No acquisition was triggered to manufacture a new import demonstration.

Verified: 13 backend tests, including authenticated HTTP search/request/status/
import availability slice. Live Jellyfin API pagination and evidence ingestion
passed. Production media and application settings were not changed for this app.

Latest drift-aware refresh saw 8,977 items (27 above the old inventory),
demonstrating a new live item appearing during development. Public search for
Green Light returned one confidently available recording alongside unavailable
catalog recordings through the same result contract. Both initial GitHub
Catalog identity CI runs passed. Main is protected against force pushes and
deletion and requires catalog-tests. Its stable baseline is 1.0.2.

Not complete: iOS UI connection, physical-device installation, full absence
demonstration, live acquisition request dispatch, public catalog detail hydration,
reconciliation of all provisional identities, automatic secondary-match promotion,
whole-library metadata completeness. Don't represent these as working features.

Build blocker: no Flutter on PATH and no usable full Xcode/simulator toolchain.
Upstream pins Flutter 3.47.7 via .fvmrc/.flutter-version. Its `flutterw` fails
because `.flutter` is not a registered submodule in this release checkout.
Do not modify Apple credentials/certificates or rewrite playback to work around
the missing toolchain. iOS minimum in upstream Podfile is 15.0.

Server runtime data stays in `~/music-metadata-audit/catalog-index/`, excluded
from Git. Original backup/enrichment workers are independent and untouched.
