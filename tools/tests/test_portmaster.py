"""Portable-pack integrity and launcher behavior without a handheld or mounts."""
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
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
                     'tools/portmaster-runtimes.json', 'tools/portmaster.gptk', 'docs/portmaster.md']:
            self.assertTrue(allowed_path(path), path)
        for path in ['outputs/portmaster/moonstone.zip', 'tools/godot_4.6.3.squashfs', 'game/assets/classic/moonstone.pck']:
            self.assertFalse(allowed_path(path), path)


class LauncherTests(unittest.TestCase):
    def run_launcher(self, fail_mount=False, missing_runtime=False, game_exit=0):
        with tempfile.TemporaryDirectory(prefix='moonstone-launch-') as tmp:
            root = Path(tmp)
            control = root / 'PortMaster'
            game = root / 'ports/moonstone'
            control.mkdir(); game.mkdir(parents=True)
            (control / 'libs').mkdir()
            (game / 'moonstone.pck').write_bytes(b'pack')
            (game / 'moonstone.gptk').write_bytes((TOOLS / 'portmaster.gptk').read_bytes())
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
DEVICE_ARCH=aarch64
CFW_NAME=muOS
ESUDO=""
GPTOKEYB="true"
get_controls() { sdl_controllerconfig=test_mapping; }
pm_message() { echo "$*"; }
pm_finish() { echo finish >> "$EVENTS"; }
mount() { echo "mount:$2" >> "$EVENTS"; [ "$FAIL_MOUNT" != 1 ] || [ "$2" != "$TEST_ROOT/godot" ]; }
umount() { echo "umount:$1" >> "$EVENTS"; }
''')
            # Substitute only hardware discovery/mount locations; exercise the real shell flow.
            script = (TOOLS / 'launch_portmaster.sh').read_text()
            script = script.replace('for candidate in /mnt/mmc/MUOS/PortMaster', 'for candidate in "$TEST_ROOT/PortMaster" /mnt/mmc/MUOS/PortMaster')
            script = script.replace('weston_dir=/tmp/weston', 'weston_dir="$TEST_ROOT/weston"')
            script = script.replace('godot_dir=/tmp/moonstone-godot', 'godot_dir="$TEST_ROOT/godot"')
            launcher = root / 'launch.sh'
            launcher.write_text(script)
            env = dict(os.environ, TEST_ROOT=str(root), EVENTS=str(events),
                       FAIL_MOUNT=str(int(fail_mount)), GAME_EXIT=str(game_exit))
            result = subprocess.run(['bash', launcher], env=env, capture_output=True, text=True, timeout=5)
            return result.returncode, events.read_text() if events.exists() else '', result.stdout

    def test_launch_and_cleanup_preserve_failure(self):
        code, events, output = self.run_launcher(game_exit=7)
        self.assertEqual(code, 7, output)
        self.assertIn('wrapper:headless noop kiosk crusty_x11egl bash ./moonstone-run.sh', events)
        self.assertIn('wrapper:cleanup', events)
        self.assertTrue(events.endswith('finish\n'), events)

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
        self.assertIn('offline runtime', output)


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

    def test_helper_keyboard_and_mouse_defaults_are_unassigned(self):
        values = dict(line.split(' = ', 1) for line in (TOOLS / 'portmaster.gptk').read_text().splitlines()
                      if line and not line.startswith('#'))
        controls = 'start guide back a b x y l1 l2 l3 r1 r2 r3 up down left right'.split()
        controls += [stick + '_analog_' + direction for stick in ('left', 'right') for direction in ('up', 'down', 'left', 'right')]
        controls += [key + '_hk' for key in 'a b x y l1 l2 r1 r2'.split()]
        self.assertEqual(values, dict.fromkeys(controls, '"'))


if __name__ == '__main__':
    unittest.main()
