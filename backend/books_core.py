"""
Books Core: Canonical literary Work, Edition, Asset, Progress, and Alignment Engine.
Lightweight SQLite backend with WAL mode, Audiobookshelf synchronization, and progress tracking.
"""

import hashlib
import hmac
import json
import os
import sqlite3
import time
import urllib.parse
import urllib.request
import uuid


def generate_media_ticket(secret: str, path: str, expires_at: int) -> str:
    message = f"{path}:{expires_at}".encode("utf-8")
    return hmac.new(secret.encode("utf-8"), message, hashlib.sha256).hexdigest()


def _norm(s):
    if not s:
        return ""
    return "".join(c.lower() for c in s if c.isalnum() or c.isspace()).strip()


class BooksCore:
    def __init__(self, db_path="books.sqlite"):
        self.db_path = db_path
        self._init_db()

    def get_db(self):
        conn = sqlite3.connect(self.db_path, timeout=15)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("PRAGMA foreign_keys=ON")
        return conn

    def _init_db(self):
        with self.get_db() as db:
            db.executescript("""
                CREATE TABLE IF NOT EXISTS works (
                    id TEXT PRIMARY KEY,
                    title TEXT NOT NULL,
                    author TEXT NOT NULL,
                    description TEXT,
                    genres TEXT,
                    series_name TEXT,
                    series_order REAL,
                    cover_url TEXT,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL
                );

                CREATE TABLE IF NOT EXISTS editions (
                    id TEXT PRIMARY KEY,
                    work_id TEXT NOT NULL,
                    format TEXT NOT NULL, -- 'epub', 'audiobook', 'paired'
                    title TEXT NOT NULL,
                    subtitle TEXT,
                    authors TEXT, -- JSON array
                    narrators TEXT, -- JSON array
                    publisher TEXT,
                    published_year INTEGER,
                    language TEXT,
                    isbn TEXT,
                    asin TEXT,
                    description TEXT,
                    cover_url TEXT,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL,
                    FOREIGN KEY(work_id) REFERENCES works(id) ON DELETE CASCADE
                );

                CREATE TABLE IF NOT EXISTS assets (
                    id TEXT PRIMARY KEY,
                    edition_id TEXT NOT NULL,
                    kind TEXT NOT NULL, -- 'epub', 'audio_track', 'cover'
                    file_path TEXT,
                    file_size INTEGER,
                    mime_type TEXT,
                    format TEXT,
                    duration_seconds REAL,
                    track_number INTEGER,
                    abs_item_id TEXT,
                    abs_file_ino TEXT,
                    created_at REAL NOT NULL,
                    FOREIGN KEY(edition_id) REFERENCES editions(id) ON DELETE CASCADE
                );

                CREATE TABLE IF NOT EXISTS chapters (
                    id TEXT PRIMARY KEY,
                    edition_id TEXT NOT NULL,
                    index_num INTEGER NOT NULL,
                    title TEXT NOT NULL,
                    start_seconds REAL,
                    end_seconds REAL,
                    epub_href TEXT,
                    epub_cfi TEXT,
                    FOREIGN KEY(edition_id) REFERENCES editions(id) ON DELETE CASCADE
                );

                CREATE TABLE IF NOT EXISTS progress (
                    user_id TEXT NOT NULL,
                    work_id TEXT NOT NULL,
                    edition_id TEXT NOT NULL,
                    reading_cfi TEXT,
                    reading_percentage REAL DEFAULT 0.0,
                    reading_updated_at REAL,
                    listening_seconds REAL DEFAULT 0.0,
                    listening_track_id TEXT,
                    listening_percentage REAL DEFAULT 0.0,
                    listening_updated_at REAL,
                    last_active_format TEXT, -- 'reading', 'listening'
                    is_finished INTEGER DEFAULT 0,
                    PRIMARY KEY (user_id, work_id)
                );

                CREATE TABLE IF NOT EXISTS annotations (
                    id TEXT PRIMARY KEY,
                    user_id TEXT NOT NULL,
                    work_id TEXT NOT NULL,
                    edition_id TEXT NOT NULL,
                    kind TEXT NOT NULL, -- 'bookmark', 'highlight', 'note'
                    cfi_range TEXT,
                    highlight_color TEXT,
                    selected_text TEXT,
                    note TEXT,
                    audio_timestamp REAL,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL
                );

                CREATE TABLE IF NOT EXISTS alignments (
                    id TEXT PRIMARY KEY,
                    work_id TEXT NOT NULL,
                    epub_edition_id TEXT NOT NULL,
                    audio_edition_id TEXT NOT NULL,
                    alignment_level TEXT NOT NULL, -- 'chapter', 'sentence'
                    engine TEXT NOT NULL,
                    version TEXT NOT NULL,
                    confidence REAL NOT NULL,
                    mapping_data TEXT NOT NULL, -- JSON array of {sentence_idx, epub_cfi, text, audio_track, audio_start_sec, audio_end_sec, confidence}
                    epub_asset_hash TEXT,
                    audio_asset_hash TEXT,
                    unmatched_regions TEXT, -- JSON array of {type, start, end, reason}
                    created_at REAL NOT NULL
                );

                CREATE TABLE IF NOT EXISTS background_tasks (
                    id TEXT PRIMARY KEY,
                    task_type TEXT NOT NULL,
                    priority TEXT NOT NULL, -- 'immediate', 'opportunistic', 'deferred'
                    payload TEXT NOT NULL, -- JSON
                    state TEXT NOT NULL DEFAULT 'queued', -- 'queued', 'processing', 'completed', 'failed', 'yielded'
                    retries INTEGER DEFAULT 0,
                    error_message TEXT,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL
                );

                CREATE TABLE IF NOT EXISTS book_requests (
                    id TEXT PRIMARY KEY,
                    work_id TEXT,
                    title TEXT NOT NULL,
                    author TEXT NOT NULL,
                    isbn TEXT,
                    format_requested TEXT NOT NULL, -- 'epub', 'audiobook', 'paired'
                    state TEXT NOT NULL DEFAULT 'requested', -- 'requested', 'staging', 'metadata_verified', 'imported', 'failed'
                    origin TEXT NOT NULL DEFAULT 'user',
                    metadata_json TEXT,
                    staging_path TEXT,
                    error_message TEXT,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL
                );

                CREATE INDEX IF NOT EXISTS idx_works_author ON works(author);
                CREATE INDEX IF NOT EXISTS idx_editions_work ON editions(work_id);
                CREATE INDEX IF NOT EXISTS idx_assets_edition ON assets(edition_id);
                CREATE INDEX IF NOT EXISTS idx_chapters_edition ON chapters(edition_id);
                CREATE INDEX IF NOT EXISTS idx_book_requests_state ON book_requests(state);
            """)

    def list_books(self, query=None, format_filter=None, user_id="default"):
        with self.get_db() as db:
            sql = """
                SELECT w.*,
                       p.reading_cfi, p.reading_percentage, p.reading_updated_at,
                       p.listening_seconds, p.listening_track_id, p.listening_percentage, p.listening_updated_at,
                       p.last_active_format, p.is_finished
                FROM works w
                LEFT JOIN progress p ON p.work_id = w.id AND p.user_id = ?
            """
            params = [user_id]
            if query:
                q_clean = f"%{query.strip().lower()}%"
                sql += " WHERE (LOWER(w.title) LIKE ? OR LOWER(w.author) LIKE ? OR LOWER(COALESCE(w.series_name, '')) LIKE ?)"
                params.extend([q_clean, q_clean, q_clean])

            sql += " ORDER BY COALESCE(p.reading_updated_at, p.listening_updated_at, w.updated_at) DESC"
            rows = db.execute(sql, params).fetchall()

            result = []
            for r in rows:
                book = dict(r)
                book["genres"] = json.loads(book["genres"]) if book["genres"] else []

                # Fetch available formats from editions
                ed_rows = db.execute("SELECT id, format, cover_url FROM editions WHERE work_id=?", (book["id"],)).fetchall()
                formats = list({ed["format"] for ed in ed_rows})
                book["available_formats"] = formats
                book["is_paired"] = ("epub" in formats and "audiobook" in formats) or ("paired" in formats)

                # Format progress block
                book["progress"] = {
                    "reading_cfi": book.pop("reading_cfi"),
                    "reading_percentage": book.pop("reading_percentage") or 0.0,
                    "reading_updated_at": book.pop("reading_updated_at"),
                    "listening_seconds": book.pop("listening_seconds") or 0.0,
                    "listening_track_id": book.pop("listening_track_id"),
                    "listening_percentage": book.pop("listening_percentage") or 0.0,
                    "listening_updated_at": book.pop("listening_updated_at"),
                    "last_active_format": book.pop("last_active_format"),
                    "is_finished": bool(book.pop("is_finished")),
                }

                # Resolve relative cover proxy if cover_url starts with http://127.0.0.1:13378
                if book.get("cover_url") and ("13378" in book["cover_url"] or "/v1/books/" in book["cover_url"]):
                    secret = os.environ.get("CATALOG_API_TOKEN", "")
                    cover_path = f"/v1/books/{book['id']}/cover"
                    if secret:
                        expires = int(time.time()) + 86400
                        sig = generate_media_ticket(secret, cover_path, expires)
                        book["cover_url"] = f"http://127.0.0.1:8765{cover_path}?ticket={sig}&expires={expires}"
                    else:
                        book["cover_url"] = f"http://127.0.0.1:8765{cover_path}"

                if format_filter:
                    if format_filter == "epub" and "epub" not in formats:
                        continue
                    if format_filter == "audiobook" and "audiobook" not in formats:
                        continue
                    if format_filter == "paired" and not book["is_paired"]:
                        continue

                result.append(book)
            return result

    def get_book(self, work_id, user_id="default"):
        with self.get_db() as db:
            row = db.execute("""
                SELECT w.*,
                       p.reading_cfi, p.reading_percentage, p.reading_updated_at,
                       p.listening_seconds, p.listening_track_id, p.listening_percentage, p.listening_updated_at,
                       p.last_active_format, p.is_finished
                FROM works w
                LEFT JOIN progress p ON p.work_id = w.id AND p.user_id = ?
                WHERE w.id = ?
            """, (user_id, work_id)).fetchone()
            if not row:
                return None

            book = dict(row)
            book["genres"] = json.loads(book["genres"]) if book["genres"] else []

            # Editions
            ed_rows = db.execute("SELECT * FROM editions WHERE work_id=?", (work_id,)).fetchall()
            editions = []
            formats = set()
            for er in ed_rows:
                ed = dict(er)
                ed["authors"] = json.loads(ed["authors"]) if ed["authors"] else []
                ed["narrators"] = json.loads(ed["narrators"]) if ed["narrators"] else []
                formats.add(ed["format"])

                # Assets
                asset_rows = db.execute("SELECT * FROM assets WHERE edition_id=? ORDER BY track_number ASC", (ed["id"],)).fetchall()
                ed["assets"] = [dict(ar) for ar in asset_rows]

                # Chapters
                ch_rows = db.execute("SELECT * FROM chapters WHERE edition_id=? ORDER BY index_num ASC", (ed["id"],)).fetchall()
                ed["chapters"] = [dict(cr) for cr in ch_rows]
                editions.append(ed)

            book["editions"] = editions
            book["available_formats"] = list(formats)
            book["is_paired"] = ("epub" in formats and "audiobook" in formats) or ("paired" in formats)

            # Progress
            book["progress"] = {
                "reading_cfi": book.pop("reading_cfi"),
                "reading_percentage": book.pop("reading_percentage") or 0.0,
                "reading_updated_at": book.pop("reading_updated_at"),
                "listening_seconds": book.pop("listening_seconds") or 0.0,
                "listening_track_id": book.pop("listening_track_id"),
                "listening_percentage": book.pop("listening_percentage") or 0.0,
                "listening_updated_at": book.pop("listening_updated_at"),
                "last_active_format": book.pop("last_active_format"),
                "is_finished": bool(book.pop("is_finished")),
            }

            secret = os.environ.get("CATALOG_API_TOKEN", "")
            expires = int(time.time()) + 86400

            if book.get("cover_url") and ("13378" in book["cover_url"] or "/v1/books/" in book["cover_url"]):
                cover_path = f"/v1/books/{book['id']}/cover"
                if secret:
                    sig = generate_media_ticket(secret, cover_path, expires)
                    book["cover_url"] = f"http://127.0.0.1:8765{cover_path}?ticket={sig}&expires={expires}"
                else:
                    book["cover_url"] = f"http://127.0.0.1:8765{cover_path}"

            # Attach media URLs to edition assets
            for ed in editions:
                for a in ed.get("assets", []):
                    if ed.get("format") == "audiobook" and a.get("track_number"):
                        audio_path = f"/v1/books/{work_id}/audio/{a['track_number']}"
                        if secret:
                            sig = generate_media_ticket(secret, audio_path, expires)
                            a["stream_url"] = f"http://127.0.0.1:8765{audio_path}?ticket={sig}&expires={expires}"
                        else:
                            a["stream_url"] = f"http://127.0.0.1:8765{audio_path}"
                    elif ed.get("format") == "epub":
                        epub_path = f"/v1/books/{work_id}/epub"
                        if secret:
                            sig = generate_media_ticket(secret, epub_path, expires)
                            a["download_url"] = f"http://127.0.0.1:8765{epub_path}?ticket={sig}&expires={expires}"
                        else:
                            a["download_url"] = f"http://127.0.0.1:8765{epub_path}"

            # Alignment
            align_row = db.execute("SELECT * FROM alignments WHERE work_id=? ORDER BY created_at DESC LIMIT 1", (work_id,)).fetchone()
            if align_row:
                align = dict(align_row)
                align["mapping_data"] = json.loads(align["mapping_data"]) if align["mapping_data"] else []
                if align.get("unmatched_regions"):
                    try:
                        align["unmatched_regions"] = json.loads(align["unmatched_regions"])
                    except Exception:
                        pass
                book["alignment"] = align
            else:
                book["alignment"] = None

            return book

    def update_progress(self, work_id, user_id="default", edition_id=None,
                        reading_cfi=None, reading_percentage=None,
                        listening_seconds=None, listening_track_id=None,
                        listening_percentage=None, active_format=None, is_finished=None):
        now = time.time()
        with self.get_db() as db:
            row = db.execute("SELECT * FROM progress WHERE user_id=? AND work_id=?", (user_id, work_id)).fetchone()
            if not row:
                if not edition_id:
                    ed = db.execute("SELECT id FROM editions WHERE work_id=? LIMIT 1", (work_id,)).fetchone()
                    edition_id = ed["id"] if ed else "default"
                db.execute("""
                    INSERT INTO progress (
                        user_id, work_id, edition_id, reading_cfi, reading_percentage, reading_updated_at,
                        listening_seconds, listening_track_id, listening_percentage, listening_updated_at,
                        last_active_format, is_finished
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, (
                    user_id, work_id, edition_id,
                    reading_cfi, reading_percentage or 0.0, now if reading_cfi is not None else None,
                    listening_seconds or 0.0, listening_track_id, listening_percentage or 0.0, now if listening_seconds is not None else None,
                    active_format or ("reading" if reading_cfi is not None else "listening"),
                    1 if is_finished else 0
                ))
            else:
                updates = []
                params = []
                if edition_id:
                    updates.append("edition_id=?")
                    params.append(edition_id)
                if reading_cfi is not None:
                    updates.append("reading_cfi=?")
                    params.append(reading_cfi)
                    updates.append("reading_updated_at=?")
                    params.append(now)
                if reading_percentage is not None:
                    updates.append("reading_percentage=?")
                    params.append(reading_percentage)
                if listening_seconds is not None:
                    updates.append("listening_seconds=?")
                    params.append(listening_seconds)
                    updates.append("listening_updated_at=?")
                    params.append(now)
                if listening_track_id is not None:
                    updates.append("listening_track_id=?")
                    params.append(listening_track_id)
                if listening_percentage is not None:
                    updates.append("listening_percentage=?")
                    params.append(listening_percentage)
                if active_format is not None:
                    updates.append("last_active_format=?")
                    params.append(active_format)
                if is_finished is not None:
                    updates.append("is_finished=?")
                    params.append(1 if is_finished else 0)

                if updates:
                    sql = f"UPDATE progress SET {', '.join(updates)} WHERE user_id=? AND work_id=?"
                    params.extend([user_id, work_id])
                    db.execute(sql, params)
            db.commit()

        return self.get_book(work_id, user_id=user_id)

    def get_annotations(self, work_id, user_id="default"):
        with self.get_db() as db:
            rows = db.execute("SELECT * FROM annotations WHERE work_id=? AND user_id=? ORDER BY created_at DESC", (work_id, user_id)).fetchall()
            return [dict(r) for r in rows]

    def add_annotation(self, work_id, edition_id, kind, user_id="default",
                       cfi_range=None, highlight_color=None, selected_text=None,
                       note=None, audio_timestamp=None):
        anno_id = str(uuid.uuid4())
        now = time.time()
        with self.get_db() as db:
            db.execute("""
                INSERT INTO annotations (
                    id, user_id, work_id, edition_id, kind,
                    cfi_range, highlight_color, selected_text, note, audio_timestamp,
                    created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                anno_id, user_id, work_id, edition_id, kind,
                cfi_range, highlight_color or "#FFDE38", selected_text, note, audio_timestamp,
                now, now
            ))
            db.commit()
        return {"id": anno_id, "status": "created"}

    def delete_annotation(self, annotation_id, user_id="default"):
        with self.get_db() as db:
            db.execute("DELETE FROM annotations WHERE id=? AND user_id=?", (annotation_id, user_id))
            db.commit()
        return {"status": "deleted"}

    def sync_from_abs(self, abs_base_url="http://127.0.0.1:13378", abs_token=""):
        """
        Synchronizes works and editions from Audiobookshelf instance.
        """
        headers = {}
        if abs_token:
            headers["Authorization"] = f"Bearer {abs_token}"

        req = urllib.request.Request(f"{abs_base_url}/api/libraries", headers=headers)
        with urllib.request.urlopen(req, timeout=10) as resp:
            lib_data = json.loads(resp.read().decode())

        libraries = lib_data.get("libraries", [])
        now = time.time()
        synced_works = []

        with self.get_db() as db:
            for lib in libraries:
                lib_id = lib["id"]
                req_items = urllib.request.Request(f"{abs_base_url}/api/libraries/{lib_id}/items", headers=headers)
                with urllib.request.urlopen(req_items, timeout=15) as item_resp:
                    items_data = json.loads(item_resp.read().decode())

                for item in items_data.get("results", []):
                    item_id = item["id"]
                    # Fetch detailed item
                    req_detail = urllib.request.Request(f"{abs_base_url}/api/items/{item_id}", headers=headers)
                    with urllib.request.urlopen(req_detail, timeout=15) as det_resp:
                        detail = json.loads(det_resp.read().decode())

                    media = detail.get("media", {})
                    meta = media.get("metadata", {})
                    title = meta.get("title") or item.get("media", {}).get("metadata", {}).get("title") or "Unknown Title"
                    author = meta.get("authorName") or item.get("media", {}).get("metadata", {}).get("authorName") or "Unknown Author"
                    description = meta.get("description")
                    genres = json.dumps(meta.get("genres") or [])
                    series_list = meta.get("series") or []
                    series_name = series_list[0].get("name") if series_list else None
                    series_order = float(series_list[0].get("sequence", 1.0)) if series_list and series_list[0].get("sequence") else None

                    # Work ID deterministic by normalized title and author
                    work_id = f"work-{_norm(title)}-{_norm(author)}".replace(" ", "-")[:64]
                    cover_url = f"{abs_base_url}/api/items/{item_id}/cover"

                    db.execute("""
                        INSERT INTO works (id, title, author, description, genres, series_name, series_order, cover_url, created_at, updated_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        ON CONFLICT(id) DO UPDATE SET
                            title=excluded.title,
                            author=excluded.author,
                            description=COALESCE(excluded.description, works.description),
                            cover_url=COALESCE(excluded.cover_url, works.cover_url),
                            updated_at=excluded.updated_at
                    """, (work_id, title, author, description, genres, series_name, series_order, cover_url, now, now))

                    # Determine format
                    ebook_file = media.get("ebookFile")
                    audio_files = media.get("audioFiles") or []

                    if ebook_file:
                        ed_id = f"ed-{item_id}-epub"
                        authors_json = json.dumps([a.get("name") for a in meta.get("authors", [])] or [author])
                        db.execute("""
                            INSERT INTO editions (
                                id, work_id, format, title, authors, publisher, published_year, language, isbn, asin, description, cover_url, created_at, updated_at
                            ) VALUES (?, ?, 'epub', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                            ON CONFLICT(id) DO UPDATE SET
                                title=excluded.title,
                                cover_url=COALESCE(excluded.cover_url, editions.cover_url),
                                updated_at=excluded.updated_at
                        """, (
                            ed_id, work_id, title, authors_json, meta.get("publisher"),
                            int(meta.get("publishedYear")) if meta.get("publishedYear") and str(meta.get("publishedYear")).isdigit() else None,
                            meta.get("language"), meta.get("isbn"), meta.get("asin"), description, cover_url, now, now
                        ))

                        asset_id = f"asset-{item_id}-epub"
                        db.execute("""
                            INSERT INTO assets (id, edition_id, kind, file_path, file_size, mime_type, format, abs_item_id, abs_file_ino, created_at)
                            VALUES (?, ?, 'epub', ?, ?, 'application/epub+zip', 'epub', ?, ?, ?)
                            ON CONFLICT(id) DO UPDATE SET
                                file_path=excluded.file_path,
                                file_size=excluded.file_size
                        """, (
                            asset_id, ed_id, ebook_file.get("metadata", {}).get("path"),
                            ebook_file.get("metadata", {}).get("size"),
                            item_id, ebook_file.get("ino"), now
                        ))

                    if audio_files:
                        ed_id = f"ed-{item_id}-audio"
                        authors_json = json.dumps([a.get("name") for a in meta.get("authors", [])] or [author])
                        narrators_json = json.dumps(meta.get("narrators") or [])
                        db.execute("""
                            INSERT INTO editions (
                                id, work_id, format, title, authors, narrators, publisher, published_year, language, isbn, asin, description, cover_url, created_at, updated_at
                            ) VALUES (?, ?, 'audiobook', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                            ON CONFLICT(id) DO UPDATE SET
                                title=excluded.title,
                                cover_url=COALESCE(excluded.cover_url, editions.cover_url),
                                updated_at=excluded.updated_at
                        """, (
                            ed_id, work_id, title, authors_json, narrators_json, meta.get("publisher"),
                            int(meta.get("publishedYear")) if meta.get("publishedYear") and str(meta.get("publishedYear")).isdigit() else None,
                            meta.get("language"), meta.get("isbn"), meta.get("asin"), description, cover_url, now, now
                        ))

                        for af in audio_files:
                            tr_idx = af.get("index", 1)
                            asset_id = f"asset-{item_id}-audio-{tr_idx}"
                            db.execute("""
                                INSERT INTO assets (id, edition_id, kind, file_path, file_size, mime_type, format, duration_seconds, track_number, abs_item_id, abs_file_ino, created_at)
                                VALUES (?, ?, 'audio_track', ?, ?, ?, ?, ?, ?, ?, ?, ?)
                                ON CONFLICT(id) DO UPDATE SET
                                    duration_seconds=excluded.duration_seconds
                            """, (
                                asset_id, ed_id, af.get("metadata", {}).get("path"),
                                af.get("metadata", {}).get("size"), af.get("mimeType", "audio/flac"),
                                af.get("format", "audio"), af.get("duration", 0.0), tr_idx,
                                item_id, af.get("ino"), now
                            ))

                            ch_title = af.get("metaTags", {}).get("tagTitle") or f"Track {tr_idx}"
                            ch_id = f"ch-{ed_id}-{tr_idx}"
                            db.execute("""
                                INSERT INTO chapters (id, edition_id, index_num, title, start_seconds, end_seconds)
                                VALUES (?, ?, ?, ?, ?, ?)
                                ON CONFLICT(id) DO NOTHING
                            """, (ch_id, ed_id, tr_idx, ch_title, 0.0, af.get("duration", 0.0)))

                    synced_works.append(work_id)

            # Check if any synced work has both epub and audiobook, and if so enqueue an alignment task
            for wid in set(synced_works):
                epub_ed = db.execute("SELECT id FROM editions WHERE work_id=? AND format='epub'", (wid,)).fetchone()
                audio_ed = db.execute("SELECT id FROM editions WHERE work_id=? AND format='audiobook'", (wid,)).fetchone()
                if epub_ed and audio_ed:
                    existing_task = db.execute(
                        "SELECT id FROM background_tasks WHERE task_type='align_work' AND payload LIKE ? AND state IN ('queued', 'processing')",
                        (f"%{wid}%",)
                    ).fetchone()
                    if not existing_task:
                        task_id = f"task-{uuid.uuid4().hex[:12]}"
                        payload = json.dumps({"work_id": wid, "epub_edition_id": epub_ed["id"], "audio_edition_id": audio_ed["id"]})
                        db.execute("""
                            INSERT INTO background_tasks (id, task_type, priority, payload, state, created_at, updated_at)
                            VALUES (?, 'align_work', 'opportunistic', ?, 'queued', ?, ?)
                        """, (task_id, payload, now, now))

            db.commit()

        return {"status": "ok", "synced_works": list(set(synced_works))}

    def request_book(self, title, author, isbn=None, format_requested="paired", origin="user"):
        title_clean = title.strip()
        author_clean = author.strip()
        if not title_clean or not author_clean:
            raise ValueError("title and author are required")

        with self.get_db() as db:
            work_slug = f"work-{_norm(title_clean).replace(' ', '-')}-{_norm(author_clean).replace(' ', '-')}"
            existing_work = db.execute("SELECT id FROM works WHERE id=?", (work_slug,)).fetchone()
            if existing_work:
                return {
                    "request_id": None,
                    "state": "available",
                    "work_id": existing_work["id"],
                    "message": "Book is already in your library",
                }

            existing_req = db.execute(
                "SELECT * FROM book_requests WHERE (LOWER(title)=? AND LOWER(author)=?) AND state NOT IN ('failed', 'imported')",
                (title_clean.lower(), author_clean.lower()),
            ).fetchone()
            if existing_req:
                return {
                    "request_id": existing_req["id"],
                    "state": existing_req["state"],
                    "work_id": existing_req["work_id"],
                    "message": "Request already in progress",
                }

            now = time.time()
            req_id = f"breq-{uuid.uuid4().hex[:12]}"
            db.execute("""
                INSERT INTO book_requests (
                    id, work_id, title, author, isbn, format_requested, state, origin, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, 'requested', ?, ?, ?)
            """, (req_id, work_slug, title_clean, author_clean, isbn, format_requested, origin, now, now))
            db.commit()

        try:
            self.verify_request_metadata(req_id)
        except Exception:
            pass

        return self.get_request(req_id)

    def get_request(self, request_id):
        with self.get_db() as db:
            row = db.execute("SELECT * FROM book_requests WHERE id=?", (request_id,)).fetchone()
            if not row:
                return None
            d = dict(row)
            if d.get("metadata_json"):
                d["metadata"] = json.loads(d["metadata_json"])
            return d

    def list_requests(self, state=None):
        with self.get_db() as db:
            if state:
                rows = db.execute("SELECT * FROM book_requests WHERE state=? ORDER BY created_at DESC", (state,)).fetchall()
            else:
                rows = db.execute("SELECT * FROM book_requests ORDER BY created_at DESC").fetchall()
            res = []
            for r in rows:
                d = dict(r)
                if d.get("metadata_json"):
                    d["metadata"] = json.loads(d["metadata_json"])
                res.append(d)
            return res

    def update_request_state(self, request_id, state, staging_path=None, error_message=None):
        now = time.time()
        with self.get_db() as db:
            db.execute("""
                UPDATE book_requests
                SET state=?, staging_path=COALESCE(?, staging_path), error_message=COALESCE(?, error_message), updated_at=?
                WHERE id=?
            """, (state, staging_path, error_message, now, request_id))
            db.commit()
        return self.get_request(request_id)

    def verify_request_metadata(self, request_id):
        req = self.get_request(request_id)
        if not req:
            raise ValueError(f"Request {request_id} not found")

        meta = None
        if req.get("isbn"):
            try:
                isbn_url = f"https://openlibrary.org/isbn/{urllib.parse.quote(req['isbn'])}.json"
                req_obj = urllib.request.Request(isbn_url, headers={"User-Agent": "FinampBooks/1.0"})
                with urllib.request.urlopen(req_obj, timeout=8) as resp:
                    if resp.status == 200:
                        data = json.loads(resp.read().decode())
                        meta = {
                            "source": "openlibrary_isbn",
                            "title": data.get("title", req["title"]),
                            "publish_date": data.get("publish_date"),
                            "publishers": data.get("publishers", []),
                            "isbn_13": data.get("isbn_13", [req["isbn"]]),
                            "description": data.get("description", {}).get("value") if isinstance(data.get("description"), dict) else data.get("description"),
                        }
            except Exception:
                pass

        if not meta:
            try:
                search_q = urllib.parse.urlencode({"title": req["title"], "author": req["author"], "limit": 1})
                search_url = f"https://openlibrary.org/search.json?{search_q}"
                req_obj = urllib.request.Request(search_url, headers={"User-Agent": "FinampBooks/1.0"})
                with urllib.request.urlopen(req_obj, timeout=8) as resp:
                    if resp.status == 200:
                        data = json.loads(resp.read().decode())
                        docs = data.get("docs", [])
                        if docs:
                            doc = docs[0]
                            meta = {
                                "source": "openlibrary_search",
                                "title": doc.get("title", req["title"]),
                                "author": (doc.get("author_name") or [req["author"]])[0],
                                "first_publish_year": doc.get("first_publish_year"),
                                "isbn": (doc.get("isbn") or [])[:3],
                                "cover_id": doc.get("cover_i"),
                                "cover_url": f"https://covers.openlibrary.org/b/id/{doc['cover_i']}-L.jpg" if doc.get("cover_i") else None,
                            }
            except Exception:
                pass

        if meta:
            now = time.time()
            with self.get_db() as db:
                db.execute("""
                    UPDATE book_requests
                    SET state='metadata_verified', metadata_json=?, updated_at=?
                    WHERE id=?
                """, (json.dumps(meta), now, request_id))
                db.commit()
            return self.get_request(request_id)
        return req

    # --- Alignment Engine Architecture ---

    def store_alignment(
        self,
        work_id: str,
        epub_edition_id: str,
        audio_edition_id: str,
        alignment_level: str,
        engine: str,
        version: str,
        confidence: float,
        mapping_data: list,
        epub_asset_hash: str = None,
        audio_asset_hash: str = None,
        unmatched_regions: list = None,
    ):
        if alignment_level not in ("chapter", "sentence"):
            raise ValueError(f"Invalid alignment_level: {alignment_level}")
        if not (0.0 <= confidence <= 1.0):
            raise ValueError("confidence must be between 0.0 and 1.0")
        if not isinstance(mapping_data, list):
            raise ValueError("mapping_data must be a list of mapping objects")

        now = time.time()
        align_id = f"align-{work_id}"
        mapping_json = json.dumps(mapping_data)
        unmatched_json = json.dumps(unmatched_regions or [])

        with self.get_db() as db:
            db.execute("""
                INSERT INTO alignments (
                    id, work_id, epub_edition_id, audio_edition_id,
                    alignment_level, engine, version, confidence,
                    mapping_data, epub_asset_hash, audio_asset_hash,
                    unmatched_regions, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    epub_edition_id=excluded.epub_edition_id,
                    audio_edition_id=excluded.audio_edition_id,
                    alignment_level=excluded.alignment_level,
                    engine=excluded.engine,
                    version=excluded.version,
                    confidence=excluded.confidence,
                    mapping_data=excluded.mapping_data,
                    epub_asset_hash=excluded.epub_asset_hash,
                    audio_asset_hash=excluded.audio_asset_hash,
                    unmatched_regions=excluded.unmatched_regions,
                    created_at=excluded.created_at
            """, (
                align_id, work_id, epub_edition_id, audio_edition_id,
                alignment_level, engine, version, confidence,
                mapping_json, epub_asset_hash, audio_asset_hash,
                unmatched_json, now
            ))
            db.commit()

        return self.get_alignment(work_id)

    def get_alignment(self, work_id: str):
        with self.get_db() as db:
            row = db.execute("SELECT * FROM alignments WHERE work_id=? ORDER BY created_at DESC LIMIT 1", (work_id,)).fetchone()
            if not row:
                return None
            d = dict(row)
            if d.get("mapping_data"):
                try:
                    d["mapping_data"] = json.loads(d["mapping_data"])
                except Exception:
                    pass
            if d.get("unmatched_regions"):
                try:
                    d["unmatched_regions"] = json.loads(d["unmatched_regions"])
                except Exception:
                    pass
            return d

    def map_audio_to_reading_location(self, work_id: str, track_number: int, timestamp_seconds: float):
        """
        Maps an audio playback position (track + timestamp) to the corresponding EPUB CFI.
        Returns a dict with {epub_cfi, sentence_idx, confidence, text} or None.
        """
        alignment = self.get_alignment(work_id)
        if not alignment or not alignment.get("mapping_data"):
            return None

        mappings = alignment["mapping_data"]
        track_candidates = [
            m for m in mappings
            if m.get("audio_track", 1) == track_number
        ]
        if not track_candidates:
            return None

        best_match = None
        for m in track_candidates:
            start = m.get("audio_start_sec", 0.0)
            end = m.get("audio_end_sec", float("inf"))
            if start <= timestamp_seconds <= end:
                best_match = m
                break

        if not best_match:
            prior = [m for m in track_candidates if m.get("audio_start_sec", 0.0) <= timestamp_seconds]
            if prior:
                best_match = max(prior, key=lambda m: m.get("audio_start_sec", 0.0))

        if best_match:
            return {
                "epub_cfi": best_match.get("epub_cfi"),
                "sentence_idx": best_match.get("sentence_idx") or best_match.get("chapter_idx"),
                "confidence": best_match.get("confidence", alignment.get("confidence", 1.0)),
                "text": best_match.get("text"),
                "alignment_level": alignment.get("alignment_level", "sentence"),
            }
        return None

    def map_reading_location_to_audio(self, work_id: str, epub_cfi: str):
        """
        Maps an EPUB CFI reading position to audio playback position (track + seconds).
        Returns a dict with {audio_track, audio_timestamp_seconds, confidence} or None.
        """
        alignment = self.get_alignment(work_id)
        if not alignment or not alignment.get("mapping_data"):
            return None

        mappings = alignment["mapping_data"]
        for m in mappings:
            if m.get("epub_cfi") == epub_cfi:
                return {
                    "audio_track": m.get("audio_track", 1),
                    "audio_timestamp_seconds": m.get("audio_start_sec", 0.0),
                    "confidence": m.get("confidence", alignment.get("confidence", 1.0)),
                }

        cfi_prefix = epub_cfi.split("!")[0] if "!" in epub_cfi else epub_cfi
        prefix_matches = [
            m for m in mappings
            if m.get("epub_cfi", "").startswith(cfi_prefix)
        ]
        if prefix_matches:
            best = prefix_matches[0]
            return {
                "audio_track": best.get("audio_track", 1),
                "audio_timestamp_seconds": best.get("audio_start_sec", 0.0),
                "confidence": max(0.5, best.get("confidence", 0.8) * 0.9),
            }

        return None

    # --- Persistent Resource-Aware Background Task Queue ---

    def enqueue_task(self, task_type: str, payload: dict, priority: str = "opportunistic"):
        if priority not in ("immediate", "opportunistic", "deferred"):
            raise ValueError(f"Invalid priority: {priority}")
        task_id = f"task-{uuid.uuid4().hex[:12]}"
        now = time.time()
        with self.get_db() as db:
            db.execute("""
                INSERT INTO background_tasks (id, task_type, priority, payload, state, retries, created_at, updated_at)
                VALUES (?, ?, ?, ?, 'queued', 0, ?, ?)
            """, (task_id, task_type, priority, json.dumps(payload), now, now))
            db.commit()
        return self.get_task(task_id)

    def get_task(self, task_id: str):
        with self.get_db() as db:
            row = db.execute("SELECT * FROM background_tasks WHERE id=?", (task_id,)).fetchone()
            if not row:
                return None
            d = dict(row)
            if d.get("payload"):
                try:
                    d["payload"] = json.loads(d["payload"])
                except Exception:
                    pass
            return d

    def list_tasks(self, state: str = None, priority: str = None):
        with self.get_db() as db:
            query = "SELECT * FROM background_tasks"
            params = []
            clauses = []
            if state:
                clauses.append("state=?")
                params.append(state)
            if priority:
                clauses.append("priority=?")
                params.append(priority)
            if clauses:
                query += " WHERE " + " AND ".join(clauses)
            query += " ORDER BY created_at DESC"
            rows = db.execute(query, params).fetchall()
            res = []
            for r in rows:
                d = dict(r)
                if d.get("payload"):
                    try:
                        d["payload"] = json.loads(d["payload"])
                    except Exception:
                        pass
                res.append(d)
            return res

    def can_run_background_tasks(self, priority: str = "opportunistic") -> bool:
        """
        Resource-aware gatekeeper:
        - Checks free disk space on database filesystem.
        - Checks system 1-minute load average to prevent CPU saturation.
        """
        import shutil

        try:
            total, used, free = shutil.disk_usage(os.path.dirname(os.path.abspath(self.db_path)))
            free_mb = free / (1024 * 1024)
            if priority == "immediate" and free_mb < 100:
                return False
            if priority in ("opportunistic", "deferred") and free_mb < 500:
                return False
        except Exception:
            pass

        if priority in ("opportunistic", "deferred"):
            try:
                if hasattr(os, "getloadavg"):
                    load1, _, _ = os.getloadavg()
                    cpu_count = os.cpu_count() or 4
                    if load1 > cpu_count * 2.5:
                        return False
            except Exception:
                pass

        return True

    def process_next_task(self):
        """
        Picks and processes the next queued task based on priority order:
        immediate -> opportunistic -> deferred.
        """
        with self.get_db() as db:
            row = db.execute("""
                SELECT * FROM background_tasks
                WHERE state='queued'
                ORDER BY
                    CASE priority
                        WHEN 'immediate' THEN 1
                        WHEN 'opportunistic' THEN 2
                        WHEN 'deferred' THEN 3
                        ELSE 4
                    END ASC,
                    created_at ASC
                LIMIT 1
            """).fetchone()

            if not row:
                return {"status": "idle", "message": "No queued tasks"}

            task = dict(row)
            task_id = task["id"]
            priority = task["priority"]
            task_type = task["task_type"]
            payload = json.loads(task["payload"]) if task.get("payload") else {}

            if not self.can_run_background_tasks(priority):
                return {"status": "deferred", "task_id": task_id, "reason": "system_load_or_disk"}

            now = time.time()
            db.execute("UPDATE background_tasks SET state='processing', updated_at=? WHERE id=?", (now, task_id))
            db.commit()

        try:
            result = self._dispatch_task(task_type, payload)
            now = time.time()
            with self.get_db() as db:
                db.execute("UPDATE background_tasks SET state='completed', updated_at=? WHERE id=?", (now, task_id))
                db.commit()
            return {"status": "completed", "task_id": task_id, "result": result}
        except Exception as e:
            now = time.time()
            with self.get_db() as db:
                retries = task.get("retries", 0) + 1
                new_state = "failed" if retries >= 3 else "queued"
                db.execute("""
                    UPDATE background_tasks
                    SET state=?, retries=?, error_message=?, updated_at=?
                    WHERE id=?
                """, (new_state, retries, str(e), now, task_id))
                db.commit()
            return {"status": "error", "task_id": task_id, "error": str(e), "retries": retries}

    def _dispatch_task(self, task_type: str, payload: dict):
        if task_type == "verify_metadata":
            req_id = payload.get("request_id")
            return self.verify_request_metadata(req_id)
        elif task_type == "align_work":
            work_id = payload.get("work_id")
            if "mapping_data" in payload:
                return self.store_alignment(
                    work_id=work_id,
                    epub_edition_id=payload.get("epub_edition_id"),
                    audio_edition_id=payload.get("audio_edition_id"),
                    alignment_level=payload.get("alignment_level", "sentence"),
                    engine=payload.get("engine", "storyteller-stalign"),
                    version=payload.get("version", "1.0.0"),
                    confidence=payload.get("confidence", 0.95),
                    mapping_data=payload["mapping_data"],
                    epub_asset_hash=payload.get("epub_asset_hash"),
                    audio_asset_hash=payload.get("audio_asset_hash"),
                    unmatched_regions=payload.get("unmatched_regions"),
                )
            return {"status": "alignment_queued_or_ready", "work_id": work_id}
        else:
            return {"status": "no_op", "task_type": task_type}
