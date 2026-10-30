"""Release guards: offline history and installed integration byte identity."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('packaging', ROOT / 'scripts/package-agent-skills.py')
packaging = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packaging)

class ReleasePayloadTests(unittest.TestCase):
    def test_offline_payload_contains_history_skills_and_install_entry(self):
        release = (ROOT / 'REL_VERSION').read_text().strip()
        payload = packaging.public_payload(ROOT, release, 'unversioned')
        for path in ('AGENT_INSTALL.md', 'docs/releases/v0.2.0-preview.1.md',
                     'skills/devflow-record/SKILL.md', 'skills/devflow-resolve/SKILL.md'):
            self.assertIn(path, payload)
        packaging.check_links(payload)

    def test_offline_link_to_missing_history_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'Broken offline link'):
            packaging.check_links({'docs/CHANGELOG.md': b'[Previous](releases/missing.md)'})

    def test_staged_payload_rejects_missing_modified_and_extra_files(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp).resolve()
            payload = {'guide.md': b'original'}
            target = root / 'guide.md'
            with self.assertRaises(ValueError):
                packaging.verify_staged_files(root, payload)
            target.write_bytes(b'original')
            packaging.verify_staged_files(root, payload)
            target.write_bytes(b'changed')
            with self.assertRaises(ValueError):
                packaging.verify_staged_files(root, payload)
            target.write_bytes(b'original')
            (root / 'private.txt').write_text('synthetic unexpected content')
            with self.assertRaises(ValueError):
                packaging.verify_staged_files(root, payload)

    def test_staged_payload_rejects_symlink_even_to_expected_bytes(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp).resolve()
            (root / 'original').write_bytes(b'original')
            (root / 'guide.md').symlink_to(root / 'original')
            with self.assertRaisesRegex(ValueError, 'Symbolic links'):
                packaging.verify_staged_files(root, {'guide.md': b'original', 'original': b'original'})
