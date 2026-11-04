# Catalog identity and application contract

Python standard-library backend + SQLite, separate from existing music tooling.
Finamp remains responsible for authentication to Jellyfin, playback, queues,
downloads, offline playback and reporting. Do not put Lidarr/slskd admin keys
in Dart. The backend's scoped access token is distinct from those credentials.

## Identity graph

Artists have ordered credit edges to recordings, releases and release groups.
Release groups own editions. Releases own ordered disc/position release tracks;
each release track references a recording. Recordings can belong to many
editions and map to many `(server_id, Jellyfin item_id)` pairs. All mappings
retain evidence and confidence. `local:server:item` is a provisional playable
identity, not a fabricated MBID. No audio tags are written.

The read-only refresh imports expanded MusicBrainz responses already cached
by the audit, corrected per-file verification evidence and paginated live
Jellyfin items. Hashes avoid rewriting unchanged API payloads. Completed
snapshots deactivate removed items; failed enumeration preserves the previous
snapshot. The watcher refreshes every five minutes. Catalog evidence is
reused; no fresh media metadata scan or per-track Internet matching occurs.

Verified audit recording identities are confident mappings. Unverified raw
IDs and secondary edition/position/title/credit/duration matches remain
ambiguous. No arbitrary candidate is selected: multiple confidently identified
files require selection; ambiguous mappings expose no Play item. A song without
public IDs remains playable through its provisional local identity.

`available`, `possibly_available`, `not_found`, `pending` are mapping states.
`not_found` means no evidence in the local index, not proof that no untagged
copy exists. Albums count recording availability across their ordered edition
tracks; one recording may be available from another edition. Edition metadata
is preserved rather than silently claiming ownership of the exact edition.

## HTTP contract (v1)

All routes require `Authorization: Bearer <backend token>`. Server binds only
127.0.0.1. Development uses SSH forwarding over Tailscale; remote deployment
needs an authenticated Tailscale/reverse-proxy endpoint before iPhone use.

- GET `/v1/search?q=...`: cached unified artist/album-concept/recording results.
- GET `/v1/search?q=...&refresh=true`: fetch public search evidence, then use
  the same index and response contract. Three sequential provider requests;
  1.1-second spacing, finite timeout, cached successes and failure cooldown.
- GET `/v1/artists/{artist_mbid}`: credited album concepts and recordings.
- GET `/v1/albums/{release_group_mbid}`: one concept with edition availability.
- GET `/v1/releases/{release_mbid}`: ordered tracks and partial ownership.
- GET `/v1/recordings/{recording_id}/availability`: state, candidate count,
  mapped local IDs and a playable ID only for one confident candidate.
- POST `/v1/requests` `{release_id, scope:"album"}`: idempotent local request
  outbox; `{id,state:"queued",dispatch_enabled:false}` is explicit. It does
  not claim a Lidarr search/download has started.
- GET `/v1/requests/{id}`: persisted state. Successful mapped imports can make
  it available. Unsupported song requests fail rather than requesting albums.

The controlled HTTP test verifies search -> request -> request status -> import
reconciliation -> available playback ID. It does not download media.
Live dispatch is intentionally disabled until explicit requests can be kept
separate from existing Soularr wanted-list monitoring. Search results from a
provider outage remain usable from the persistent cache; offline Finamp media
continues through its original systems without this backend.

## Providers and acquisition

MusicBrainz is primary because its open identities align with existing evidence.
Apple Music API adds catalog/artwork but requires developer token/key setup;
it is not configured. Discogs has edition/marketplace strengths, separate IDs
and API/content restrictions; it is not configured. Neither is silently used as
a title-based fallback. No provider offers a guaranteed complete world catalog.

Soularr's current upstream reads wanted albums, defaults to album acquisition,
and can clean completed transfer records after a run. Our prepared configuration
limits a run to one selected release; normal monitoring remains disabled in
this integration. Requests need their own allowlist/dispatcher before enabling
it: existing monitored wants are not evidence of an explicit app request.
Single-song acquisition is not supported by this contract.

Jellyfin's existing ListenBrainz integration and Finamp reporting must be kept
as the single reporting path until deduplication/offline-play behavior is
verified; no second scrobbler was added.

Sources: https://musicbrainz.org/doc/MusicBrainz_API/Rate_Limiting
https://developer.apple.com/help/account/capabilities/create-a-media-identifier-and-private-key
https://www.discogs.com/developers
https://developer.apple.com/help/account/basics/about-your-developer-account/
