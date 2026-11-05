# KB Music product constitution

KB Music should offer the beauty, ease, reliability, and continuity of Apple Music
and Spotify while leaving people in control of their media, metadata, server,
and choice of clients. Finamp is the playback foundation, not the limit of the
product. This document defines direction and decision invariants; it is **not a
list of shipped capabilities**. Evidence belongs in [CURRENT_STATE](docs/CURRENT_STATE.md).

## One beautiful product, everywhere

Build a gorgeous, seamless, native-quality experience on iPhone, iPad, macOS,
and the web PWA. Web must visually match native: the same product identity,
design tokens, typography hierarchy, artwork treatment, navigation concepts,
mini-player, and interaction semantics. Adapt layout to touch, pointer, keyboard,
screen size, accessibility, safe areas, and platform conventions without creating
an unrelated website. Shared tokens and reference screenshots are contracts;
independent implementations must demonstrate parity rather than assume it.

Album cover/title taps open album details. They never shuffle, start playback,
replace the queue, or interrupt the current track. Play and Shuffle are explicit,
separate actions. Artist and book navigation likewise opens details. Loading,
empty, missing-artwork, offline, and error states receive the same design care
as populated screens. Prefer restrained, fast, accessible interfaces over visual
spectacle. Improve design in coherent, reviewable steps; preserve playback.

## Continuity without lock-in

One account should connect clients to the user's server with elegant, minimal
onboarding, without asking ordinary users to manage internal provider keys.
Library state, favorites, preferences, and reading/listening progress should
follow the account with defined conflict and offline reconciliation behavior.
Spotify Connect-like continuity means truthful active-device awareness, current
playback state, remote controls, and explicit transfer of queue, order, current
item, position, and playback modes. Prevent duplicate playback and acknowledge
handoff success or failure. Device enrollment, pairing, heartbeat/presence, state
sync, queue transfer, and synchronized multi-room playback are **distinct
capabilities**. Prove each separately on real clients before claiming support.

Native offline downloads, queues, playback, and later reporting must survive
catalog/account/provider outages. A PWA's browser limitations must be explicit;
do not remove native capabilities to manufacture parity. Reconnecting must not
silently overwrite newer progress or discard local work.

## Own the ecosystem

Use open, portable identities, documented interfaces, exportable state, and
ordinary media formats. Keep Jellyfin, Audiobookshelf, and alternate clients
useful; metadata and library organization must not require KB Music to decode
them. Respect upstream MPL-2.0 notices and dependency licenses. Keep server,
native, and web contracts maintained together, with explicit version compatibility
and coordinated tests across separately deployed sources.

Music Assistant and Home Assistant are optional integration candidates, never
assumed prerequisites for account, playback, offline access, or device handoff.
Research supported transports/players and prototype interoperability before an
architecture decision. Neither product's existence proves KB clients implement
Connect-like handoff. See [research](docs/agents/RESEARCH.md).

## Metadata worthy of the collection

Seek the richest accurate album, edition, release-track, recording, artist,
ordered credits, artwork, lyrics, and contributor metadata possible. Preserve
original release chronology, edition distinctions, artist identity, and source
provenance. Confidence comes from evidence, not a plausible title, generated
text, a provider's popularity, or a single matching field. Model conflicting
sources, uncertainty, manual corrections, and refresh history explicitly.
Never invent MBIDs, credits, availability, lyrics, sourcing, or coverage claims.
Graceful missing metadata is better than confidently wrong metadata.

Global discovery and local availability are separate: discovering a recording
does not mean the user owns that edition or can play it. Keep provisional local
identities playable when public IDs are absent. Do not merge different artists
with the same name or choose arbitrarily among ambiguous recordings.

## Safety is part of elegance

Enrichment and acquisition should be simple to use because the system handles
failures safely. Stage changes away from good media; retain evidence, backups,
and a recoverable journal. Validate identity, edition, completeness, container,
artwork, and media integrity before publishing. For tag-only audio edits verify
the decoded audio hash or an appropriate lossless audio signature before/after;
a whole-file hash changes with tags and cannot prove audio preservation.

Publish a validated logical release atomically, with a tested rollback and
restart/retry recovery. An atomic rename of one file does not establish atomic
multi-file rollout or backup safety. On uncertain matches, unavailable providers,
interrupted jobs, failed verification, or rollback failure, preserve the last
known good media and metadata. Never delete or overwrite good media to resolve
uncertainty. Retain recoverable staging for diagnosis instead of broad cleanup.

Acquisition is an explicit, scoped, server-side operation with idempotent requests,
real observable states, bounded resource use, and verified authorized sources.
A queued request is not a download. Spotify reconciliation should preserve
favorites/playlists, distinguish exact versions and unmatched items, and offer
reviewable mapping; Spotify metadata is not evidence of a downloadable source.
Do not expose administrative credentials to clients or start broad acquisition.

## Music and Books, equally considered

EPUB reading and audiobooks belong to the same polished ecosystem: accurate
work/edition/author/narrator identities, covers, chapters, offline access,
annotations, progress, and explicit reading/listening continuation. Pair formats
only with trustworthy edition/alignment evidence; expose approximate alignment
as approximate. Preserve Audiobookshelf interoperability and independent formats.

macOS should retain traditional downloadable GitHub DMG releases and safe
upgrade-in-place behavior. Optional automatic updates must verify artifacts,
preserve user data/downloads, and have a tested recovery path. Source files,
an appcast, or an uploaded artifact alone do not prove distribution works.

## What quality means

A feature is finished when its behavior, failure recovery, accessibility, visual
parity, and relevant device/server integration have evidence at the tested
revision. Mocks prove narrow contracts, not deployed capabilities. Never substitute
screenshots of mock data, seeded activity, placeholder handlers, or generated
feature descriptions for a working product. Record failures and untested platforms
openly. Use [quality gates](docs/agents/QUALITY_GATES.md) for acceptance, and
[decisions](docs/DECISIONS.md) for architecture tradeoffs, without turning this
constitution into an implementation backlog.
