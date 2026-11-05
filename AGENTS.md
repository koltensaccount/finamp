# KB Music agent entry point

## Start here

Before editing, inspect `git status`, branch/worktrees, then read [VISION.md](VISION.md),
[CURRENT_STATE](docs/CURRENT_STATE.md), and [NEXT_TASK](docs/NEXT_TASK.md).
Read [ARCHITECTURE](docs/ARCHITECTURE.md) and [DECISIONS](docs/DECISIONS.md) for the
area being changed. Establish acceptance criteria and evidence before coding.

## Authority and scope

- Follow system/tool instructions and the user's current explicit request first.
  Within this repository, VISION owns product intent; this file owns the agent
  workflow; scoped guides add area-specific constraints; architecture/decisions
  describe contracts; current state records dated evidence; next task is a
  proposed work item, not permission to deploy or acquire media.
- Reconcile contradictions in their owning files. Historical reports and old
  task ordering do not prohibit visual improvements. No blanket redesign ban
  remains; make deliberate, tested improvements that preserve playback.
- GEMINI/Claude/Copilot entry points are adapters to this contract, not separate
  policies. Do not copy the vision into competing editable documents.
- Read [lib/AGENTS.md](lib/AGENTS.md) for client/UI work and
  [backend/AGENTS.md](backend/AGENTS.md) for catalog, metadata, Books, or server work,
  even if your assistant does not automatically discover nested instructions.
  For the separate PWA use [web guidance](docs/agents/WEB_WORKSPACE.md).

## Non-negotiable working rules

- Preserve MPL-2.0 notices and Finamp playback, queue, offline, lyrics,
  normalization, background controls, reporting, and iOS behavior.
- Album taps navigate without changing playback. Both clients follow the [shared workflow contract](docs/WORKFLOWS.md);
  neither client is the automatic standard for behavior or design.
  Device registration is not cross-device playback. Never claim untested features.
- Preserve user changes; use a separate work branch/worktree. Check concurrent
  work rather than assuming permanent ownership by an agent or branch name.
- Never commit credentials, databases, media inventories, signing keys, or private
  server paths. Never run broad production media writes, cleanup, acquisition,
  account changes, migrations, or deployment as a side effect of development.
- Preserve good media/metadata on uncertain matching or provider failure. Keep
  global discovery separate from local ownership and playable identity.

## Verify and hand off

Use [QUALITY_GATES](docs/agents/QUALITY_GATES.md) for task-specific commands,
visual/device checks, and the evidence format. Run `python3 scripts/check_agent_guidance.py`
for guidance changes. Backend tests need the safety instructions in the scoped
backend guide; do not blindly run acquisition tests against a real server.
Flutter is pinned by `.flutter-version`; unavailable checks are blocked, never passed.

For behavior changes, add a report under `docs/verification/`, update affected
status/contract docs, and include tests, screenshots, real-system evidence,
failures, and remaining limits. Report implemented, automated-tested, and
real-system-verified separately. A draft PR may expose gaps; a feature cannot
be called complete while its required gates are failed or blocked.
