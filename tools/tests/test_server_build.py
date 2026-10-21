from pathlib import Path
import json
import tempfile
import unittest
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from build_server import stage, package
from build_support import digest
from zipfile import ZipFile
from network_fingerprint import ROOTS, MANIFEST


class ServerBuildTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.game = self.root / 'game'
        for name in [*ROOTS, MANIFEST, 'server/duel_server.gd', 'server/duel_server.tscn', 'server/version.json', 'export_presets.cfg']:
            path = self.game / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('{}' if name.endswith('.json') else 'source\n')
        (self.game / 'server/version.json').write_text('{"version":"0.1.0"}\n')
        (self.game / ROOTS[-1]).write_text('preload("res://scripts/session/duel_host.gd")\n')
        (self.game / 'scripts/session/duel_host.gd').write_text('shared authority source\n')
        (self.game / 'export_presets.cfg').write_text('[preset.0]\nrunnable=true\nexport_filter="all_resources"\n')
        for name in ['assets/classic/sprite.png', 'assets/classic/sound.wav', '.godot/cache.bin']:
            path = self.game / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b'private artwork/audio/cache')

    def tearDown(self):
        self.temp.cleanup()

    def test_shared_code_and_compatibility_without_artwork_or_autoloads(self):
        destination = self.root / 'server'
        value, names = stage(destination, self.root)
        self.assertEqual((destination / 'scripts/session/duel_host.gd').read_bytes(),
                         (self.game / 'scripts/session/duel_host.gd').read_bytes())
        self.assertEqual(json.loads((destination / MANIFEST).read_text()), value)
        self.assertFalse((destination / 'assets').exists())
        self.assertFalse((destination / '.godot').exists())
        self.assertNotIn('[autoload]', (destination / 'project.godot').read_text())
        self.assertIn('dedicated_server=true', (destination / 'export_presets.cfg').read_text())
        self.assertTrue(all(Path(name).suffix in {'.gd', '.tres', '.json', '.tscn'} for name in names))

    def test_missing_shared_authority_stops_staging(self):
        (self.game / 'scripts/session/duel_host.gd').unlink()
        with self.assertRaises(FileNotFoundError):
            stage(self.root / 'server', self.root)

    def test_local_generated_tables_cannot_enter_a_server_stage(self):
        (self.game / ROOTS[0]).write_text('preload("res://content/generated/private.tres")')
        path = self.game / 'content/generated/private.tres'
        path.parent.mkdir(parents=True)
        path.write_text('source numbers')
        with self.assertRaises(ValueError):stage(self.root / 'server', self.root)


class ServerPackageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        output = self.root / 'outputs'
        output.mkdir()
        (self.root / 'tools').mkdir()
        (self.root / 'tools/build-config.json').write_text(json.dumps({
            'artifact_id': 'test', 'stem': 'Test', 'engine_version': '4.6.1',
            'platforms': {'Linux': {}, 'Windows': {}}}))
        (self.root / 'docs').mkdir()
        (self.root / 'docs/server-guide.md').write_text('One duel, two clients.')
        (self.root / 'LICENSE').write_text('Source licence')
        (self.root / 'THIRD_PARTY.md').write_text('Source attribution')
        for name in ['host-linux', 'host-windows.exe', 'host-windows.console.exe', 'client-linux',
                     'Moonstone-Server.sh', 'Moonstone-Server.cmd', 'notices/GODOT-LICENSE.txt', 'notices/GODOT-COPYRIGHT.txt']:
            path = output / name
            path.parent.mkdir(exist_ok=True)
            path.write_bytes(name.encode())
        def row(platform, name):
            return {'platform': platform, 'file': 'outputs/' + name, 'sha256': digest(output / name)}
        linux = row('Linux', 'host-linux')
        windows = row('Windows', 'host-windows.exe')
        windows['console_wrapper'] = row('Windows', 'host-windows.console.exe')
        (output / 'duel-server-build-manifest.json').write_text(json.dumps({'version': '0.1.0', 'tag': 'server-v0.1.0', 'compatibility': 'test-hash', 'builds': [linux, windows], 'notices': 'outputs/notices'}))
        (output / 'test-build-manifest.json').write_text(json.dumps({'builds': [row('Linux', 'client-linux')]}))
        version = self.root / 'game/server/version.json'
        version.parent.mkdir(parents=True)
        version.write_text('{"version":"0.1.0"}')
        self.acceptance = self.root / 'accepted.json'
        self.acceptance.write_text(json.dumps({'result': 'PASS', 'server_sha256': linux['sha256'],
                                             'client_sha256': digest(output / 'client-linux'), 'scope': 'same-machine UDP'}))

    def tearDown(self):
        self.temp.cleanup()

    def test_packages_include_console_wrapper_and_preserve_execution_limits(self):
        rows = package(self.acceptance, self.root)
        with ZipFile(self.root / rows[1]['file']) as archive:
            self.assertIn('host-windows.console.exe', archive.namelist())
            self.assertEqual(archive.read('SOURCE-LICENSE.txt'), b'Source licence')
            self.assertIn('ATTRIBUTION.txt', archive.namelist())
            self.assertEqual(json.loads(archive.read('verification.json'))['Windows'], 'NOT_RUN')
        with ZipFile(self.root / rows[0]['file']) as archive:
            self.assertEqual(archive.getinfo('host-linux').external_attr >> 16 & 0o777, 0o755)
            self.assertFalse(any(name.endswith(('.png', '.wav')) for name in archive.namelist()))

    def test_stale_windows_input_preserves_both_existing_packages(self):
        outputs = self.root / 'outputs'
        paths = [outputs / ('Moonstone-Duel-Server-' + platform + '.zip') for platform in ['Linux', 'Windows']]
        for path in paths:
            path.write_bytes(b'previous accepted package')
        (outputs / 'host-windows.console.exe').write_bytes(b'changed')
        with self.assertRaises(ValueError):
            package(self.acceptance, self.root)
        self.assertTrue(all(path.read_bytes() == b'previous accepted package' for path in paths))

    def test_changed_client_rejects_old_acceptance(self):
        (self.root / 'outputs/client-linux').write_bytes(b'new client')
        with self.assertRaises(ValueError):
            package(self.acceptance, self.root)
        self.assertFalse((self.root / 'outputs/Moonstone-Duel-Server-Linux.zip').exists())


    def protocol_acceptance(self):
        value = json.loads(self.acceptance.read_text())
        value.update({'kind': 'server-protocol-release', 'compatibility': 'test-hash', 'version': '0.1.0'})
        value.pop('client_sha256')
        self.acceptance.write_text(json.dumps(value))
        (self.root / 'outputs/test-build-manifest.json').unlink()
        (self.root / 'outputs/client-linux').unlink()

    def test_source_only_release_needs_no_client_assets_or_client_binary(self):
        self.protocol_acceptance()
        rows = package(self.acceptance, self.root, protocol_release=True)
        self.assertEqual({Path(row['file']).name for row in rows}, {'Moonstone-Duel-Server-0.1.0-Linux.zip', 'Moonstone-Duel-Server-0.1.0-Windows.zip'})
        from server_release import collect
        destination = collect(rows, self.root)
        self.assertEqual(len(list(destination.iterdir())), 6)
        self.assertNotIn('client-linux', (destination / 'SHA256SUMS').read_text())
        (destination / 'private.png').write_bytes(b'private')
        with self.assertRaises(ValueError):collect(rows, self.root)

    def test_source_only_acceptance_must_match_version_and_combat(self):
        self.protocol_acceptance()
        value = json.loads(self.acceptance.read_text())
        value['compatibility'] = 'another-combat-pack'
        self.acceptance.write_text(json.dumps(value))
        with self.assertRaises(ValueError):package(self.acceptance, self.root, protocol_release=True)
        self.assertFalse((self.root / 'outputs/Moonstone-Duel-Server-0.1.0-Linux.zip').exists())
