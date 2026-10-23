"""Installer/build integration without a preconfigured developer environment."""
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
from zipfile import ZipFile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from build_support import godot_binary, stage_templates
import install_server_toolchain


class ToolchainDiscoveryTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.settings = {'engine_version': '4.6.1'}
        self.editor_name = 'Godot_v4.6.1-stable_linux.x86_64'
        self.directory = self.root / 'work/server-toolchain'
        self.directory.mkdir(parents=True)
        archives = {}
        for name, members in {
            'editor.zip': {self.editor_name: b'editor fixture'},
            'templates.tpz': {'templates/' + file: data for file, data in {
                'linux_release.x86_64': b'linux', 'windows_release_x86_64.exe': b'windows',
                'windows_release_x86_64_console.exe': b'console', 'version.txt': b'4.6.1.stable',
            }.items()},
        }.items():
            archive = self.directory / name
            with ZipFile(archive, 'w') as out:
                for member, data in members.items():out.writestr(member, data)
            archives[name] = hashlib.sha512(archive.read_bytes()).hexdigest()
        (self.root / 'tools').mkdir()
        (self.root / 'tools/server-toolchain.json').write_text(json.dumps({
            'version': '4.6.1', 'base_url': 'https://example.invalid/', 'archives': archives,
        }))
        self.env = {'GITHUB_ENV': str(self.root / 'github.env'), 'PATH': ''}

    def install(self):
        with patch.object(install_server_toolchain, 'ROOT', self.root), \
                patch.object(install_server_toolchain, 'config', return_value=self.settings), \
                patch.object(install_server_toolchain.platform, 'system', return_value='Linux'), \
                patch.object(install_server_toolchain.platform, 'machine', return_value='x86_64'), \
                patch.object(install_server_toolchain.urllib.request, 'urlopen', side_effect=AssertionError('Unexpected network')):
            install_server_toolchain.main()

    def test_installer_output_works_before_github_environment_is_applied(self):
        with patch.dict(os.environ, self.env, clear=True):
            self.install()
            self.assertNotIn('GODOT_BIN', os.environ)
            self.assertNotIn('GODOT_TEMPLATES_DIR', os.environ)
            self.assertIn('GODOT_BIN=', (self.root / 'github.env').read_text())
            with patch('build_support.subprocess.check_output', return_value='4.6.1.stable.fixture\n') as execute:
                binary, _ = godot_binary(self.settings, self.root)
                self.assertEqual(binary, self.directory / self.editor_name)
                execute.assert_called_once_with([str(binary), '--version'], text=True)
            destination = self.root / 'build-data'
            selected = stage_templates(self.settings, {'XDG_DATA_HOME': str(destination)}, self.root)
            self.assertEqual(selected, str(self.directory / 'templates'))
            for name in ['linux_release.x86_64', 'windows_release_x86_64.exe', 'windows_release_x86_64_console.exe']:
                self.assertEqual((destination / 'godot/export_templates/4.6.1.stable' / name).read_bytes(),
                                 (self.directory / 'templates' / name).read_bytes())

    def test_bad_explicit_overrides_are_not_silently_replaced(self):
        with patch.dict(os.environ, self.env, clear=True):
            self.install()
            with patch.dict(os.environ, GODOT_BIN=str(self.root / 'missing-editor')):
                with self.assertRaisesRegex(RuntimeError, 'GODOT_BIN'):godot_binary(self.settings, self.root)
            with patch.dict(os.environ, GODOT_TEMPLATES_DIR=str(self.root / 'missing-templates')):
                with self.assertRaisesRegex(RuntimeError, 'templates'):
                    stage_templates(self.settings, {'XDG_DATA_HOME': str(self.root / 'data')}, self.root)

    def test_old_installed_editor_and_templates_cannot_satisfy_new_version(self):
        with patch.dict(os.environ, self.env, clear=True), patch('build_support.Path.home', return_value=self.root / 'user'):
            self.install()
            with patch('build_support.subprocess.check_output', return_value='4.5.0.stable.fixture\n'):
                with self.assertRaisesRegex(RuntimeError, 'Expected Godot 4.6.1'):godot_binary(self.settings, self.root)
            (self.directory / 'templates/version.txt').write_text('4.5.0.stable')
            with self.assertRaisesRegex(RuntimeError, 'templates'):
                stage_templates(self.settings, {'XDG_DATA_HOME': str(self.root / 'data')}, self.root)
