"""
Book Acquisition Pipeline & Coordinators:
Multi-source authorized adapters (Standard Ebooks, Internet Archive / LibriVox, Prowlarr),
durable staging lifecycle, metadata verification, embedded tagging, and permanent library publishing.
"""

import json
import logging
import os
import shutil
import time
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

try:
    from metadata_engine import MetadataIngestionEngine, _safe_filename, compute_file_sha256
except ImportError:
    from backend.metadata_engine import MetadataIngestionEngine, _safe_filename, compute_file_sha256

logger = logging.getLogger("book_acquisition")


def _norm(s: str) -> str:
    if not s:
        return ""
    return "".join(c.lower() for c in s if c.isalnum() or c.isspace()).strip()


class StandardEbooksAdapter:
    """Acquires curated, DRM-free public domain EPUBs from Standard Ebooks."""

    def search_and_acquire(self, title: str, author: str, staging_dir: str) -> dict:
        encoded_q = urllib.parse.quote(title)
        url = f"https://standardebooks.org/opds/all?query={encoded_q}"
        req = urllib.request.Request(url, headers={"User-Agent": "FinampBooks/2.0"})

        try:
            with urllib.request.urlopen(req, timeout=10) as resp:
                if resp.status != 200:
                    return {"acquired": False, "error": f"HTTP {resp.status}"}
                xml_data = resp.read()

            root = ET.fromstring(xml_data)
            ns = {"atom": "http://www.w3.org/2005/Atom"}
            entries = root.findall("atom:entry", ns)
            if not entries:
                return {"acquired": False, "error": "No entries found"}

            target_norm = _norm(title)
            best_entry = None
            for e in entries:
                e_title = e.find("atom:title", ns)
                if e_title is not None and e_title.text:
                    if target_norm in _norm(e_title.text):
                        best_entry = e
                        break
            if best_entry is None:
                best_entry = entries[0]

            # Find EPUB download link
            epub_link = None
            for link in best_entry.findall("atom:link", ns):
                if link.attrib.get("type") == "application/epub+zip":
                    epub_link = link.attrib.get("href")
                    break

            if not epub_link:
                return {"acquired": False, "error": "No EPUB download link in feed"}

            # Download EPUB to staging
            os.makedirs(staging_dir, exist_ok=True)
            slug = _safe_filename(title)
            dest_file = os.path.join(staging_dir, f"{slug}.epub")

            dl_req = urllib.request.Request(epub_link, headers={"User-Agent": "FinampBooks/2.0"})
            with urllib.request.urlopen(dl_req, timeout=20) as dl_resp:
                epub_bytes = dl_resp.read()

            # Verify zip magic bytes PK\x03\x04
            if len(epub_bytes) < 4 or epub_bytes[:2] != b"PK":
                return {"acquired": False, "error": "Downloaded file is not a valid zip/epub"}

            with open(dest_file, "wb") as f:
                f.write(epub_bytes)

            return {
                "acquired": True,
                "file_path": dest_file,
                "file_size": len(epub_bytes),
                "source": "standard_ebooks",
                "format": "epub",
            }
        except Exception as e:
            return {"acquired": False, "error": str(e)}


