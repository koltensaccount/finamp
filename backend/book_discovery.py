"""
Worldwide Book Discovery Service:
Aggregated multi-provider book search (Open Library, Google Books, Standard Ebooks),
deduplication, local ownership cross-referencing, request state tracking, and SQLite caching.
"""

import hashlib
import json
import logging
import os
import sqlite3
import time
import urllib.parse
import urllib.request

logger = logging.getLogger("book_discovery")


def _norm(s: str) -> str:
    if not s:
        return ""
    return "".join(c.lower() for c in s if c.isalnum() or c.isspace()).strip()


class WorldwideDiscoveryService:
    def __init__(self, books_core):
        self.books_core = books_core

    def search(self, query: str, format_filter: str = None, bypass_cache: bool = False, limit: int = 15) -> list[dict]:
        clean_q = query.strip()
        if not clean_q:
            return []

        # 1. Check SQLite search cache
        cache_key = hashlib.sha256(f"{clean_q.lower()}:{format_filter or 'all'}".encode("utf-8")).hexdigest()
        now = time.time()

        if not bypass_cache:
            cached = self._get_cached_search(cache_key, now)
            if cached is not None:
                # Re-enrich cached items with live local ownership and request state
                return self._enrich_with_local_state(cached)

        # 2. Query external providers with timeouts and error handling
        raw_results = []

        # Provider A: Open Library (Primary)
        try:
            ol_results = self._search_open_library(clean_q, limit=limit)
            raw_results.extend(ol_results)
        except Exception as e:
            logger.warning(f"Open Library search error for '{clean_q}': {e}")

        # Provider B: Google Books (Enrichment / Fallback if OL yielded few results)
        if len(raw_results) < 5:
            try:
                gb_results = self._search_google_books(clean_q, limit=5)
                raw_results.extend(gb_results)
            except Exception as e:
                logger.warning(f"Google Books search error for '{clean_q}': {e}")

        # 3. Deduplicate and group into canonical works
        deduped = self._deduplicate_results(raw_results, limit=limit)

        # 4. Save to SQLite search cache (24 hour TTL)
        self._save_cached_search(cache_key, clean_q, deduped, expires_at=now + 86400)

        # 5. Enrich with live local ownership and request state
        return self._enrich_with_local_state(deduped)

    def _search_open_library(self, query: str, limit: int = 15) -> list[dict]:
        encoded_q = urllib.parse.quote(query)
        url = f"https://openlibrary.org/search.json?q={encoded_q}&limit={limit}"
        req = urllib.request.Request(url, headers={"User-Agent": "FinampBooks/2.0 (Audiobooks & EPUB Ecosystem)"})

        with urllib.request.urlopen(req, timeout=8) as resp:
            if resp.status != 200:
                return []
            data = json.loads(resp.read().decode("utf-8"))

        docs = data.get("docs", [])
        results = []
        for d in docs:
            title = d.get("title")
            if not title:
                continue

            authors = d.get("author_name") or ["Unknown Author"]
            author = authors[0]
            first_year = d.get("first_publish_year")
            cover_i = d.get("cover_i")
            cover_url = f"https://covers.openlibrary.org/b/id/{cover_i}-L.jpg" if cover_i else None
            isbns = (d.get("isbn") or [])[:5]
            work_key = d.get("key") # e.g. "/works/OL45804W"
            edition_count = d.get("edition_count", 1)
            languages = d.get("language") or ["eng"]

            results.append({
                "source": "openlibrary",
                "external_id": work_key,
                "title": title,
                "author": author,
                "authors": authors,
                "published_year": first_year,
                "cover_url": cover_url,
                "isbns": isbns,
                "edition_count": edition_count,
                "languages": languages,
                "description": None,
                "genres": (d.get("subject") or [])[:5],
            })
        return results

    def _search_google_books(self, query: str, limit: int = 5) -> list[dict]:
        encoded_q = urllib.parse.quote(query)
        url = f"https://www.googleapis.com/books/v1/volumes?q={encoded_q}&maxResults={limit}"
        req = urllib.request.Request(url, headers={"User-Agent": "FinampBooks/2.0"})

        with urllib.request.urlopen(req, timeout=6) as resp:
            if resp.status != 200:
                return []
            data = json.loads(resp.read().decode("utf-8"))

        items = data.get("items", [])
        results = []
        for it in items:
            vol = it.get("volumeInfo", {})
            title = vol.get("title")
            if not title:
                continue
            authors = vol.get("authors") or ["Unknown Author"]
            author = authors[0]

            pub_date = vol.get("publishedDate", "")
            year = int(pub_date[:4]) if pub_date and pub_date[:4].isdigit() else None

            images = vol.get("imageLinks", {})
            cover_url = images.get("thumbnail") or images.get("smallThumbnail")
            if cover_url and cover_url.startswith("http://"):
                cover_url = cover_url.replace("http://", "https://")

            isbns = []
            for ident in vol.get("industryIdentifiers", []):
                if ident.get("identifier"):
                    isbns.append(ident["identifier"])

            results.append({
                "source": "googlebooks",
                "external_id": it.get("id"),
                "title": title,
                "author": author,
                "authors": authors,
                "published_year": year,
                "cover_url": cover_url,
                "isbns": isbns[:5],
                "edition_count": 1,
                "languages": [vol.get("language", "en")],
                "description": vol.get("description"),
                "genres": vol.get("categories", [])[:5],
            })
        return results

    def _deduplicate_results(self, items: list[dict], limit: int = 15) -> list[dict]:
        seen = {}
        for it in items:
            norm_title = _norm(it.get("title", ""))
            norm_author = _norm(it.get("author", ""))
            key = f"{norm_title}:::{norm_author}"

            if key not in seen:
                seen[key] = it
            else:
                existing = seen[key]
                # Merge artwork if missing
                if not existing.get("cover_url") and it.get("cover_url"):
                    existing["cover_url"] = it["cover_url"]
                # Merge description if missing
                if not existing.get("description") and it.get("description"):
                    existing["description"] = it["description"]
                # Merge ISBNs
                all_isbns = list(dict.fromkeys(existing.get("isbns", []) + it.get("isbns", [])))
                existing["isbns"] = all_isbns[:5]
                # Update edition count
                existing["edition_count"] = max(existing.get("edition_count", 1), it.get("edition_count", 1))

        return list(seen.values())[:limit]

    def _enrich_with_local_state(self, items: list[dict]) -> list[dict]:
        """
        Cross-reference items against local SQLite works, editions, progress, and active requests.
        """
        enriched = []
        with self.books_core.get_db() as db:
            for item in items:
                res = dict(item)
                title_norm = _norm(res.get("title", ""))
                author_norm = _norm(res.get("author", ""))
                isbns = res.get("isbns", [])

                # 1. Check local owned works
                matched_work = None
                # Check by normalized title + author
                slug = f"work-{title_norm.replace(' ', '-')}-{author_norm.replace(' ', '-')}"
                work_row = db.execute("SELECT * FROM works WHERE id=?", (slug,)).fetchone()
                if not work_row:
                    work_row = db.execute(
                        "SELECT * FROM works WHERE LOWER(title)=? AND LOWER(author)=?",
                        (res.get("title", "").strip().lower(), res.get("author", "").strip().lower())
                    ).fetchone()

                # Check by ISBN
                if not work_row and isbns:
                    placeholders = ",".join(["?"] * len(isbns))
                    work_row = db.execute(f"""
                        SELECT w.* FROM works w
                        JOIN editions e ON e.work_id = w.id
                        WHERE e.isbn IN ({placeholders})
                        LIMIT 1
                    """, isbns).fetchone()

                if work_row:
                    matched_work = dict(work_row)
                    res["is_local"] = True
                    res["local_work_id"] = matched_work["id"]

                    # Fetch available owned formats
                    ed_rows = db.execute("SELECT format FROM editions WHERE work_id=?", (matched_work["id"],)).fetchall()
                    owned_formats = list({r["format"] for r in ed_rows if r["format"] in ("epub", "audiobook")})
                    res["owned_formats"] = owned_formats

                    # Check progress
                    prog_row = db.execute("SELECT * FROM progress WHERE work_id=?", (matched_work["id"],)).fetchone()
                    if prog_row:
                        res["reading_percentage"] = prog_row["reading_percentage"]
                        res["listening_percentage"] = prog_row["listening_percentage"]
                    else:
                        res["reading_percentage"] = 0.0
                        res["listening_percentage"] = 0.0
                else:
                    res["is_local"] = False
                    res["local_work_id"] = None
                    res["owned_formats"] = []
                    res["reading_percentage"] = 0.0
                    res["listening_percentage"] = 0.0

                # 2. Check active acquisition requests
                req_row = db.execute("""
                    SELECT id, state, format_requested, acquired_formats, progress_percentage, error_message
                    FROM book_requests
                    WHERE (LOWER(title)=? AND LOWER(author)=?) AND state != 'failed'
                    ORDER BY created_at DESC LIMIT 1
                """, (res.get("title", "").strip().lower(), res.get("author", "").strip().lower())).fetchone()

                if req_row:
                    req_d = dict(req_row)
                    res["request_id"] = req_d["id"]
                    res["request_state"] = req_d["state"] # 'requested', 'searching', 'acquiring', 'verifying', 'importing', 'available', 'needs_review'
                    res["format_requested"] = req_d["format_requested"]
                    try:
                        res["acquired_formats"] = json.loads(req_d["acquired_formats"]) if isinstance(req_d["acquired_formats"], str) else (req_d["acquired_formats"] or [])
                    except Exception:
                        res["acquired_formats"] = []
                    res["acquisition_progress"] = req_d.get("progress_percentage", 0.0)
                else:
                    res["request_id"] = None
                    res["request_state"] = None
                    res["acquired_formats"] = []
                    res["acquisition_progress"] = 0.0

                enriched.append(res)
        return enriched

    def _get_cached_search(self, cache_key: str, now: float):
        try:
            with self.books_core.get_db() as db:
                row = db.execute(
                    "SELECT results_json FROM catalog_search_cache WHERE query_hash=? AND expires_at > ?",
                    (cache_key, now)
                ).fetchone()
                if row and row["results_json"]:
                    return json.loads(row["results_json"])
        except Exception:
            pass
        return None

    def _save_cached_search(self, cache_key: str, query_text: str, results: list[dict], expires_at: float):
        try:
            now = time.time()
            with self.books_core.get_db() as db:
                db.execute("""
                    INSERT INTO catalog_search_cache (query_hash, query_text, results_json, expires_at, created_at)
                    VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(query_hash) DO UPDATE SET
                        results_json=excluded.results_json,
                        expires_at=excluded.expires_at
                """, (cache_key, query_text, json.dumps(results), expires_at, now))
                db.commit()
        except Exception:
            pass
