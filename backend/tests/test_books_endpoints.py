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


if __name__ == "__main__":
    unittest.main()