class InternetArchiveLibriVoxAdapter:
    """Acquires public domain audiobooks from Internet Archive LibriVox collection."""

    def search_and_acquire(self, title: str, author: str, staging_dir: str, max_tracks: int = 50) -> dict:
        encoded_q = urllib.parse.quote(f"collection:(librivoxaudio) AND title:({title})")
        url = f"https://archive.org/advancedsearch.php?q={encoded_q}&fl[]=identifier,title,creator&sort[]=downloads+desc&rows=3&page=1&output=json"
        req = urllib.request.Request(url, headers={"User-Agent": "FinampBooks/2.0"})

        try:
            with urllib.request.urlopen(req, timeout=10) as resp:
                if resp.status != 200:
                    return {"acquired": False, "error": f"HTTP {resp.status}"}
                data = json.loads(resp.read().decode("utf-8"))

            docs = data.get("response", {}).get("docs", [])
            if not docs:
                return {"acquired": False, "error": "No audiobooks found on Internet Archive"}

            identifier = docs[0].get("identifier")
            if not identifier:
                return {"acquired": False, "error": "No identifier in search result"}

            # Fetch file list
            meta_url = f"https://archive.org/metadata/{identifier}/files"
            meta_req = urllib.request.Request(meta_url, headers={"User-Agent": "FinampBooks/2.0"})
            with urllib.request.urlopen(meta_req, timeout=10) as meta_resp:
                meta_data = json.loads(meta_resp.read().decode("utf-8"))

            files = meta_data.get("result", [])
            # Filter mp3 tracks
            mp3_files = [f for f in files if f.get("name", "").lower().endswith(".mp3") and "64kb" not in f.get("name", "").lower()]
            if not mp3_files:
                mp3_files = [f for f in files if f.get("name", "").lower().endswith(".mp3")]

            if not mp3_files:
                return {"acquired": False, "error": "No MP3 tracks found in item"}

            # Sort tracks alphabetically or by track
            mp3_files.sort(key=lambda x: x.get("name", ""))
            tracks_to_dl = mp3_files[:max_tracks]

            os.makedirs(staging_dir, exist_ok=True)
            downloaded_paths = []

            for idx, tr in enumerate(tracks_to_dl, 1):
                tr_name = tr.get("name")
                dl_url = f"https://archive.org/download/{identifier}/{urllib.parse.quote(tr_name)}"
                local_name = f"{idx:02d} - {tr_name}"
                dest_path = os.path.join(staging_dir, local_name)

                track_req = urllib.request.Request(dl_url, headers={"User-Agent": "FinampBooks/2.0"})
                with urllib.request.urlopen(track_req, timeout=30) as tr_resp:
                    content = tr_resp.read()

                with open(dest_path, "wb") as f:
                    f.write(content)
                downloaded_paths.append(dest_path)

            return {
                "acquired": True,
                "file_paths": downloaded_paths,
                "source": "internet_archive_librivox",
                "format": "audiobook",
                "total_tracks": len(downloaded_paths),
            }
        except Exception as e:
            return {"acquired": False, "error": str(e)}


