"""
Tests for Phase 3: Worldwide Book Discovery, Metadata Engine, and Acquisition Coordinator.
"""

import json
import os
import shutil
import tempfile
import time
import unittest
import zipfile

try:
    from books_core import BooksCore
    from book_discovery import WorldwideDiscoveryService
    from metadata_engine import MetadataIngestionEngine
    from book_acquisition import AcquisitionCoordinator
    from worker import BooksWorker
except ImportError:
    from backend.books_core import BooksCore
    from backend.book_discovery import WorldwideDiscoveryService
    from backend.metadata_engine import MetadataIngestionEngine
    from backend.book_acquisition import AcquisitionCoordinator
    from backend.worker import BooksWorker


def create_sample_epub(file_path: str, title: str = "Test Book", author: str = "Test Author"):
    """Helper to create a valid minimal EPUB package."""
    opf_content = f"""<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="pub-id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>{title}</dc:title>
    <dc:creator>{author}</dc:creator>
    <dc:language>en</dc:language>
    <dc:identifier id="pub-id">urn:uuid:12345</dc:identifier>
  </metadata>
  <manifest>
    <item id="content" href="content.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="content"/>
  </spine>
</package>
"""
    container_xml = """<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
"""
    with zipfile.ZipFile(file_path, "w") as z:
        z.writestr("mimetype", b"application/epub+zip", compress_type=zipfile.ZIP_STORED)
        z.writestr("META-INF/container.xml", container_xml)
        z.writestr("OEBPS/content.opf", opf_content)
        z.writestr("OEBPS/content.xhtml", "<html><body><p>Hello world.</p></body></html>")


