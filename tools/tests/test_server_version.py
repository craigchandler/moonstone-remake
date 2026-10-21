from pathlib import Path
import json
import sys
import tempfile
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from server_version import server_version, validate_version, validate_tag
from network_fingerprint import ROOTS, manifest


class ServerVersionTests(unittest.TestCase):
    def test_stable_and_prerelease_versions(self):
        for value in ['0.1.0', '1.2.3', '1.2.3-rc.1']:
            self.assertEqual(validate_version(value), value)
        for value in ['1.2', '01.2.3', '1.2.3-rc.01', '1.2.3/../file', '1.2.3;echo', 123]:
            with self.assertRaises(ValueError):validate_version(value)

    def test_server_tags_do_not_accept_game_tags_or_mismatched_versions(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);path=root/'game/server/version.json';path.parent.mkdir(parents=True)
            path.write_text(json.dumps({'version':'0.1.0'}))
            self.assertEqual(validate_tag('server-v0.1.0',root),'server-v0.1.0')
            for tag in ['v0.1.0','game-v0.1.0','server-v0.2.0']:
                with self.assertRaises(ValueError):validate_tag(tag,root)

    def test_server_version_bump_does_not_change_combat_compatibility(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);game=root/'game'
            for name in ROOTS:
                path=game/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_text('source\n')
            path=game/'server/version.json';path.parent.mkdir();path.write_text('{"version":"0.1.0"}')
            first=manifest(game)
            path.write_text('{"version":"0.2.0"}')
            self.assertEqual(server_version(root),'0.2.0')
            self.assertEqual(manifest(game),first)
