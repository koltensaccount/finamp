"""
Autonomous Background Worker for Books Ecosystem:
Processes queued background tasks (acquisitions, metadata verification, alignments)
with system load monitoring, disk space safeguards, exponential backoff, and robust error recovery.
"""

import argparse
import logging
import os
import signal
import sys
import time

try:
    from books_core import BooksCore
except ImportError:
    from backend.books_core import BooksCore

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] [BooksWorker] %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)]
)
logger = logging.getLogger("books_worker")


class BooksWorker:
    def __init__(self, db_path="books.sqlite", poll_interval=3.0):
        self.books_core = BooksCore(db_path)
        self.poll_interval = poll_interval
        self._running = True

        signal.signal(signal.SIGINT, self._handle_signal)
        signal.signal(signal.SIGTERM, self._handle_signal)

    def _handle_signal(self, signum, frame):
        logger.info(f"Received signal {signum}. Shutting down worker gracefully...")
        self._running = False

    def run_once(self) -> dict:
        """Process one pending task if available and resources permit."""
        try:
            res = self.books_core.process_next_task()
            if res.get("status") == "completed":
                logger.info(f"Task {res.get('task_id')} completed successfully: {res.get('result')}")
            elif res.get("status") == "deferred":
                logger.info(f"Task {res.get('task_id')} deferred due to resource constraints: {res.get('reason')}")
            elif res.get("status") == "error":
                logger.warning(f"Task {res.get('task_id')} failed: {res.get('error')} (retry {res.get('retries')})")
            return res
        except Exception as e:
            logger.error(f"Unexpected worker exception: {e}", exc_info=True)
            return {"status": "exception", "error": str(e)}

    def run_forever(self):
        logger.info("Books background worker started. Monitoring task queue...")
        consecutive_idle = 0

        while self._running:
            res = self.run_once()
            status = res.get("status")

            if status == "idle":
                consecutive_idle += 1
                # Sleep between polling
                time.sleep(self.poll_interval)
            elif status == "deferred":
                # System is busy or low on disk, wait longer before re-trying
                time.sleep(min(30.0, self.poll_interval * 4))
            else:
                consecutive_idle = 0
                # Give a short breather between tasks
                time.sleep(0.5)

        logger.info("Books background worker terminated.")


def main():
    parser = argparse.ArgumentParser(description="Finamp Books Background Worker")
    parser.add_argument("--database", default=os.environ.get("BOOKS_DATABASE", "books.sqlite"))
    parser.add_argument("--interval", type=float, default=3.0)
    parser.add_argument("--once", action="store_true", help="Process at most one task and exit")
    args = parser.parse_args()

    worker = BooksWorker(db_path=args.database, poll_interval=args.interval)
    if args.once:
        res = worker.run_once()
        print(f"Single task execution: {res}")
    else:
        worker.run_forever()


if __name__ == "__main__":
    main()
