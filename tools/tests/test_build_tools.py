"""Contracts for reproducible packaging without private historical workspaces."""
from pathlib import Path
from zipfile import ZipFile
import json
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from build_support import ROOT, artifact_path, config, digest
from package_builds import package_current


class PackagingTests(unittest.TestCase):
    def setUp(self):
        (ROOT / 'work').mkdir(exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(prefix='package-test-', dir=ROOT / 'work')
        self.root = Path(self.temporary.name)
        for folder in ['tools', 'outputs/notices', 'docs', 'work']:
            (self.root / folder).mkdir(parents=True)
        for name in ['build-config.json', 'launch_moonstone.sh', 'launch_moonstone.cmd']:
            shutil.copy2(ROOT / 'tools' / name, self.root / 'tools' / name)
        settings = config(self.root)
        (self.root / settings['guide']).write_text('Current player instructions\n')
        (self.root / 'docs/asset-policy.md').write_text('Personal assets stay local\n')
        for name in ['GODOT-LICENSE.txt', 'GODOT-COPYRIGHT.txt']:
            (self.root / 'outputs/notices' / name).write_text('Current matching engine notice\n')
        self.settings = settings
        self.builds = []
        for platform, target in settings['platforms'].items():
            path = self.root / 'outputs' / (settings['stem'] + '-' + target['suffix'])
            path.write_bytes(b'current fixture executable\x00' + platform.encode())
            self.builds.append({'platform': platform, 'file': str(path.relative_to(self.root)), 'sha256': digest(path)})
        self.manifest = self.root / 'outputs' / (settings['artifact_id'] + '-build-manifest.json')
        self.manifest.write_text(json.dumps({'stem': settings['stem'], 'builds': self.builds, 'notices': 'outputs/notices'}))
        self.verification = self.root / 'outputs' / (settings['artifact_id'] + '-verification.json')
        self.verification.write_text(json.dumps({'result': 'PASS', 'build_manifest_sha256': digest(self.manifest)}))

    def tearDown(self):
        self.temporary.cleanup()

    def test_clean_package_has_only_current_inputs_and_platform_launchers(self):
        result = package_current(self.root)
        self.assertEqual(len(result['packages']), 2)
        for row in result['packages']:
            with ZipFile(self.root / 'outputs' / row['archive']) as archive:
                self.assertIsNone(archive.testzip())
                self.assertEqual(len(archive.namelist()), 9)
                self.assertFalse(any(n.endswith('.mp4') for n in archive.namelist()))
                target = self.settings['platforms'][row['platform']]
                launch = archive.read(target['launcher'])
                self.assertIn(self.settings['stem'].encode(), launch)
                self.assertNotIn(b'@BINARY@', launch)
                if row['platform'] == 'Linux':
                    self.assertTrue((archive.getinfo(target['launcher']).external_attr >> 16) & 0o111)
                else:
                    self.assertIn(b'\r\n', launch)
                    self.assertNotIn(b'\\r\\n', launch)

    def test_packages_are_reproducible_when_input_mtimes_change(self):
        first = package_current(self.root)
        import os
        for build in self.builds:
            os.utime(self.root / build['file'], (123456, 123456))
        self.assertEqual(first, package_current(self.root))

    def test_stale_binary_fails_before_any_archive_is_replaced(self):
        first = package_current(self.root)
        protected = {p['archive']: digest(self.root / 'outputs' / p['archive']) for p in first['packages']}
        (self.root / self.builds[1]['file']).write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'Stale executable'):
            package_current(self.root)
        self.assertEqual(protected, {n: digest(self.root / 'outputs' / n) for n in protected})

    def test_report_from_another_build_is_rejected(self):
        self.verification.write_text(json.dumps({'result': 'PASS', 'build_manifest_sha256': 'wrong'}))
        with self.assertRaisesRegex(ValueError, 'matching build'):
            package_current(self.root)
        self.assertEqual(list((self.root / 'outputs').glob('*.zip')), [])

    def test_failed_acceptance_is_rejected(self):
        self.verification.write_text(json.dumps({'result': 'FAIL', 'build_manifest_sha256': digest(self.manifest)}))
        with self.assertRaises(ValueError):
            package_current(self.root)

    def test_artifact_paths_cannot_escape_the_outputs_folder(self):
        with self.assertRaises(ValueError):
            artifact_path(self.root, 'tools/build-config.json')
        link = self.root / 'outputs/leaked.txt'
        link.symlink_to(self.root / 'tools/build-config.json')
        with self.assertRaises(ValueError):
            artifact_path(self.root, 'outputs/leaked.txt')

    def test_missing_notice_fails_before_packages_are_written(self):
        (self.root / 'outputs/notices/GODOT-COPYRIGHT.txt').unlink()
        with self.assertRaises(ValueError):
            package_current(self.root)
        self.assertEqual(list((self.root / 'outputs').glob('*.zip')), [])


if __name__ == '__main__':
    unittest.main()
