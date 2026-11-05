# Implementation and evidence workflow

Instructions improve judgment; tests/CI provide mechanical checks. Neither
instruction loading nor this checklist guarantees feature quality.

## Before implementation

Record base revision, workspace, affected clients/services, observed behavior,
expected behavior, acceptance criteria, and the smallest regression case.
Inspect worktrees and actual code. Use [architecture](../ARCHITECTURE.md) to find
owners, then read scoped guides; do not load every document or create a new
architecture from a task description. Treat historical prose as a claim to verify.

## Gates by change

| Change | Required verification |
| --- | --- |
| Guidance/docs only | `python3 scripts/check_agent_guidance.py`; `git diff --check`; inspect discovery adapters and contradictory rules. Runtime screenshots are not applicable unless product behavior changed. |
| Flutter behavior | Pinned Flutter (`.flutter-version`), `flutter pub get`, `flutter analyze`, targeted `flutter test test/<affected>_test.dart`, then full `flutter test`; relevant platform build. Record existing failures separately. |
| UI/layout/navigation | Above plus before/after screenshots of the same real data, route, size, theme, and state on iPhone, iPad, macOS, web; compare typography, spacing, color, artwork, controls, mini-player, empty/error/offline states. Test accessibility, text scaling, touch and keyboard focus. |
| Catalog/API | Safe catalog tests in [backend scope](../../backend/AGENTS.md), relevant contract/HTTP tests, bad/ambiguous IDs, provider outage and failed refresh preserving cached state. |
| Metadata/acquisition | Hermetic fixtures with all roots temporary and all providers stubbed, before/after integrity, backups, retry/idempotency, collision, partial-write/interruption and rollback tests. No live acquisition to satisfy a unit test. |
| Account/sync/handoff | Client contract tests plus two actual clients/server at recorded revisions. Verify revocation/isolation, bootstrap, offline/reconnect/conflict and stale presence; then separately queue order/item/position/modes, transfer acknowledgement, source stop, target failure. Registration alone passes none of these sync gates. |
| Books | Work/edition/format identity, EPUB/audio/offline, progress/annotations, actual reading↔listening alignment confidence and unmatched segments; cross-device continuation tested separately. |
| Distribution | Actual install/update from intended GitHub DMG, artifact verification, preserved account/downloads, failure/recovery path. Build/upload alone does not pass. |
| Separate PWA | Its own dependency-version docs, applicable tests/lint/build, browser/standalone behavior, range seeking/media session/offline limitations, native visual comparison and contract compatibility. Never use inherited Aubrey deployment scripts for KB Music. |

Use the installed pinned SDK or existing wrapper after inspecting its setup;
do not silently upgrade toolchains. Check iOS on a physical device for audio,
background/lock-screen, interruption and offline acceptance; simulator evidence
is useful but cannot replace those checks. iPad/macOS/web each need their own
evidence; a browser resized to iPhone dimensions is not a physical iPhone test.

## Evidence and completion

Copy [TEMPLATE.md](../verification/TEMPLATE.md) to a task report in
`docs/verification/`. Each gate is **pass**, **fail**, **blocked**, or
**not_applicable** (with a reason). Include exact command, exit result, date,
revision, OS/device/browser, source paths, and artifact locations or sanitized
logs. Separate code presence, automated tests, and real-system verification.
Screenshots must identify real versus fixture data. Do not commit private
library inventories, credentials, full server paths, or personal screenshots;
keep sensitive artifacts local and describe sanitized evidence in the report.

If a required platform/system is unavailable, retain **blocked** and specify the
remaining check. Do not mark the feature complete. A reviewable draft PR may be
opened with that limit. Update CURRENT_STATE for capability changes, architecture
for contract changes, DECISIONS for new tradeoffs, and NEXT_TASK for follow-up.
No broad production operations are implied by tests or acceptance criteria.

CI checks document links, adapter structure/size, stale prohibitions, and the
presence of a changed verification report for behavior changes. It does not
validate screenshots or certify truthful prose; review the actual evidence.
