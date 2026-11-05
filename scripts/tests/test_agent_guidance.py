"""Regression checks for missing evidence and policy drift."""
import importlib.util
from pathlib import Path
import shutil
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'check_agent_guidance.py'
spec = importlib.util.spec_from_file_location('guidance', SCRIPT)
guidance = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guidance)


class GuidanceChecks(unittest.TestCase):
    def test_behavior_and_deployment_changes_need_evidence(self):
        for path in ('lib/screens/music_screen.dart', 'backend/catalog.py',
                     'macos/Runner/Info.plist', 'test/navigation_test.dart',
                     '.github/workflows/macos-release.yml'):
            with self.subTest(path=path):
                errors = guidance.check(changed=[path])
                self.assertTrue(any('changed task report' in e for e in errors))

    def test_deleted_report_and_template_do_not_satisfy_gate(self):
        errors = guidance.check(changed=['backend/catalog.py',
            'docs/verification/deleted.md', 'docs/verification/TEMPLATE.md'])
        self.assertTrue(any('changed task report' in e for e in errors))

    def test_docs_only_does_not_require_runtime_report(self):
        self.assertEqual(guidance.check(changed=['docs/PROJECT_BRIEF.md']), [])

    def test_new_menu_surface_cannot_silently_escape_the_inventory(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in guidance.DOCS:
                target = root / name
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(guidance.ROOT / name, target)
            new_menu = root / 'lib/menus/new_action_menu.dart'
            new_menu.parent.mkdir(parents=True, exist_ok=True)
            new_menu.write_text('// New user-facing menu')
            self.assertIn('Unmapped native workflow surface: lib/menus/new_action_menu.dart', guidance.check(root))

    def test_broken_link_and_adapter_drift_are_detected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in guidance.DOCS:
                target = root / name
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(guidance.ROOT / name, target)
            (root / 'VISION.md').unlink()
            (root / 'GEMINI.md').write_text('Independent policy with no canonical reference')
            errors = guidance.check(root)
            self.assertTrue(any('Broken local link' in e for e in errors))
            self.assertTrue(any('Adapter does not reference' in e for e in errors))


if __name__ == '__main__':
    unittest.main()
