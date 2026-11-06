# Engineering contract

Read docs/CURRENT_STATE.md and docs/NEXT_TASK.md and inspect git status before edits.
Baseline: upstream Finamp 1.0.2. Preserve MPL-2.0 notices and existing playback,
queue, offline, lyrics, normalization, reporting and iOS behavior. User-authorized targeted UX redesigns are allowed when they preserve those capabilities; follow docs/UX_PARITY_CONTRACT.md and validate iPhone/iPad/macOS/web parity.
Codex owns backend/catalog identity on codex/catalog-identity. Antigravity should
use its own branch/worktree; do not concurrently edit backend without coordination.
Never commit credentials, library inventories, databases or private server paths.
Backend checks: `python3 -m unittest discover -s backend/tests -v`.
Flutter checks require Flutter and full Xcode; never claim unavailable builds passed.
No production media writes or uncontrolled acquisition. Server binds loopback and
requires bearer authentication. Availability is not inferred from title alone.
