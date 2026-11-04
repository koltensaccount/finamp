# Next Concrete Tasks

## 1. Flutter Client Integration (Finamp App Agent on `antigravity/catalog-client`)

- Connect downloaded track and album detail views to `/v1/artists/resolve?item_id={itemId}`:
  - Add `resolveArtist(String itemId)` in `CatalogApiClient`.
  - When user taps on artist name in a downloaded/offline view, resolve the item ID and push `CatalogArtistScreen` with resolved `artistMbid`.
- Wire up the request status badge in `CatalogArtistScreen` and `CatalogAlbumScreen`:
  - When a user taps "Request Album", display the live request progression (`queued` -> `dispatched` -> `downloading` -> `available`).
- Render enriched artist details from `/v1/artists/{id}`:
  - Utilize `artist.image_url` for header background and Deezer artist photo fallback.
  - Display genres pills and bio summary in artist overview dialog.

## 2. Server Operations & Monitoring

- Keep `server.py` and `refresh.py --watch` running continuously under systemd or supervisor.
- Monitor Soularr / SLSKD completion for Request 4 (Neutral Milk Hotel — *In the Aeroplane Over the Sea*).
- Observe automatic state progression from `dispatched` -> `downloading` -> `imported` -> `available`.
