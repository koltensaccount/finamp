# Live request and automation checks — 2026-11-05

Build209 installed; user completed normal KB login. Native Aimee Mann search
returned a result and artist detail loaded successfully without Keychain prompts.
94 Flutter tests pass. Stable local signer; not Apple-notarized.

| Check | Result | Evidence |
| --- | --- | --- |
| Core API credentials | pass for sampled endpoints | Catalog, Books, Jellyfin System/Info, Audiobookshelf libraries, Lidarr status, slskd application returned200. Not every route or provider. |
| Music search | pass sample | Server search200, one Aimee Mann result; native search and detail verified after sign-in. |
| Books search | pass sample | War of the Worlds search200,15 results. |
| Album request | FAIL download acceptance | Live request5 accepted200, state queued, dispatch_enabled false. Deployed handler records requests without dispatching. No album download claimed. |
| Paired book request | pass server acquisition/file presence | Explicit test breq-b6b4e0c37467, The War of the Worlds by H.G.Wells. Both formats available100%. Published assets:1 EPUB,27 MP3s,380801792 bytes, no missing files. EPUB ZIP/mimetype validated;27 MP3 headers/durations parsed,23747 seconds total. |
| Read/listen on clients | not verified | File/header validation is not full decoding, audiobook listening, EPUB content correctness, alignment, offline download or cross-platform certification. ffprobe absent; used mutagen instead. |
| Platforms | incomplete | Native Mac runtime verified. Prior deployed-web playback evidence exists. No new physical iPhone/iPad or web request-to-download UI checks. |
| Personalized ranking | pending implementation | User requests gentle account-specific familiarity boost from library/listening/search, with relevant new artists retained. Not implemented or represented as shipped. |

Server probes and explicit test submissions used existing server credentials,
not an extracted user token. This is backend automation evidence, not proof that
every client's request UI works. No Keychain password reads repeated. Test
requests and downloaded public-domain book are retained; no cleanup, broad
monitoring, acquisition enablement, migration, or unrelated automation changes.

Remaining release blockers: connect album-request handler to safely scoped
acquisition and prove an unowned album reaches playable availability; verify
both book formats through native and web UI; physical device checks; implement
and validate shared personalized ranking. The product is not fully certified.
