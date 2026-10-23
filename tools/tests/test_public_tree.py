"""Real-index publication regressions; no game assets or network required."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import struct
import zlib

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from check_public_tree import audit, PUBLIC_SCREENSHOTS


class PublicTreeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.git('init', '-q')
        self.git('config', 'user.name', 'Test Author')
        self.git('config', 'user.email', 'test@example.invalid')

    def tearDown(self):
        self.temp.cleanup()

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.root), *args], stderr=subprocess.PIPE)

    def stage(self, name, content=b'source\n'):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
        self.git('add', '--', name)

    def test_source_and_numeric_fixtures_are_allowed(self):
        for name in ['README.md', 'LICENSE', 'docs/art-packs.md', 'game/tests/fixtures/trace.json', 'tools/import_example.py', 'game/assets/classic/.gitkeep', '.github/workflows/server-release.yml', 'docs/gameplay-packs.md']:
            self.stage(name)
        issues, count, _ = audit(self.root)
        self.assertEqual(issues, [])
        self.assertEqual(count, 8)

    def test_assets_notes_config_and_archives_are_rejected(self):
        for name in ['docs/source-notes.md', 'STATUS.md', '.codex/config.toml', 'reference/manifest.json', 'game/assets/modern/knight.png', 'game/content/generated/content.tres', 'outputs/build.zip', 'work/blog.md']:
            self.stage(name)
        issues, _, _ = audit(self.root)
        self.assertEqual(len(issues), 8)

    @staticmethod
    def screenshot(width=640, height=400):
        def chunk(kind, payload):
            return struct.pack('>I', len(payload)) + kind + payload + struct.pack('>I', zlib.crc32(kind + payload))
        pixels = (b'\0' + b'\x40\x60\x80' * width) * height
        return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)) +
                chunk(b'IDAT', zlib.compress(pixels)) + chunk(b'IEND', b''))

    def test_only_named_documentation_screenshots_are_allowed(self):
        self.stage('docs/screenshots.md')
        for name in PUBLIC_SCREENSHOTS:
            size = (320, 200) if name.endswith('/portmaster-thumbnail.png') else (640, 480 if name.endswith('/portmaster.png') else 400)
            self.stage(name, self.screenshot(*size))
        self.assertEqual(audit(self.root)[0], [])
        self.stage('docs/screenshots/sprite-atlas.png', self.screenshot())
        issues, _, _ = audit(self.root)
        self.assertTrue(any('sprite-atlas.png' in issue for issue in issues))

    def test_screenshot_exception_rejects_wrong_format_size_and_truncation(self):
        for content in [b'not an image', self.screenshot(320, 200), self.screenshot()[:-1]]:
            self.stage('docs/screenshots/intro.png', content)
            self.assertTrue(any('PNG screenshot' in issue for issue in audit(self.root)[0]))
        self.stage('docs/screenshots/portmaster.png', self.screenshot())
        self.assertTrue(any('640x480 PNG' in issue for issue in audit(self.root)[0]))
        self.stage('docs/screenshots/portmaster-thumbnail.png', self.screenshot())
        self.assertTrue(any('320x200 PNG' in issue for issue in audit(self.root)[0]))

    def test_screenshot_exception_preserves_staged_content_and_credential_checks(self):
        name = 'docs/screenshots/intro.png'
        self.stage(name, b'not a PNG')
        (self.root / name).write_bytes(self.screenshot())
        self.assertTrue(any('PNG screenshot' in issue for issue in audit(self.root)[0]))
        self.stage('docs/screenshots/notes.txt', ('ghp_' + 'a' * 36).encode())
        self.assertTrue(any('credential' in issue for issue in audit(self.root)[0]))

    def test_unstaged_cleanup_cannot_hide_a_staged_credential(self):
        name = 'game/config.txt'
        self.stage(name, ('ghp_' + 'a' * 36).encode())
        (self.root / name).write_text('clean working copy\n')
        issues, _, _ = audit(self.root)
        self.assertTrue(any('credential' in issue for issue in issues))
        self.assertFalse(any('a' * 36 in issue for issue in issues))

    def test_deleted_working_file_is_still_checked(self):
        self.stage('source.txt', b'a\x00binary')
        (self.root / 'source.txt').unlink()
        self.assertTrue(any('binary' in issue for issue in audit(self.root)[0]))

    def test_game_home_location_is_not_a_machine_path(self):
        self.stage('game/hints.gd', b'print("towns/home/tower/lair")\n')
        self.assertEqual(audit(self.root)[0], [])

    def test_old_private_content_is_found_even_after_deletion(self):
        self.stage('docs/brief.md')
        self.git('commit', '-qm', 'private history fixture')
        self.git('rm', '-q', 'docs/brief.md')
        self.stage('README.md')
        self.git('commit', '-qm', 'clean latest tree')
        self.assertEqual(audit(self.root, 'HEAD')[0], [])
        self.assertTrue(any('brief.md' in issue for issue in audit(self.root, 'HEAD', True)[0]))

    def test_symlinks_and_machine_paths_are_rejected(self):
        self.stage('path.txt', ('/' + 'home/' + 'someone/project/').encode())
        (self.root / 'linked.txt').symlink_to('path.txt')
        self.git('add', 'linked.txt')
        issues, _, _ = audit(self.root)
        self.assertTrue(any('symlink' in issue for issue in issues))
        self.assertTrue(any('home path' in issue for issue in issues))


if __name__ == '__main__':
    unittest.main()
