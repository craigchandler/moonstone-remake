"""Portable-pack integrity and launcher behavior without a handheld or mounts."""
import hashlib
import io
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import tarfile
import tempfile
import unittest

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
from package_portmaster import extract_pack
from check_public_tree import allowed_path


def embedded(payload=b'project settings', name='project.binary', flags=2):
    path = name.encode()
    header = struct.pack('<4sIIIIIQQ', b'GDPC', 3, 4, 6, 1, flags, 104, 104 + len(payload))
    header += bytes(104 - len(header))
    directory = struct.pack('<II', 1, len(path)) + path
    directory += struct.pack('<QQ16sI', 0, len(payload), hashlib.md5(payload).digest(), 0)
    pack = header + payload + directory
    return b'ELF placeholder' + pack + struct.pack('<Q4s', len(pack), b'GDPC'), pack


class PackTests(unittest.TestCase):
    def test_exact_extraction(self):
        binary, expected = embedded()
        actual, info = extract_pack(binary)
        self.assertEqual(actual, expected)
        self.assertEqual(info['files'], 1)

    def test_bad_footer_and_length(self):
        binary, _ = embedded()
        for bad in [b'', binary[:-1], binary[:-12] + struct.pack('<Q4s', len(binary) + 100, b'GDPC')]:
            with self.assertRaises(ValueError):
                extract_pack(bad)

    def test_payload_corruption(self):
        binary, _ = embedded()
        with self.assertRaisesRegex(ValueError, 'checksum'):
            extract_pack(binary.replace(b'project settings', b'PROJECT settings'))

    def test_encrypted_or_sparse_pack_rejected(self):
        for flags in [0, 1, 3, 6]:
            with self.assertRaises(ValueError):
                extract_pack(embedded(flags=flags)[0])

    def test_native_extension_rejected(self):
        with self.assertRaisesRegex(ValueError, 'Native extension'):
            extract_pack(embedded(name='addons/native.so')[0])

    def test_path_escape_rejected(self):
        with self.assertRaises(ValueError):
            extract_pack(embedded(name='../project.binary')[0])

    def test_missing_project_rejected(self):
        with self.assertRaisesRegex(ValueError, 'project.binary'):
            extract_pack(embedded(name='other.txt')[0])

    def test_source_allowlist_keeps_bundles_private(self):
        for path in ['tools/package_portmaster.py', 'tools/launch_portmaster.sh', 'tools/run_portmaster.sh',
                     'tools/portmaster-runtimes.json', 'docs/portmaster.md']:
            self.assertTrue(allowed_path(path), path)
        for path in ['outputs/portmaster/moonstone.zip', 'tools/godot_4.6.3.squashfs', 'game/assets/classic/moonstone.pck']:
            self.assertFalse(allowed_path(path), path)


