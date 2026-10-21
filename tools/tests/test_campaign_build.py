"""Campaign compatibility binds source gameplay, never artwork or local imports."""
from pathlib import Path
import json
import sys
import tempfile
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from campaign_fingerprint import ROOTS, manifest
import test_server_build


class CampaignFingerprintTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.game = Path(self.temp.name)
        for name in ROOTS:
            path = self.game / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('source\n')

    def tearDown(self):self.temp.cleanup()

    def test_numeric_changes_require_matching_clients_but_art_does_not(self):
        path = self.game / 'content/packs/classic/campaign/travel.tres'
        path.parent.mkdir(parents=True);path.write_text('speed = 2\n')
        (self.game / ROOTS[0]).write_text('preload("res://content/packs/classic/campaign/travel.tres")')
        first = manifest(self.game)
        art = self.game / 'assets/local.png';art.parent.mkdir();art.write_bytes(b'local art')
        self.assertEqual(manifest(self.game), first)
        path.write_text('speed = 3\n')
        self.assertNotEqual(manifest(self.game)['digest'], first['digest'])

    def test_generated_candidates_and_path_traversal_cannot_become_server_inputs(self):
        for name in ['content/generated/private.tres', '../private.gd', 'assets/classic/art.tres']:
            (self.game / ROOTS[0]).write_text(f'preload("res://{name}")')
            with self.assertRaises(ValueError):manifest(self.game)


class CampaignPackageTests(unittest.TestCase):
    def setUp(self):
        self.fixture = test_server_build.ServerPackageTests()
        self.fixture.setUp()
        self.root, self.acceptance = self.fixture.root, self.fixture.acceptance

    def tearDown(self):self.fixture.tearDown()

    def test_campaign_export_cannot_reuse_duel_only_or_stale_campaign_acceptance(self):
        report_path = self.root / 'outputs/duel-server-build-manifest.json'
        report = json.loads(report_path.read_text());report['campaign_compatibility'] = 'current-campaign'
        report_path.write_text(json.dumps(report))
        from build_server import package
        with self.assertRaises(ValueError):package(self.acceptance, self.root)
        accepted = json.loads(self.acceptance.read_text())
        accepted.update(campaign_compatibility='old-campaign', campaign={'result': 'PASS'})
        self.acceptance.write_text(json.dumps(accepted))
        with self.assertRaises(ValueError):package(self.acceptance, self.root)
        accepted['campaign_compatibility'] = 'current-campaign'
        self.acceptance.write_text(json.dumps(accepted))
        self.assertEqual(len(package(self.acceptance, self.root)), 2)
