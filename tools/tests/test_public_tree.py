"""Real-index publication regressions; no game assets or network required."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from check_public_tree import audit


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
        for name in ['README.md', 'LICENSE', 'docs/art-packs.md', 'game/tests/fixtures/trace.json', 'tools/import_example.py', 'game/assets/classic/.gitkeep']:
            self.stage(name)
        issues, count, _ = audit(self.root)
        self.assertEqual(issues, [])
        self.assertEqual(count, 6)

    def test_assets_notes_config_and_archives_are_rejected(self):
        for name in ['docs/source-notes.md', 'STATUS.md', '.codex/config.toml', 'reference/manifest.json', 'game/assets/modern/knight.png', 'game/content/generated/content.tres', 'outputs/build.zip', 'work/blog.md']:
            self.stage(name)
        issues, _, _ = audit(self.root)
        self.assertEqual(len(issues), 8)

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