class LauncherTests(unittest.TestCase):
    def run_launcher(self, fail_mount=False, missing_runtime=False, game_exit=0, adjacent=False,
                     missing_mapper=False, arch='aarch64', download=None):
        with tempfile.TemporaryDirectory(prefix='moonstone launch ') as tmp:
            root = Path(tmp)
            control = root / 'PortMaster'
            game = root / ('moonstone' if adjacent else 'ports/moonstone')
            control.mkdir(); game.mkdir(parents=True)
            (control / 'libs').mkdir()
            (game / 'moonstone.pck').write_bytes(b'pack')
            (game / ('moonstone-run' if adjacent else 'moonstone-run.sh')).write_text('#!/bin/bash\n')
            (game / 'mapper').write_text('#!/bin/bash\nprintf "mapper:%s\\n" "$*" >> "$EVENTS"\n')
            for name in ['godot_4.6.3', 'weston_pkg_0.2']:
                if not missing_runtime:
                    (control / 'libs' / (name + '.squashfs')).write_bytes(b'runtime')
            events = root / 'events'
            weston = root / 'weston'
            godot = root / 'godot'
            weston.mkdir(); godot.mkdir()
            wrapper = weston / 'westonwrap.sh'
            wrapper.write_text('#!/bin/bash\necho "wrapper:$*" >> "$EVENTS"\nif [ "$1" = cleanup ]; then exit 0; fi\nexit "$GAME_EXIT"\n')
            wrapper.chmod(0o755)
            engine = godot / 'godot463.aarch64'
            engine.write_text('#!/bin/bash\nexit 0\n');engine.chmod(0o755)
            (control / 'control.txt').write_text('''
directory="${TEST_ROOT#/}"
DEVICE_ARCH=$TEST_ARCH
CFW_NAME=muOS
ESUDO=""
GPTOKEYB2=$TEST_MAPPER
get_controls() { sdl_controllerconfig=test_mapping; }
pm_message() { echo "$*"; }
pm_show_error() { echo "$*"; }
pm_finish() { echo finish >> "$EVENTS"; }
pm_platform_helper() { for attempt in {1..100}; do grep -q "^mapper:" "$EVENTS" && break; sleep .01; done; echo "platform:$1" >> "$EVENTS"; }
mount() { echo "mount:$2" >> "$EVENTS"; [ "$FAIL_MOUNT" != 1 ] || [ "$2" != "$TEST_ROOT/godot" ]; }
umount() { echo "umount:$1" >> "$EVENTS"; }
''')
            if download is not None:
                helper = control / 'harbourmaster'
                helper.write_text('''#!/bin/bash
echo "download:$*" >> "$EVENTS"
[ "$TEST_DOWNLOAD" = success ] || exit 1
printf runtime > "$TEST_ROOT/PortMaster/libs/${@: -1}"
''')
                helper.chmod(0o755)
            # Substitute only hardware discovery/mount locations; exercise the real shell flow.
            script = (TOOLS / 'launch_portmaster.sh').read_text()
            script = script.replace('if [ -d "/opt/system/Tools/PortMaster/" ]; then', 'if [ -d "$TEST_ROOT/PortMaster" ]; then\n    controlfolder="$TEST_ROOT/PortMaster"\nelif [ -d "/opt/system/Tools/PortMaster/" ]; then')
            script = script.replace('weston_dir=/tmp/weston', 'weston_dir="$TEST_ROOT/weston"')
            script = script.replace('godot_dir=/tmp/moonstone-godot', 'godot_dir="$TEST_ROOT/godot"')
            launcher = root / 'launch.sh'
            launcher.write_text(script)
            env = dict(os.environ, TEST_ROOT=str(root), EVENTS=str(events),
                       FAIL_MOUNT=str(int(fail_mount)), GAME_EXIT=str(game_exit),
                       TEST_ARCH=arch, TEST_MAPPER='' if missing_mapper else 'bash mapper',
                       TEST_DOWNLOAD=download or '')
            result = subprocess.run(['bash', launcher], env=env, capture_output=True, text=True, timeout=5)
            return result.returncode, events.read_text() if events.exists() else '', result.stdout

    def test_launch_and_cleanup_preserve_failure(self):
        code, events, output = self.run_launcher(game_exit=7)
        self.assertEqual(code, 7, output)
        self.assertIn('wrapper:headless noop kiosk crusty_x11egl bash ./moonstone-run.sh', events)
        self.assertIn('wrapper:cleanup', events)
        self.assertIn('platform:', events)
        self.assertIn('mapper:godot463.aarch64\n', events)
        self.assertNotIn('-c ', events)
        self.assertLess(events.index('platform:'),events.index('wrapper:headless'))
        self.assertTrue(events.endswith('finish\n'), events)

    def test_standard_adjacent_folder_layout(self):
        code, events, output = self.run_launcher(adjacent=True)
        self.assertEqual(code,0,output)
        self.assertIn('wrapper:headless noop kiosk crusty_x11egl bash ./moonstone-run\n',events)

    def test_partial_mount_failure_cleans_up(self):
        code, events, _ = self.run_launcher(fail_mount=True)
        self.assertNotEqual(code, 0)
        self.assertNotIn('wrapper:', events)
        self.assertTrue(events.endswith('finish\n'), events)
        self.assertEqual(sum(line.startswith('umount:') and line.endswith('/weston') for line in events.splitlines()), 2)

    def test_missing_runtime_does_not_start_game(self):
        code, events, output = self.run_launcher(missing_runtime=True)
        self.assertNotEqual(code, 0, output)
        self.assertNotIn('wrapper:', events)
        self.assertIn('Runtime Manager', output)
        self.assertTrue(events.endswith('finish\n'), events)

    def test_missing_gptokeyb2_does_not_start_game(self):
        code, events, output = self.run_launcher(missing_mapper=True)
        self.assertNotEqual(code, 0, output)
        self.assertNotIn('wrapper:', events)
        self.assertIn('gptokeyb2', output)
        self.assertTrue(events.endswith('finish\n'), events)

    def test_non_arm_importer_is_rejected_before_mount(self):
        code, events, output = self.run_launcher(arch='x86_64')
        self.assertNotEqual(code, 0, output)
        self.assertNotIn('mount:', events)
        self.assertIn('requires 64-bit ARM', output)

    def test_runtime_download_success_and_failure(self):
        for download in ['success', 'failure']:
            with self.subTest(download=download):
                code, events, output = self.run_launcher(missing_runtime=True, download=download)
                self.assertIn('download:--quiet --no-check runtime_check weston_pkg_0.2.squashfs', events)
                self.assertTrue(events.endswith('finish\n'), events)
                if download == 'success':
                    self.assertEqual(code, 0, output)
                    self.assertIn('wrapper:headless', events)
                else:
                    self.assertNotEqual(code, 0, output)
                    self.assertIn('Runtime unavailable', output)
                    self.assertNotIn('mount:', events)


