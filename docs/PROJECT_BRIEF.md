# Personal iOS music application

Fork Finamp for one personal, self-hosted catalog: public discovery, local
Jellyfin playback, and explicit server-side album requests. Normal browsing
must not expose separate providers or duplicate search tabs. Preserve existing
playback, queues, offline downloads, background controls, gapless audio,
synchronized lyrics, normalization, playback reporting and iOS behavior.

Mandatory order: functioning upstream baseline; catalog/requests; physical
iPhone testing; then visual refinement. Apple Music-style album types and
chronology, edition grouping, restrained typography/artwork/animation and
Spotify-like discovery are later UI goals, not permission to replace playback.

Use MusicBrainz artist, release-group, release, recording and release-track
identities separately. Missing identifiers must not prevent local playback.
Never resolve a public track by fuzzy title alone. Offer album requests by
default; explicitly reject unsupported single-song requests. Only show real
queued/searching/downloading/processing/importing/available/failed states.
No fictional ETA. Server acquisition and iPhone offline downloads are distinct.

Private iPhone development should initially use a free Apple Personal Team;
retain a stable bundle ID and upgrade in place to retain downloads. No Apple
account/certificate changes here. Expect seven-day Personal Team profile
expiry; restricted entitlements such as CarPlay need separate verification.

Retain MPL-2.0 notices. Use one repository, protected main, separate agent
branches/worktrees, relevant tests and accurate shared state. Antigravity
continues Flutter integration and device tests before redesign. Never commit
server credentials or media inventories, alter production tags, or start broad
acquisition. Keep full evidence on the server and reasoning output compact.

Success: stable baseline builds; one catalog search resolves safe Jellyfin
playback/offline actions; unavailable albums submit authenticated server
requests and later gain availability; failures/offline states remain honest;
another engineer can continue without chat history.
