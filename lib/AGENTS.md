# Client and interface scope

Apply the root [agent contract](../AGENTS.md). This guide covers Flutter client,
platform integration, and UI changes; read it explicitly from root-launched agents.

- Reuse Finamp's player/download/reporting services. An outage in account/catalog
  must not disable downloaded media. Do not add a duplicate scrobbler or player
  to make a new screen work.
- Preserve album navigation without autoplay/queue mutations. Relevant owners:
  `components/MusicScreen/item_wrapper.dart`, `screens/catalog_album_screen.dart`,
  and `services/catalog_playback_helper.dart`.
- Reuse theme and navigation owners (`services/theme_provider.dart`,
  `components/navigation/`) before adding styling. `docs/design_references/` is
  inspiration, not proof of current cross-platform parity or a token specification.
  Change shared design choices coherently and compare the matching PWA screens.
- Account owner: `services/kb_account_service.dart`; catalog credentials and API
  have separate services. Mocks of pairing/devices do not prove preference sync,
  live device awareness, remote playback, or queue handoff.
- Books owners: `services/books_api_client.dart`, `services/books_download_service.dart`,
  `screens/epub_reader_screen.dart`, `screens/audiobook_player_screen.dart`.
  Distinguish within-book format alignment from transfer between devices.
- Use pinned Flutter, meaningful unit/widget regressions, relevant platform
  builds, and the visual/real-device matrix in
  [quality gates](../docs/agents/QUALITY_GATES.md). Never change bundle IDs,
  signing accounts, or remove downloads to get a test installation working.
