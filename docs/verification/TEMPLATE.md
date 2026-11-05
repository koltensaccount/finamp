# Verification: <task>

- Date / branch / base and tested revisions:
- Scope and affected clients/services:
- Acceptance criteria (observable behavior and failure recovery):
- Implementation evidence (source paths; presence is not runtime proof):

| Gate | Result: pass / fail / blocked / not_applicable | Evidence and reason |
| --- | --- | --- |
| Automated checks | blocked | Exact commands, exit codes, test counts, exclusions |
| iPhone | blocked | Device/OS, before/after artifact, real vs fixture, physical vs simulator |
| iPad | blocked | Same state and reference comparison |
| macOS | blocked | Same state and reference comparison |
| Web/PWA | blocked | Browser/version, viewport, standalone, native comparison |
| Real service / two-client continuity | blocked | Server revision, conflict/offline/failure behavior |
| Media integrity / rollback | blocked | Temporary fixture hashes, backups, interruption and recovery |

## Failures and limits

List failures, unavailable environments, unverified claims, and concrete follow-up.
For not_applicable, explain why the change cannot affect that gate. Never convert
an unavailable required check to not_applicable. Overall completion: incomplete
until all required gates pass; describe exactly what is verified.
