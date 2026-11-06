# Account and catalog connection failure honesty — 2026-11-06

## Scope and provenance

This is an isolated source-only change on `codex/account-restore-guard-20261106`, based on `codex/kb-agent-guidance-20261105`. It does not include newer local, uncommitted changes from the 1.0.4 build 213 handoff. Compare/cherry-pick after checking the actual local worktree; never reset or replace local edits to apply this branch.

## Corrected source behaviors

- A saved but expired KB token is no longer reported as a successful account restoration if refresh fails or has no refresh token. Existing stored tokens remain untouched for manual reconnection.
- macOS Keychain read denial now produces an actionable catalog error rather than silently being treated as an unconfigured connection. Account init also recognizes the read failure. No Keychain ACL, signing identity, or saved item is modified.
- Account device-list 401/403, server failures and malformed responses now produce errors rather than an apparently successful empty device list. The existing account screen renders its connection error on the caught failure.
- A failed refresh-token callback preserves the original 401 response and message. An unchanged or empty token cannot trigger a duplicate GET. No writes are replayed.

## Regression tests added

- `test/account_connection_failures_test.dart`: expired/revoked session and device API 401/503/malformed response.
- `test/account_retry_failure_test.dart`: refresh exception and unchanged-token retry.
- `test/mac_keychain_read_failure_test.dart`: denied catalog read on macOS (skipped on other platforms).

## Verification truth

**Source inspection and GitHub diff only.** The Flutter SDK, installed Mac build 213, signed DMG, physical iPhone/iPad, deployed web client, and server were not available to this connected GitHub-only review. None of the new tests, runtime screens, Keychain upgrade persistence checks, or builds were executed. This patch is not a fix or certification of persistence through app restart/update.

Before merge, run the pinned Flutter tests (including the macOS-specific test on an actual Mac), analyzer, formatter, app builds, and a non-destructive upgrade-in-place Keychain fixture. Check current local uncommitted work first. Validate reconnect, catalog search, old valid sessions, expired/revoked sessions, offline downloads, and the account device view. No live acquisition or media changes are needed.

Separate unresolved blockers remain: native build 213 runtime validation; actual Keychain persistence; KB-to-Shelfarr/MAM Books request dispatch and seeding obligations; genuine web EPUB reading; old PWA media proxy authentication; and physical-device playback controls. Do not treat this focused patch as a release.