class AcquisitionCoordinator:
    def __init__(self, books_core, staging_dir=None, metadata_engine=None):
        self.books_core = books_core
        if staging_dir:
            self.staging_dir = staging_dir
        elif os.environ.get("BOOKS_STAGING_DIR"):
            self.staging_dir = os.environ["BOOKS_STAGING_DIR"]
        elif os.path.exists("/home/koltensaccount/music-metadata-audit/catalog-index/staging"):
            self.staging_dir = "/home/koltensaccount/music-metadata-audit/catalog-index/staging"
        else:
            import tempfile
            self.staging_dir = os.path.join(tempfile.gettempdir(), "finamp_books_staging")

        self.metadata_engine = metadata_engine or MetadataIngestionEngine()
        self.standard_ebooks = StandardEbooksAdapter()
        self.ia_librivox = InternetArchiveLibriVoxAdapter()

    def process_acquisition(self, request_id: str) -> dict:
        req = self.books_core.get_request(request_id)
        if not req:
            raise ValueError(f"Request {request_id} not found")

        title = req["title"]
        author = req["author"]
        fmt = req.get("format_requested", "paired")
        staging_req_dir = os.path.join(self.staging_dir, request_id)

        # 1. State: searching
        self.books_core.update_request_state(
            request_id=request_id,
            state="searching",
            staging_path=staging_req_dir,
            progress_percentage=15.0,
        )

        acquired_formats = []
        epub_result = None
        audio_result = None

        # 2. State: acquiring
        self.books_core.update_request_state(
            request_id=request_id,
            state="acquiring",
            progress_percentage=35.0,
        )

        # Try acquiring EPUB if requested
        if fmt in ("epub", "paired"):
            epub_staging_dir = os.path.join(staging_req_dir, "epub")
            epub_result = self.standard_ebooks.search_and_acquire(title, author, epub_staging_dir)
            if epub_result.get("acquired"):
                acquired_formats.append("epub")

        # Try acquiring Audiobook if requested
        if fmt in ("audiobook", "paired"):
            audio_staging_dir = os.path.join(staging_req_dir, "audio")
            audio_result = self.ia_librivox.search_and_acquire(title, author, audio_staging_dir)
            if audio_result.get("acquired"):
                acquired_formats.append("audiobook")

        if not acquired_formats:
            err_msg = "No authorized open-access sources currently have this title available for automatic download"
            self.books_core.update_request_state(
                request_id=request_id,
                state="needs_review",
                error_message=err_msg,
                progress_percentage=0.0,
            )
            return self.books_core.get_request(request_id)

        # 3. State: verifying (Metadata-First Ingestion)
        self.books_core.update_request_state(
            request_id=request_id,
            state="verifying",
            acquired_formats=acquired_formats,
            progress_percentage=60.0,
        )

        # If EPUB was acquired: validate and embed metadata
        published_epub = None
        if epub_result and epub_result.get("acquired"):
            src_epub = epub_result["file_path"]
            try:
                self.metadata_engine.validate_epub(src_epub)
                self.metadata_engine.write_epub_metadata(
                    src_epub,
                    title=title,
                    author=author,
                    language="en",
                )
            except Exception as e:
                logger.warning(f"Metadata tagging warning on {src_epub}: {e}")

        # If Audio was acquired: inspect and embed tags
        if audio_result and audio_result.get("acquired"):
            for tr_path in audio_result.get("file_paths", []):
                try:
                    self.metadata_engine.write_audio_metadata(
                        tr_path,
                        title=os.path.splitext(os.path.basename(tr_path))[0],
                        artist=author,
                        album=title,
                    )
                except Exception as e:
                    logger.warning(f"Audio metadata tagging warning on {tr_path}: {e}")

        # 4. State: importing
        self.books_core.update_request_state(
            request_id=request_id,
            state="importing",
            progress_percentage=80.0,
        )

        published_epub_path = None
        published_audio_paths = []

        if epub_result and epub_result.get("acquired"):
            try:
                published_epub_path = self.metadata_engine.publish_epub_to_library(
                    epub_result["file_path"], author=author, title=title
                )
            except Exception as e:
                logger.warning(f"Could not publish EPUB to library directory: {e}")

        if audio_result and audio_result.get("acquired"):
            try:
                published_audio_paths = self.metadata_engine.publish_audiobook_to_library(
                    audio_result["file_paths"], author=author, title=title
                )
            except Exception as e:
                logger.warning(f"Could not publish audiobook to library directory: {e}")

        # Ingest directly into Books Core database
        work_slug = f"work-{_norm(title).replace(' ', '-')}-{_norm(author).replace(' ', '-')}"
        now = time.time()

        with self.books_core.get_db() as db:
            db.execute("""
                INSERT INTO works (id, title, author, description, genres, series_name, series_order, cover_url, created_at, updated_at)
                VALUES (?, ?, ?, ?, '[]', NULL, NULL, NULL, ?, ?)
                ON CONFLICT(id) DO UPDATE SET updated_at=excluded.updated_at
            """, (work_slug, title, author, req.get("metadata", {}).get("description"), now, now))

            if published_epub_path:
                ed_id = f"ed-{work_slug}-epub"
                db.execute("""
                    INSERT INTO editions (id, work_id, format, title, authors, narrators, publisher, published_year, language, isbn, asin, description, cover_url, created_at, updated_at)
                    VALUES (?, ?, 'epub', ?, ?, '[]', ?, ?, 'en', ?, NULL, ?, NULL, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET updated_at=excluded.updated_at
                """, (
                    ed_id, work_slug, title, json.dumps([author]),
                    req.get("metadata", {}).get("publisher"),
                    req.get("metadata", {}).get("first_publish_year"),
                    req.get("isbn"),
                    req.get("metadata", {}).get("description"),
                    now, now
                ))

                asset_id = f"asset-{ed_id}"
                db.execute("""
                    INSERT INTO assets (id, edition_id, kind, file_path, file_size, mime_type, format, duration_seconds, track_number, abs_item_id, abs_file_ino, created_at)
                    VALUES (?, ?, 'epub', ?, ?, 'application/epub+zip', 'epub', NULL, NULL, NULL, NULL, ?)
                    ON CONFLICT(id) DO UPDATE SET file_path=excluded.file_path, file_size=excluded.file_size
                """, (asset_id, ed_id, published_epub_path, os.path.getsize(published_epub_path), now))

            if published_audio_paths:
                ed_id = f"ed-{work_slug}-audio"
                db.execute("""
                    INSERT INTO editions (id, work_id, format, title, authors, narrators, publisher, published_year, language, isbn, asin, description, cover_url, created_at, updated_at)
                    VALUES (?, ?, 'audiobook', ?, ?, '[]', NULL, NULL, 'en', NULL, NULL, NULL, NULL, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET updated_at=excluded.updated_at
                """, (ed_id, work_slug, title, json.dumps([author]), now, now))

                for idx, a_path in enumerate(published_audio_paths, 1):
                    asset_id = f"asset-{ed_id}-{idx}"
                    db.execute("""
                        INSERT INTO assets (id, edition_id, kind, file_path, file_size, mime_type, format, duration_seconds, track_number, abs_item_id, abs_file_ino, created_at)
                        VALUES (?, ?, 'audio_track', ?, ?, 'audio/mpeg', 'mp3', 0.0, ?, NULL, NULL, ?)
                        ON CONFLICT(id) DO UPDATE SET file_path=excluded.file_path
                    """, (asset_id, ed_id, a_path, os.path.getsize(a_path), idx, now))

            db.commit()

        # Trigger Audiobookshelf scan if endpoint available
        self._trigger_abs_scan()

        # 5. Determine final request state
        final_state = "available"
        if fmt == "paired" and len(acquired_formats) == 1:
            final_state = "partial"

        self.books_core.update_request_state(
            request_id=request_id,
            state=final_state,
            acquired_formats=acquired_formats,
            progress_percentage=100.0,
        )

        # If both formats exist, enqueue alignment
        if len(acquired_formats) >= 2 or (published_epub_path and published_audio_paths):
            self.books_core.enqueue_task(
                task_type="align_work",
                payload={"work_id": work_slug},
                priority="opportunistic"
            )

        return self.books_core.get_request(request_id)

    def _trigger_abs_scan(self):
        abs_url = os.environ.get("ABS_URL", "http://127.0.0.1:13378")
        abs_token = os.environ.get("ABS_TOKEN", "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VySWQiOiI0M2IwZjY1NS0xZjc3LTQ1ZDAtYTFlMC1hNWEyN2MzNzE3NjEiLCJ1c2VybmFtZSI6InJvb3QiLCJpYXQiOjE3NzM5NTI4OTF9.GbOc3bhWXnr8-r9ewGul2OBVgs2s_HWbKjAkvJW0qV0")

        # Scan Books library
        try:
            req = urllib.request.Request(
                f"{abs_url}/api/libraries/0f39b9e1-8501-424b-9cb5-1e59f64b605f/scan",
                headers={"Authorization": f"Bearer {abs_token}"},
                method="POST"
            )
            urllib.request.urlopen(req, timeout=5)
        except Exception:
            pass
