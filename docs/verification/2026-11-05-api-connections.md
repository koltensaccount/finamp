# API connections and session recovery

Date: 2026-11-05. User screenshot: catalog artist returns authentication failure
while Jellyfin playback works. User later identified an incorrect password.

## Observed system state

Read-only authenticated checks returned HTTP200 for catalog search, Books list,
Jellyfin System/Info, Audiobookshelf libraries, Lidarr system status and slskd
application. Jellyfin Users/Me returned 400; System/Info is the successful service
credential check, not proof that every Jellyfin user endpoint works.
Account status returned200. Saved Mac account/catalog tokens matched each other,
but requests to account devices/sync and catalog/Books returned401. Neither saved
access-token nor refresh-token hash matched the live account database. No token
values are included here. The cause of the stale session is not established.

The API process start time precedes the source file modification by roughly one
second. This alone does not prove stale code; no restart was performed. Books'
ABS_TOKEN environment alias is absent, but the existing source fallback matches
the configured AUDIOBOOKSHELF_TOKEN and authenticates successfully. Embedded
credentials remain a previously identified security/deployment debt; no key
rotation or broader privilege changes were performed.

## App fixes and acceptance

- Server refresh returns flat token/refresh-token/expiry fields. Client previously
  treated it as the full login/config envelope. Preserve account/device identity,
  rotate session and matching catalog credentials, and single-flight renewal.
- Catalog and Books GET/HEAD requests retry once after401 with the renewed account
  token. Never replay writes/acquisition requests or replace manual API keys.
- API reads await account initialization without blocking the first app frame. Failed
  renewal gives an actionable sign-in message. Artist and Account screens expose
  Sign In Again without deleting offline media or signing out other devices.
- Incorrect-password errors remain on the login form (existing widget regression).

Validation: full Flutter suite **89 passed**, including four added renewal/retry
regressions. Explicit live session renewal/fresh sign-in, artist reload and Books
using a newly authenticated Mac session require runtime verification. A200 service
probe does not certify acquisition, metadata-provider coverage, Spotify OAuth,
Apple Music setup, Books correctness, full visual parity or device handoff.
No downloads, media writes, migrations or server configuration changes.

Build206 runtime check caught black-window startup when account initialization
was awaited before runApp. Superseded by207: initialization gates API reads,
not rendering. No startup completion claim is based on the build alone.
