# KB Music project brief

[../VISION.md](../VISION.md) owns the product constitution: a premium, portable,
self-hosted Music and Books experience across iPhone, iPad, macOS, and web PWA.
This fork retains Finamp's native playback foundation and MPL-2.0 notices.

One discovery experience should combine rich public catalog information with
truthful local availability, Jellyfin playback, and explicit server requests.
Books integrates EPUB/audiobooks and Audiobookshelf. Native offline capability
must remain independent of catalog/account/provider availability.

Visual refinement is active product work, with cross-platform comparisons and
behavioral regression checks. The earlier rule requiring all acquisition work
before any redesign is retired. Do not replace the playback engine to restyle UI.

Use [architecture](ARCHITECTURE.md) for source ownership and contracts,
[decisions](DECISIONS.md) for constraints, [current state](CURRENT_STATE.md) for
dated evidence, and [next task](NEXT_TASK.md) for bounded follow-up work.
The [agent contract](../AGENTS.md) defines workflow and scope.

Private Apple development should preserve bundle identity and upgrade in place
to retain downloads. Signing-account/certificate changes are separate work;
profile expiry and restricted entitlements need verification on the actual device.
No production tag edits, broad acquisition, or cleanup are authorized by this brief.
