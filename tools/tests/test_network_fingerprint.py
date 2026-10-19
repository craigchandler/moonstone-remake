from pathlib import Path
import tempfile
import unittest
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from network_fingerprint import ROOTS, manifest


class NetworkFingerprintTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.game = Path(self.temp.name)
        for name in ROOTS:
            path = self.game / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('source\n')
        (self.game / ROOTS[0]).write_text('preload("res://rules.tres")\npreload("res://sprite.png")')
        (self.game / 'rules.tres').write_text('damage = 5\n')
        (self.game / 'sprite.png').write_bytes(b'pixels')

    def tearDown(self):
        self.temp.cleanup()

    def test_reproducible_dependency_closure(self):
        first = manifest(self.game)
        self.assertEqual(first, manifest(self.game))
        self.assertIn('rules.tres', first['files'])
        self.assertNotIn('sprite.png', first['files'])

    def test_gameplay_change_rejects_compatibility(self):
        first = manifest(self.game)
        (self.game / 'rules.tres').write_text('damage = 6\n')
        self.assertNotEqual(first['digest'], manifest(self.game)['digest'])

    def test_graphics_change_does_not_change_rules_fingerprint(self):
        first = manifest(self.game)
        (self.game / 'sprite.png').write_bytes(b'new artwork')
        self.assertEqual(first['digest'], manifest(self.game)['digest'])

    def test_missing_required_rules_fail_the_build(self):
        (self.game / 'rules.tres').unlink()
        with self.assertRaises(FileNotFoundError):
            manifest(self.game)
