# Decisions

## 2026-11-05 — choose the best common workflow

- Per the user's clarification, choose efficient, effective task workflows first,
  then align native and web to them. Neither implementation is an unquestioned
  reference. Track intentional platform differences explicitly.
- Start with reliable ordered playback and clear previous/play-pause/next controls.
  Retain Finamp's engine; fix web event/state handling rather than replacing both.
- The complete discovered surface inventory and 61 task contracts are in
  [WORKFLOWS](WORKFLOWS.md) and its machine-readable companion. Source presence
  is not runtime proof; require actual cross-platform checks before parity claims.

## 2026-11-05 — canonical intent and evidence

- VISION.md owns stable product intent; AGENTS.md owns the common workflow.
  Assistant adapters reference the same policy. Scoped guides supply local rules.
- Retire blanket “No visual redesign” and acquisition-before-polish ordering:
  premium native/web parity is active scope; playback/offline regressions remain
  unacceptable. Preserve Finamp's engine while improving presentation.
- Shared account, registration, preferences, presence, remote control, queue
  transfer, and synchronized playback require separate evidence. Never infer one
  from another or from a mock test.
- Preserve separate PWA source and generated Next.js guidance; do not create a
  replacement app/repository. Connect it to a synchronized canonical snapshot.
- Music Assistant/Home Assistant remain optional candidates pending a tested
  adapter/transport decision; see [official-source research](agents/RESEARCH.md).
- [Quality gates](agents/QUALITY_GATES.md) and task reports distinguish aspirations,
  code presence, automated evidence and actual system verification.

## Earlier catalog decisions (retained with scope clarified)


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
- No duplicate scrobbling or additional playback engine. The initial visual-redesign deferral was retired on 2026-11-05.
- Full iOS build requires installing/configuring Xcode and pinned Flutter first.
