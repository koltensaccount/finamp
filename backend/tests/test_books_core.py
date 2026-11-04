import json
import os
import tempfile
import unittest

from backend.books_core import BooksCore


class TestBooksCore(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.NamedTemporaryFile(suffix=".sqlite", delete=False)
        self.tmp.close()
        self.core = BooksCore(self.tmp.name)

    def tearDown(self):
        if os.path.exists(self.tmp.name):
            os.unlink(self.tmp.name)

    def test_empty_library(self):
        books = self.core.list_books()
        self.assertEqual(books, [])

    def test_manual_work_and_edition_lifecycle(self):
        with self.core.get_db() as db:
            db.execute("""
                INSERT INTO works (id, title, author, description, genres, cover_url, created_at, updated_at)
                VALUES ('work-gatsby', 'The Great Gatsby', 'F. Scott Fitzgerald', 'Classic jazz age novel', '["Fiction"]', 'http://example.com/cover.jpg', 1000, 1000)
            """)
            db.execute("""
                INSERT INTO editions (id, work_id, format, title, publisher, published_year, language, isbn, cover_url, created_at, updated_at)
                VALUES ('ed-gatsby-epub', 'work-gatsby', 'epub', 'The Great Gatsby', 'Scribner', 1925, 'en', '9780743273565', 'http://example.com/cover.jpg', 1000, 1000)
            """)
            db.execute("""
                INSERT INTO chapters (id, edition_id, index_num, title, start_seconds, end_seconds, epub_href, epub_cfi)
                VALUES ('ch-1', 'ed-gatsby-epub', 1, 'Chapter 1', 0, 0, 'chapter1.xhtml', '/6/2[ch01]!/4/2')
            """)
            db.commit()

        books = self.core.list_books()
        self.assertEqual(len(books), 1)
        self.assertEqual(books[0]["title"], "The Great Gatsby")
        self.assertEqual(books[0]["author"], "F. Scott Fitzgerald")
        self.assertEqual(books[0]["available_formats"], ["epub"])
        self.assertFalse(books[0]["is_paired"])

        detail = self.core.get_book("work-gatsby")
        self.assertIsNotNone(detail)
        self.assertEqual(len(detail["editions"]), 1)
        self.assertEqual(len(detail["editions"][0]["chapters"]), 1)
        self.assertEqual(detail["editions"][0]["chapters"][0]["title"], "Chapter 1")

    def test_progress_tracking_and_handoff(self):
        with self.core.get_db() as db:
            db.execute("""
                INSERT INTO works (id, title, author, created_at, updated_at)
                VALUES ('work-hobbit', 'The Hobbit', 'J.R.R. Tolkien', 1000, 1000)
            """)
            db.execute("""
                INSERT INTO editions (id, work_id, format, title, created_at, updated_at)
                VALUES ('ed-hobbit-audio', 'work-hobbit', 'audiobook', 'The Hobbit', 1000, 1000)
            """)
            db.commit()

        # Update listening progress
        res = self.core.update_progress(
            "work-hobbit",
            listening_seconds=125.5,
            listening_track_id="tr-1",
            listening_percentage=0.15,
            active_format="listening"
        )
        self.assertIsNotNone(res)
        self.assertEqual(res["progress"]["listening_seconds"], 125.5)
        self.assertEqual(res["progress"]["listening_track_id"], "tr-1")
        self.assertEqual(res["progress"]["last_active_format"], "listening")

        # Now update reading progress (e.g. user switched to reading)
        res2 = self.core.update_progress(
            "work-hobbit",
            reading_cfi="/6/4[ch02]!/4/10",
            reading_percentage=0.20,
            active_format="reading"
        )
        self.assertEqual(res2["progress"]["reading_cfi"], "/6/4[ch02]!/4/10")
        self.assertEqual(res2["progress"]["reading_percentage"], 0.20)
        # Listening progress should be preserved independently
        self.assertEqual(res2["progress"]["listening_seconds"], 125.5)
        self.assertEqual(res2["progress"]["last_active_format"], "reading")

    def test_annotations_crud(self):
        with self.core.get_db() as db:
            db.execute("INSERT INTO works (id, title, author, created_at, updated_at) VALUES ('w1', 'Title', 'Author', 1, 1)")
            db.execute("INSERT INTO editions (id, work_id, format, title, created_at, updated_at) VALUES ('e1', 'w1', 'epub', 'Title', 1, 1)")
            db.commit()

        created = self.core.add_annotation(
            work_id="w1",
            edition_id="e1",
            kind="highlight",
            cfi_range="/6/2!/4/2/1,/4/2/5",
            highlight_color="#FF3B30",
            selected_text="So we beat on, boats against the current",
            note="Iconic final sentence"
        )
        self.assertIn("id", created)
        anno_id = created["id"]

        annos = self.core.get_annotations("w1")
        self.assertEqual(len(annos), 1)
        self.assertEqual(annos[0]["selected_text"], "So we beat on, boats against the current")
        self.assertEqual(annos[0]["note"], "Iconic final sentence")

        self.core.delete_annotation(anno_id)
        self.assertEqual(self.core.get_annotations("w1"), [])

    def test_search_and_format_filter(self):
        with self.core.get_db() as db:
            db.execute("INSERT INTO works (id, title, author, created_at, updated_at) VALUES ('w1', 'Dune', 'Frank Herbert', 1, 1)")
            db.execute("INSERT INTO editions (id, work_id, format, title, created_at, updated_at) VALUES ('e1', 'w1', 'epub', 'Dune', 1, 1)")

            db.execute("INSERT INTO works (id, title, author, created_at, updated_at) VALUES ('w2', 'Neuromancer', 'William Gibson', 1, 1)")
            db.execute("INSERT INTO editions (id, work_id, format, title, created_at, updated_at) VALUES ('e2', 'w2', 'audiobook', 'Neuromancer', 1, 1)")
            db.commit()

        # Query search
        results = self.core.list_books(query="dune")
        self.assertEqual(len(results), 1)
        self.assertEqual(results[0]["title"], "Dune")

        # Format filter
        audio_only = self.core.list_books(format_filter="audiobook")
        self.assertEqual(len(audio_only), 1)
        self.assertEqual(audio_only[0]["title"], "Neuromancer")

    def test_book_acquisition_request_flow(self):
        # 1. New request
        req = self.core.request_book("Foundation", "Isaac Asimov", format_requested="paired")
        self.assertIsNotNone(req["id"])
        self.assertIn(req["state"], ["requested", "metadata_verified"])
        self.assertEqual(req["title"], "Foundation")
        self.assertEqual(req["author"], "Isaac Asimov")

        req_id = req["id"]

        # 2. Idempotent deduplication
        dup = self.core.request_book("Foundation", "Isaac Asimov")
        self.assertEqual(dup["request_id"], req_id)

        # 3. State transitions
        staged = self.core.update_request_state(req_id, "staging", staging_path="/tmp/staging/foundation")
        self.assertEqual(staged["state"], "staging")
        self.assertEqual(staged["staging_path"], "/tmp/staging/foundation")

        # 4. Filter requests
        reqs = self.core.list_requests(state="staging")
        self.assertEqual(len(reqs), 1)
        self.assertEqual(reqs[0]["id"], req_id)

        # 5. Already owned check
        with self.core.get_db() as db:
            db.execute("INSERT INTO works (id, title, author, created_at, updated_at) VALUES ('work-dune-frank-herbert', 'Dune', 'Frank Herbert', 1, 1)")
            db.commit()

        owned = self.core.request_book("Dune", "Frank Herbert")
        self.assertEqual(owned["state"], "available")
        self.assertEqual(owned["work_id"], "work-dune-frank-herbert")


if __name__ == "__main__":
    unittest.main()
