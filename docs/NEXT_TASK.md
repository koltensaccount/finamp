# Next concrete task — Scoped Acquisition Dispatcher

Branch/worktree: create `backend/acquisition-dispatcher` or continue on `codex/catalog-identity`.
Ownership: Server-side request outbox processing and acquisition dispatch.

## Objectives

1. **Scoped Acquisition Worker:**
   - Implement a lightweight background worker or cron job on the server (`koltensserver`) to poll the `requests` table in `catalog.sqlite` where `state = 'queued'`.
   - Dispatch album requests to Lidarr API or Soularr acquisition workflow in a strictly scoped, rate-limited manner.
   - Guard against duplicate searches and preserve the current conservative library boundaries.

2. **Acquisition State Machine:**
   - Transition requests from `queued` -> `dispatched` -> `downloading` -> `imported` -> `available`.
   - Re-run catalog incremental sync once an album is imported to link newly added tracks to Jellyfin item IDs.
   - Update request record state in SQLite so the client's `GET /v1/requests/{id}` reflects live status.

3. **Client Notification / Status Refresh:**
   - Add status polling or refresh on `CatalogAlbumScreen` for albums with existing requests.
   - When a request becomes `available`, update the album view ownership chip from `Unowned` / `Partially Owned` to `Fully Owned`.

4. **Visual Polish & Redesign (Follow-up):**
   - Begin Apple Music-style aesthetic redesign of Finamp interface once acquisition dispatching is verified end-to-end.
