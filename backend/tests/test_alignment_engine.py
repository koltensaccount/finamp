import os
import tempfile
import unittest
import json

from backend.books_core import BooksCore
from backend.alignment_engine import AlignmentEngine, _norm


class AlignmentEngineTests(unittest.TestCase):
    def setUp(self):
        self.tmp_dir = tempfile.TemporaryDirectory()
        self.db_path = os.path.join(self.tmp_dir.name, "test_books.sqlite")
        self.books = BooksCore(self.db_path)

    def tearDown(self):
        self.tmp_dir.cleanup()

    def test_norm_function(self):
        self.assertEqual(_norm("The Time Machine, Chapter 1!"), "the time machine chapter 1")
        self.assertEqual(_norm("  H. G. Wells  "), "h g wells")
        self.assertEqual(_norm(""), "")

    def test_store_and_retrieve_alignment(self):
        work_id = "work-the-time-machine-h-g-wells"
        mappings = [
            {
                "sentence_idx": 0,
                "epub_cfi": "/6/4[chapter-1.xhtml]!/4/2/1:0",
                "text": "The Time Traveller was expounding a recondite matter to us.",
                "audio_track": 1,
                "audio_start_sec": 25.84,
                "audio_end_sec": 31.50,
                "confidence": 0.98,
            },
            {
                "sentence_idx": 1,
                "epub_cfi": "/6/4[chapter-1.xhtml]!/4/2/3:0",
                "text": "His grey eyes shone and twinkled, and his usually pale face was flushed and animated.",
                "audio_track": 1,
                "audio_start_sec": 31.60,
                "audio_end_sec": 38.20,
                "confidence": 0.95,
            },
        ]
        unmatched = [
            {
                "type": "preface_disclaimer",
                "start_sec": 0.0,
                "end_sec": 25.84,
                "reason": "LibriVox opening announcement",
            }
        ]

        rec = self.books.store_alignment(
            work_id=work_id,
            epub_edition_id="ed-epub-1",
            audio_edition_id="ed-audio-1",
            alignment_level="sentence",
            engine="faster-whisper-ctc-matcher",
            version="1.0.0",
            confidence=0.965,
            mapping_data=mappings,
            unmatched_regions=unmatched,
        )

        self.assertIsNotNone(rec)
        self.assertEqual(rec["work_id"], work_id)
        self.assertEqual(rec["alignment_level"], "sentence")
        self.assertEqual(len(rec["mapping_data"]), 2)
        self.assertEqual(len(rec["unmatched_regions"]), 1)

        # Test audio-to-cfi mapping
        loc = self.books.map_audio_to_reading_location(work_id, track_number=1, timestamp_seconds=28.0)
        self.assertIsNotNone(loc)
        self.assertEqual(loc["epub_cfi"], "/6/4[chapter-1.xhtml]!/4/2/1:0")

        # Test cfi-to-audio mapping
        aud = self.books.map_reading_location_to_audio(work_id, "/6/4[chapter-1.xhtml]!/4/2/3:0")
        self.assertIsNotNone(aud)
        self.assertEqual(aud["audio_track"], 1)
        self.assertAlmostEqual(aud["audio_timestamp_seconds"], 31.60)


if __name__ == "__main__":
    unittest.main()
