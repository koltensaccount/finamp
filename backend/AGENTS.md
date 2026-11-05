# Catalog, metadata, Books, and server scope

Apply the root [agent contract](../AGENTS.md). Read this guide explicitly for
server work even when automatic nested discovery is unavailable.

- Music identity owner: `catalog.py`; transport: `server.py`; refresh: `refresh.py`.
  Keep artist/release-group/release/recording/release-track IDs distinct. Preserve
  provisional local playback and ambiguous candidates. Failed enumeration must
  retain the last good snapshot; title similarity never proves ownership.
- Books owners: `books_core.py`, `book_discovery.py`, `book_acquisition.py`,
  `metadata_engine.py`, `alignment_engine.py`, `worker.py`. These can write files
  and contact providers. Function names/docstrings claiming safety are not proof.
- Before any media writer change, use temporary fixtures to prove backup,
  decoded-audio integrity, collision handling, atomic logical rollout, rollback,
  interruption recovery, and provider-failure preservation. No production writes
  or worker starts are authorized by this guide. Preserve previous good metadata.
- Use explicit, authenticated, idempotent server requests; do not enable broad
  wanted-list monitoring or put provider/admin credentials in Flutter or PWA.
  Music request dispatch and Books acquisition are different paths.
- The checked-in backend lacks the deployed account service source; do not invent
  routes or claim a matching server implementation. See architecture provenance.

## Safe verification

For catalog-only changes: `python3 -m unittest discover -s backend/tests -p 'test_catalog.py' -v`
and likewise `test_reconciliation_identity.py`, `test_discography.py`, `test_http.py`.
These are narrower than the whole backend suite. Inspect tests before executing.

The full command is `python3 -m unittest discover -s backend/tests -v`.
The acquisition lifecycle regression now injects a fixture coordinator, blocks
network access and uses temporary library roots. Other legacy tests can still
perform metadata-provider lookups; inspect/mock those before treating the entire
suite as hermetic. Never execute a worker against a deployed database to verify
behavior. Record exclusions/failures and use the shared quality gates.