class TestBookDiscoveryAndAcquisition(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()
        self.db_path = os.path.join(self.temp_dir, "test_books.sqlite")
        self.books_core = BooksCore(self.db_path)
        self.library_dir = os.path.join(self.temp_dir, "library")
        self.books_dir = os.path.join(self.library_dir, "Books")
        self.audio_dir = os.path.join(self.library_dir, "Audiobooks")
        os.makedirs(self.books_dir, exist_ok=True)
        os.makedirs(self.audio_dir, exist_ok=True)

        self.metadata_engine = MetadataIngestionEngine(
            books_library_path=self.books_dir,
            audiobooks_library_path=self.audio_dir,
        )
        self.staging_dir = os.path.join(self.temp_dir, "staging")
        os.makedirs(self.staging_dir, exist_ok=True)
        self.discovery = WorldwideDiscoveryService(self.books_core)
        self.acquisition = AcquisitionCoordinator(
            self.books_core,
            staging_dir=self.staging_dir,
            metadata_engine=self.metadata_engine,
        )

    def tearDown(self):
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_metadata_engine_epub_validation_and_tagging(self):
        epub_file = os.path.join(self.temp_dir, "sample.epub")
        create_sample_epub(epub_file, title="Original Title", author="Original Author")

        # 1. Validation
        info = self.metadata_engine.validate_epub(epub_file)
        self.assertTrue(info["valid"])
        self.assertEqual(info["title"], "Original Title")
        self.assertEqual(info["author"], "Original Author")

        # 2. Embedded Tagging
        self.metadata_engine.write_epub_metadata(
            epub_file,
            title="Corrected Title",
            author="Corrected Author",
            publisher="Penguin Classics",
            year=1895,
            isbn="9780141439563",
        )

        # 3. Verify newly embedded tags
        info2 = self.metadata_engine.validate_epub(epub_file)
        self.assertEqual(info2["title"], "Corrected Title")
        self.assertEqual(info2["author"], "Corrected Author")
        self.assertEqual(info2["publisher"], "Penguin Classics")
        self.assertEqual(info2["date"], "1895")

        # 4. Safe Publishing to Library
        published_path = self.metadata_engine.publish_epub_to_library(
            epub_file, author="Corrected Author", title="Corrected Title"
        )
        self.assertTrue(os.path.exists(published_path))
        self.assertIn("Corrected Title.epub", published_path)
        self.assertTrue(zipfile.is_zipfile(published_path))

    def test_discovery_local_library_enrichment_and_caching(self):
        # 1. Populate a local work in SQLite
        now = time.time()
        with self.books_core.get_db() as db:
            db.execute("""
                INSERT INTO works (id, title, author, description, genres, series_name, series_order, cover_url, created_at, updated_at)
                VALUES ('work-local-1', 'Project Hail Mary', 'Andy Weir', 'Sci-fi novel', '[]', NULL, NULL, 'http://cover.jpg', ?, ?)
            """, (now, now))
            db.execute("""
                INSERT INTO editions (id, work_id, format, title, authors, narrators, publisher, published_year, language, isbn, asin, description, cover_url, created_at, updated_at)
                VALUES ('ed-1', 'work-local-1', 'audiobook', 'Project Hail Mary', '["Andy Weir"]', '["Ray Porter"]', 'Audible', 2021, 'en', '9781665241088', NULL, NULL, NULL, ?, ?)
            """, (now, now))
            db.commit()

        # 2. Simulate raw search results containing the owned book and an unowned book
        raw_items = [
            {
                "source": "openlibrary",
                "external_id": "/works/OL21745884W",
                "title": "Project Hail Mary",
                "author": "Andy Weir",
                "published_year": 2021,
                "cover_url": "https://covers.openlibrary.org/b/id/11200092-L.jpg",
                "isbns": ["9781665241088"],
            },
            {
                "source": "openlibrary",
                "external_id": "/works/OL45804W",
                "title": "The Time Machine",
                "author": "H. G. Wells",
                "published_year": 1895,
                "cover_url": "https://covers.openlibrary.org/b/id/8231991-L.jpg",
                "isbns": ["9780141439976"],
            },
        ]

        # Enrich results
        enriched = self.discovery._enrich_with_local_state(raw_items)
        self.assertEqual(len(enriched), 2)

        # First item must be recognized as local
        hail_mary = enriched[0]
        self.assertTrue(hail_mary["is_local"])
        self.assertEqual(hail_mary["local_work_id"], "work-local-1")
        self.assertEqual(hail_mary["owned_formats"], ["audiobook"])
        self.assertIsNone(hail_mary["request_id"])

        # Second item must be recognized as remote / requestable
        time_machine = enriched[1]
        self.assertFalse(time_machine["is_local"])
        self.assertIsNone(time_machine["local_work_id"])
        self.assertEqual(time_machine["owned_formats"], [])

        # 3. Submit request for The Time Machine
        req = self.books_core.request_book("The Time Machine", "H. G. Wells", format_requested="paired")
        self.assertIn(req["state"], ("requested", "metadata_verified"))

        # 4. Re-enrich: Time Machine now displays active request state!
        enriched_again = self.discovery._enrich_with_local_state(raw_items)
        time_machine_updated = enriched_again[1]
        self.assertEqual(time_machine_updated["request_id"], req["id"])
        self.assertIn(time_machine_updated["request_state"], ("requested", "metadata_verified"))

    def test_acquisition_lifecycle_and_worker(self):
        # 1. Create a request
        req = self.books_core.request_book("The Time Machine", "H. G. Wells", format_requested="epub")
        req_id = req["id"]
        self.assertIn(req["state"], ("requested", "metadata_verified"))

        # 2. Run autonomous worker to process the queued task
        worker = BooksWorker(db_path=self.db_path, poll_interval=1.0)
        # Point coordinator to test directories
        worker.books_core = self.books_core

        # Process the acquisition task
        worker_res = worker.run_once()
        self.assertEqual(worker_res["status"], "completed")

        # 3. Verify request progressed through lifecycle
        updated_req = self.books_core.get_request(req_id)
        # Should have acquired EPUB from Standard Ebooks!
        self.assertIn(updated_req["state"], ("available", "partial"))
        self.assertIn("epub", updated_req["acquired_formats"])
        self.assertEqual(updated_req["progress_percentage"], 100.0)

        # 4. Verify book is now in local works table
        work = self.books_core.get_book(updated_req["work_id"])
        self.assertIsNotNone(work)
        self.assertEqual(work["title"], "The Time Machine")
        self.assertIn("epub", work["available_formats"])


if __name__ == "__main__":
    unittest.main()
