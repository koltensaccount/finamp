"""Test to ensure no exposed administrative credentials exist in tracked files."""
import re, unittest
from pathlib import Path

class SecretScanTests(unittest.TestCase):
    def test_no_hardcoded_secrets_in_backend(self):
        backend_dir = Path(__file__).resolve().parents[1]
        
        # Patterns for known exposed keys/tokens (redacted patterns)
        suspicious_patterns = [
            re.compile(r'8caa7cceb8a5[0-9a-fA-F]{20}'),
            re.compile(r'dKFTvjXGZxos[0-9a-zA-Z]{15}'),
            re.compile(r'b00648d43061[0-9a-fA-F]{20}'),
            # Generic check for hardcoded API keys in client instantiation
            re.compile(r'LIDARR_API_KEY",\s*"[0-9a-zA-Z]{16,}'),
            re.compile(r'SLSKD_API_KEY",\s*"[0-9a-zA-Z]{16,}'),
            re.compile(r'JELLYFIN_TOKEN",\s*"[0-9a-zA-Z]{16,}'),
        ]

        violations = []
        for p in backend_dir.glob("**/*.py"):
            if "__pycache__" in p.parts:
                continue
            if p.name == "test_secrets.py":
                continue
            content = p.read_text(encoding="utf-8")
            for pat in suspicious_patterns:
                m = pat.search(content)
                if m:
                    violations.append(f"{p.name}:{m.start()} matched pattern {pat.pattern}")

        self.assertEqual(violations, [], f"Found hardcoded credentials: {violations}")

if __name__ == '__main__':
    unittest.main()
