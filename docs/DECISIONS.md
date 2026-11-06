# Decisions

- Stable Finamp 1.0.2, not an arbitrary development tip. Preserve upstream history.
- Identity mapping precedes UI search. Recording/edition/position/concept are
  separate entities; trustworthy IDs outrank heuristic matching.
- Unverified local items get provisional identities and remain playable locally.
  They do not make similarly titled public recordings falsely available.
- Album concepts use release groups; edition choice remains explicit. No guessing
  between multiple recording candidates or local versions.
- SQLite + standard-library backend reuse audit caches and avoid recurring AI.
- Authenticated loopback development API; no administrative credentials in app.
- Requests persist in an outbox but do not trigger Soularr. Dispatch needs an
  explicit-user allowlist separate from optional wanted-list monitoring.
- No duplicate scrobbling or additional playback engine. Targeted, user-authorized UX parity improvements across phone/tablet/desktop/web started 2026-11-06; see docs/UX_PARITY_CONTRACT.md.
- Full iOS build requires installing/configuring Xcode and pinned Flutter first.
