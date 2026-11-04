import json
import os
import tempfile
import threading
import unittest
import urllib.request
from http.server import HTTPServer

from backend.books_core import BooksCore
from backend.server import Handler


class TestBooksEndpoints(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.token = "test-token-123"
        os.environ["CATALOG_API_TOKEN"] = cls.token

        cls.cat_db = tempfile.NamedTemporaryFile(suffix=".sqlite", delete=False)
        cls.cat_db.close()
        cls.books_db = tempfile.NamedTemporaryFile(suffix=".sqlite", delete=False)
        cls.books_db.close()

        cls.books = BooksCore(cls.books_db.name)
        # Seed test book
        with cls.books.get_db() as db:
            db.execute("""
                INSERT INTO works (id, title, author, description, genres, cover_url, created_at, updated_at)
                VALUES ('work-1', 'The Great Gatsby', 'F. Scott Fitzgerald', 'Jazz age masterpiece', '["Fiction"]', 'http://example.com/cover.jpg', 1, 1)
            """)
            db.execute("""
                INSERT INTO editions (id, work_id, format, title, publisher, published_year, language, isbn, cover_url, created_at, updated_at)
                VALUES ('ed-1', 'work-1', 'epub', 'The Great Gatsby', 'Scribner', 1925, 'en', '9780743273565', 'http://example.com/cover.jpg', 1, 1)
            """)
            db.commit()

        cls.server = HTTPServer(("127.0.0.1", 0), Handler)
        cls.server.database = cls.cat_db.name
        cls.server.books = cls.books
        cls.port = cls.server.server_port

        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        for f in (cls.cat_db.name, cls.books_db.name):
            if os.path.exists(f):
                os.unlink(f)

    def _req(self, path, method="GET", body=None, token=None):
        req = urllib.request.Request(
            f"http://127.0.0.1:{self.port}{path}",
            headers={"Authorization": f"Bearer {token or self.token}", "Content-Type": "application/json"},
            method=method,
            data=json.dumps(body).encode() if body else None,
        )
        with urllib.request.urlopen(req, timeout=5) as resp:
            return resp.status, json.loads(resp.read().decode())

    def test_auth_rejection(self):
        with self.assertRaises(urllib.error.HTTPError) as ctx:
            self._req("/v1/books", token="invalid")
        self.assertEqual(ctx.exception.code, 401)

    def test_list_books_endpoint(self):
        status, data = self._req("/v1/books")
        self.assertEqual(status, 200)
        self.assertIn("books", data)
        self.assertEqual(len(data["books"]), 1)
        self.assertEqual(data["books"][0]["title"], "The Great Gatsby")

    def test_get_book_endpoint(self):
        status, data = self._req("/v1/books/work-1")
        self.assertEqual(status, 200)
        self.assertEqual(data["title"], "The Great Gatsby")
        self.assertEqual(len(data["editions"]), 1)

    def test_progress_endpoints(self):
        # Update progress
        status, updated = self._req(
            "/v1/books/work-1/progress",
            method="POST",
            body={"reading_cfi": "/6/2!/4/10", "reading_percentage": 0.35, "active_format": "reading"},
        )
        self.assertEqual(status, 200)
        self.assertEqual(updated["progress"]["reading_cfi"], "/6/2!/4/10")
        self.assertEqual(updated["progress"]["reading_percentage"], 0.35)

        # Get progress
        status, prog = self._req("/v1/books/work-1/progress")
        self.assertEqual(status, 200)
        self.assertEqual(prog["reading_cfi"], "/6/2!/4/10")
        self.assertEqual(prog["reading_percentage"], 0.35)

    def test_annotations_endpoints(self):
        # Add annotation
        status, res = self._req(
            "/v1/books/work-1/annotations",
            method="POST",
            body={"edition_id": "ed-1", "kind": "bookmark", "cfi_range": "/6/2!/4/2", "note": "Great quote"},
        )
        self.assertEqual(status, 200)
        anno_id = res["id"]

        # Get annotations
        status, annos = self._req("/v1/books/work-1/annotations")
        self.assertEqual(status, 200)
        self.assertEqual(len(annos["annotations"]), 1)
        self.assertEqual(annos["annotations"][0]["note"], "Great quote")

        # Delete annotation
        status, d_res = self._req(f"/v1/books/work-1/annotations/{anno_id}", method="DELETE")
        self.assertEqual(status, 200)
        self.assertEqual(d_res["status"], "deleted")

    def test_book_requests_endpoints(self):
        # Create request
        status, res = self._req(
            "/v1/books/requests",
            method="POST",
            body={"title": "Hyperion", "author": "Dan Simmons", "format_requested": "paired"},
        )
        self.assertEqual(status, 200)
        req_id = res["id"]
        self.assertEqual(res["title"], "Hyperion")

        # List requests
        status, list_res = self._req("/v1/books/requests")
        self.assertEqual(status, 200)
        self.assertIn("requests", list_res)
        self.assertTrue(any(r["id"] == req_id for r in list_res["requests"]))

        # Get request by id
        status, get_res = self._req(f"/v1/books/requests/{req_id}")
        self.assertEqual(status, 200)
        self.assertEqual(get_res["id"], req_id)

        # Update request state
        status, updated_res = self._req(
            f"/v1/books/requests/{req_id}/state",
            method="POST",
            body={"state": "staging", "staging_path": "/mnt/staging/hyperion"},
        )
        self.assertEqual(status, 200)
        self.assertEqual(updated_res["state"], "staging")
        self.assertEqual(updated_res["staging_path"], "/mnt/staging/hyperion")

    def test_security_rejections_and_signed_tickets(self):
        import time
        from backend.server import generate_media_ticket

        # 1. Direct unauthenticated requests to media endpoints must be rejected with 401
        for unauth_path in [
            "/v1/books/work-1/cover",
            "/v1/books/work-1/epub",
            "/v1/books/work-1/audio/1",
            "/v1/books/requests",
        ]:
            req = urllib.request.Request(f"http://127.0.0.1:{self.port}{unauth_path}")
            with self.assertRaises(urllib.error.HTTPError) as ctx:
                urllib.request.urlopen(req, timeout=5)
            self.assertEqual(ctx.exception.code, 401, f"{unauth_path} was not protected with 401!")

        # 2. Issue a scoped ticket via authenticated /v1/ticket
        status, ticket_res = self._req("/v1/ticket?path=/v1/books/work-1/cover&ttl=300")
        self.assertEqual(status, 200)
        self.assertIn("ticket", ticket_res)
        self.assertIn("expires", ticket_res)

        # 3. Access with an expired ticket must be rejected with 401
        past_expires = int(time.time()) - 100
        expired_ticket = generate_media_ticket(self.token, "/v1/books/work-1/cover", past_expires)
        expired_req = urllib.request.Request(
            f"http://127.0.0.1:{self.port}/v1/books/work-1/cover?ticket={expired_ticket}&expires={past_expires}"
        )
        with self.assertRaises(urllib.error.HTTPError) as ctx:
            urllib.request.urlopen(expired_req, timeout=5)
        self.assertEqual(ctx.exception.code, 401)

        # 4. Access with a tampered ticket must be rejected with 401
        tampered_req = urllib.request.Request(
            f"http://127.0.0.1:{self.port}/v1/books/work-1/cover?ticket=badbadbadbadbadbadbadbadbadbadbadbadbadbadbadbadbadbadbadbadbadb&expires={int(time.time()) + 300}"
        )
        with self.assertRaises(urllib.error.HTTPError) as ctx:
            urllib.request.urlopen(tampered_req, timeout=5)
        self.assertEqual(ctx.exception.code, 401)

    def test_alignment_engine_and_bidirectional_mapping(self):
        # 1. Book without alignment returns 404 on /alignment
        with self.assertRaises(urllib.error.HTTPError) as ctx:
            self._req("/v1/books/work-1/alignment")
        self.assertEqual(ctx.exception.code, 404)

        # 2. Store genuine sentence-level alignment
        mapping_data = [
            {
                "sentence_idx": 1,
                "epub_cfi": "/6/2[ch01]!/4/2/1",
                "text": "In my younger and more vulnerable years...",
                "audio_track": 1,
                "audio_start_sec": 0.0,
                "audio_end_sec": 5.4,
                "confidence": 0.98,
            },
            {
                "sentence_idx": 2,
                "epub_cfi": "/6/2[ch01]!/4/2/3",
                "text": "my father gave me some advice...",
                "audio_track": 1,
                "audio_start_sec": 5.4,
                "audio_end_sec": 12.1,
                "confidence": 0.97,
            },
            {
                "sentence_idx": 3,
                "epub_cfi": "/6/4[ch02]!/4/2/1",
                "text": "About half way between West Egg...",
                "audio_track": 2,
                "audio_start_sec": 0.0,
                "audio_end_sec": 6.8,
                "confidence": 0.95,
            },
        ]

        status, stored = self._req(
            "/v1/books/work-1/alignment",
            method="POST",
            body={
                "epub_edition_id": "ed-epub-1",
                "audio_edition_id": "ed-audio-1",
                "alignment_level": "sentence",
                "engine": "storyteller-stalign",
                "version": "1.0.0",
                "confidence": 0.97,
                "mapping_data": mapping_data,
                "epub_asset_hash": "sha256:1111111111111111",
                "audio_asset_hash": "sha256:2222222222222222",
                "unmatched_regions": [],
            },
        )
        self.assertEqual(status, 200)
        self.assertEqual(stored["alignment_level"], "sentence")
        self.assertEqual(len(stored["mapping_data"]), 3)

        # 3. Retrieve stored alignment
        status, fetched = self._req("/v1/books/work-1/alignment")
        self.assertEqual(status, 200)
        self.assertEqual(fetched["confidence"], 0.97)

        # 4. Audio to CFI bidirectional mapping
        status, cfi_res = self._req("/v1/books/work-1/align/audio-to-cfi?track=1&sec=8.0")
        self.assertEqual(status, 200)
        self.assertEqual(cfi_res["epub_cfi"], "/6/2[ch01]!/4/2/3")
        self.assertEqual(cfi_res["sentence_idx"], 2)

        # Track 2 start
        status, cfi_res2 = self._req("/v1/books/work-1/align/audio-to-cfi?track=2&sec=3.5")
        self.assertEqual(status, 200)
        self.assertEqual(cfi_res2["epub_cfi"], "/6/4[ch02]!/4/2/1")

        # 5. CFI to Audio bidirectional mapping
        status, audio_res = self._req("/v1/books/work-1/align/cfi-to-audio?cfi=/6/2[ch01]!/4/2/3")
        self.assertEqual(status, 200)
        self.assertEqual(audio_res["audio_track"], 1)
        self.assertEqual(audio_res["audio_timestamp_seconds"], 5.4)

        # CFI prefix match
        status, prefix_res = self._req("/v1/books/work-1/align/cfi-to-audio?cfi=/6/4[ch02]!/4/99/99")
        self.assertEqual(status, 200)
        self.assertEqual(prefix_res["audio_track"], 2)
        self.assertEqual(prefix_res["audio_timestamp_seconds"], 0.0)

    def test_background_task_queue(self):
        # 1. Enqueue opportunistic task
        status, task1 = self._req(
            "/v1/tasks",
            method="POST",
            body={
                "task_type": "align_work",
                "priority": "opportunistic",
                "payload": {"work_id": "work-opp"},
            },
        )
        self.assertEqual(status, 200)
        self.assertEqual(task1["priority"], "opportunistic")
        self.assertEqual(task1["state"], "queued")

        # 2. Enqueue immediate task (should be prioritized over opportunistic)
        status, task2 = self._req(
            "/v1/tasks",
            method="POST",
            body={
                "task_type": "align_work",
                "priority": "immediate",
                "payload": {"work_id": "work-imm"},
            },
        )
        self.assertEqual(status, 200)
        self.assertEqual(task2["priority"], "immediate")

        # 3. List tasks
        status, task_list = self._req("/v1/tasks")
        self.assertEqual(status, 200)
        self.assertGreaterEqual(len(task_list["tasks"]), 2)

        # 4. Process next task: immediate must be processed first!
        status, proc_res = self._req("/v1/tasks/process-next", method="POST")
        self.assertEqual(status, 200)
        self.assertEqual(proc_res["task_id"], task2["id"])
        self.assertEqual(proc_res["status"], "completed")

        # 5. Process next task again: opportunistic is processed next
        status, proc_res2 = self._req("/v1/tasks/process-next", method="POST")
        self.assertEqual(status, 200)
        self.assertEqual(proc_res2["task_id"], task1["id"])
        self.assertEqual(proc_res2["status"], "completed")

        # 6. Idle when queue is empty
        status, idle_res = self._req("/v1/tasks/process-next", method="POST")
        self.assertEqual(status, 200)
        self.assertEqual(idle_res["status"], "idle")


if __name__ == "__main__":
    unittest.main()
