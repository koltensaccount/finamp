# Catalog backend

Python 3.10+, standard library only. Tests:

```sh
python3 -m unittest discover -s backend/tests -v
```

On the existing server, where its credentials remain local:

```sh
cd ~/music-metadata-audit/catalog-index
python3 refresh.py --database catalog.sqlite
python3 refresh.py --database catalog.sqlite --watch
python3 verify_cases.py --database catalog.sqlite
```

For a controlled local API, set `CATALOG_API_TOKEN` through your secret manager
or environment and start `python3 backend/server.py --database /path/catalog.sqlite`.
It binds 127.0.0.1:8765 only. Send a Bearer header. Never commit the token or
database. Request dispatch is disabled. Complete contract: docs/ARCHITECTURE.md.

The server-side refresh adapter presently targets this single existing Jellyfin
installation and its local credential/database paths. It is not a generic hosted
multi-user service. Complete snapshots reconcile active items; payload updates
are incremental. Public search hydration is opt-in (`refresh=true`).
