# Verification: durable KB Music agent guidance

- Date: 2026-11-05 (America/Chicago).
- Branch: `codex/kb-agent-guidance-20261105`; published base: `e4cfe444`.
- Tested revision: initial implementation commit containing this report; exact
  exported snapshot revision is recorded in its generated manifest. Subsequent
  verification-only commits do not change the exported policy.
- Scope: guidance, documentation reconciliation, structural CI/evidence checks,
  web snapshot exporter, and isolation of an existing acquisition regression.
  No Flutter behavior or production media/server application code changes.
- Acceptance: one canonical product vision; compatible assistant entry points;
  explicit scope/precedence; honest status and gates; existing PWA receives same
  policy without deleting its Next.js rules or deploying product changes.

## Evidence

| Gate | Result | Evidence |
| --- | --- | --- |
| Research before edits | pass | Official sources and design rationale in `docs/agents/RESEARCH.md`; fetched before repository edits. |
| Existing source/worktree audit | pass | Published base inspected plus local branch tip `202eb017`, two commits ahead. Existing worktrees clean at audit; newer local commits excluded from this PR. No original branch switched or reset. |
| Structural guidance check | pass | `python3 scripts/check_agent_guidance.py` exit 0; local links, scope routing, adapter references and size limits. |
| Checker regressions | pass | `python3 -m unittest discover -s scripts/tests -v`: 4 tests; missing/removed evidence and broken adapters/links detected. |
| Catalog tests | pass | `python3 -m unittest discover -s backend/tests -p 'test_catalog.py' -v`: 13 tests; `test_reconciliation_identity.py`: 5; `test_discography.py`: 8; `test_http.py`: 1. All exit 0. HTTP test emitted an existing ResourceWarning for a handled 401. |
| Acquisition test isolation | pass | `python3 -m unittest discover -s backend/tests -p 'test_book_discovery_and_acquisition.py' -v`: 3 tests, exit 0. Injected fixture coordinator, generated EPUB, temporary output roots, stubbed metadata/provider/scan calls and asserted zero urlopen calls. No real media acquisition. |
| Full backend suite | blocked | Other tests can still contact metadata providers; not represented as an audited offline suite. Narrow suites above were run. |
| PWA source/deployment audit | pass | Existing server workspace found; original AGENTS contains only generated Next.js block. Container uses local KB image with no Compose project labels. Adjacent Compose/update script targets Aubrey, recorded in WEB_WORKSPACE. Source/image equality is unverified. |
| Web snapshot export/install | pass | Exported and installed canonical `66595d135c6db57245caea5dc643c47db2ad2880`; all 17 SHA-256 entries verified locally and on server. Root VISION links to snapshot; GEMINI/CLAUDE/Copilot route through preserved root AGENTS. Original Next.js block retained. Original AGENTS backup: `.kb-guidance-backups/20261105T225320Z/AGENTS.md`. Dockerfile, Compose and update-script hashes unchanged. |
| Exporter drift detection | pass | Modified VISION in a temporary exported copy; `--verify` exited nonzero with `Guidance drift: VISION.md`. |
| Assistant discovery | blocked | Filename/scope conventions checked against official and installed Antigravity docs. Codex CLI 0.162.1 present; other CLIs unavailable on PATH. No fresh interactive assistant adherence test performed. See RESEARCH for smoke checks. |
| iPhone / iPad / macOS / web screenshots | not_applicable | This change does not alter UI. Existing product parity and real-device behavior remain unverified, not passed. Future UI changes require the full matrix. |
| Real two-client playback handoff | not_applicable | No sync implementation changed; account registration is explicitly distinguished from handoff. |
| Production media integrity / rollback | not_applicable | No production media writes or acquisition. Fixture EPUB publication is tested, not claimed as audio-hash or whole-release rollback proof. |

## Failures and limits

This implements an agent guidance system, not the aspirational product features.
Structural checks cannot certify model obedience or screenshot quality. Branch
protection/repository settings are unchanged, so the new CI job is not claimed
as a required merge check. Existing historical CURRENT_STATE claims are retained
and clearly labeled; this change does not recertify them.

The base branch advanced to `202eb017` during this work; the three-dot PR diff
was inspected against it and contains only the 23 intended files, with no
reversion or inclusion of those two independent native/update commits.

The account service and PWA are server-only source, outside this fork's Git
history. PWA deployment artifacts contain inherited Aubrey configuration; no
Compose/update/rebuild command was run. Existing embedded service credentials
were not used or copied into the new guidance; credential remediation/rotation
requires separate work. Do not attach private source dumps to a public report.

Overall: documentation/tooling implementation is reviewable; live assistant
adherence, product visual parity, handoff and release behavior are not certified.