class ImporterUnpackTests(unittest.TestCase):
    def test_unpack_keeps_local_ownership_and_rejects_bad_checksum(self):
        for corrupt in [False, True]:
            with self.subTest(corrupt=corrupt), tempfile.TemporaryDirectory(prefix='moonstone unpack ') as tmp:
                root = Path(tmp)
                (root / 'cache').mkdir()
                (root / 'importer.pck').write_bytes(b'setup fixture')
                (root / 'conf').mkdir()
                (root / 'conf/save').write_bytes(b'keep save')
                (root / 'content').mkdir()
                (root / 'content/current.json').write_bytes(b'keep content')
                archive = root / 'importer.tar'
                with tarfile.open(archive, 'w', format=tarfile.USTAR_FORMAT) as bundle:
                    files = {'manifest.json': b'{}',
                             'python/bin/python3.14': b'#!/bin/bash\nprintf prepared > "$MOONSTONE_GAME_DIR/worker-started"\n',
                             **{f'bin/{name}': b'fixture' for name in ['bake-audio', 'bake-menu', 'bake-module']}}
                    for name, data in files.items():
                        entry = tarfile.TarInfo(name)
                        entry.size = len(data)
                        entry.uid = entry.gid = 4242
                        bundle.addfile(entry, io.BytesIO(data))
                sha = hashlib.sha256(archive.read_bytes()).hexdigest()
                (root / 'importer.sha256').write_text(sha + '  importer.tar\n')
                if corrupt:
                    archive.write_bytes(b'corrupt archive')
                result = subprocess.run(['bash', TOOLS / 'run_portmaster.sh', '--prepare-content'],
                                        cwd=root, capture_output=True, text=True, timeout=5)
                self.assertEqual((root / 'conf/save').read_bytes(), b'keep save')
                self.assertEqual((root / 'content/current.json').read_bytes(), b'keep content')
                if corrupt:
                    self.assertNotEqual(result.returncode, 0)
                    self.assertFalse((root / 'worker-started').exists())
                    self.assertEqual(json.loads((root / 'import-status.json').read_text())['state'], 'failed')
                else:
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertEqual((root / 'worker-started').read_text(), 'prepared')
                    extracted = root / 'cache' / ('importer-' + sha) / 'manifest.json'
                    self.assertEqual(extracted.stat().st_uid, os.getuid())


class NativeInputTests(unittest.TestCase):
    def run_helper(self, mapping):
        with tempfile.TemporaryDirectory(prefix='moonstone input ') as tmp:
            root = Path(tmp)
            (root / 'cache').mkdir()
            (root / 'cache/controller-mapping.txt').write_text(mapping + '\n')
            engine = root / 'engine.py'
            engine.write_text('#!/usr/bin/env python3\nimport os, json, sys\nprint("CAPTURE=" + json.dumps({"mapping": os.environ["SDL_GAMECONTROLLERCONFIG"], "args": sys.argv[1:]}))\n')
            engine.chmod(0o755)
            script = (TOOLS / 'run_portmaster.sh').read_text().replace(
                '/tmp/moonstone-godot/godot463.aarch64', str(engine))
            helper = root / 'run.sh'
            helper.write_text(script)
            result = subprocess.run(['bash', helper], cwd=root, text=True, capture_output=True,
                                    env=dict(os.environ, SDL_GAMECONTROLLERCONFIG='stale Weston environment'), timeout=5)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse((root / 'UNEXPECTED').exists())
            return json.loads(next(line[8:] for line in result.stdout.splitlines() if line.startswith('CAPTURE=')))

    def test_muos_sdl3_raw_buttons_match_printed_letters(self):
        result = self.run_helper('19000000010000000100000000010000,Deeplay-keys,a:b3,b:b4,x:b6,y:b5,platform:Linux,')
        guid, name, *entries = result['mapping'].rstrip(',').split(',')
        self.assertEqual(guid, '19004ca6010000000100000000010000')
        self.assertEqual(name, 'RG40XX H')
        actual = dict(entry.split(':', 1) for entry in entries)
        # Raw udev indices from MustardOS's Deeplay-keys RetroArch profile.
        expected = {'a':'b0', 'b':'b1', 'x':'b3', 'y':'b2', 'leftshoulder':'b4',
                    'rightshoulder':'b5', 'back':'b6', 'start':'b7', 'guide':'b8',
                    'leftstick':'b9', 'lefttrigger':'b10', 'righttrigger':'b11', 'rightstick':'b12',
                    'dpup':'h0.1', 'dpright':'h0.2', 'dpdown':'h0.4', 'dpleft':'h0.8',
                    'leftx':'a0', 'lefty':'a1', 'rightx':'a2', 'righty':'a3', 'platform':'Linux'}
        self.assertEqual(actual, expected)
        self.assertEqual(result['args'][-2], '--main-pack')
        self.assertTrue(result['args'][-1].endswith('/moonstone.pck'))

    def test_other_controller_mapping_survives_weston_and_is_not_evaluated(self):
        mapping = 'other-guid,Pad $(touch UNEXPECTED) `touch UNEXPECTED`,a:b0,b:b1,platform:Linux,'
        self.assertEqual(self.run_helper(mapping)['mapping'], mapping)

if __name__ == '__main__':
    unittest.main()
