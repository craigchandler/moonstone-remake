"""Source-only contract: classic combat must never depend on local imports."""
from pathlib import Path
import sys
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from build_support import ROOT
from build_server import stage
from network_fingerprint import manifest
import tempfile


class GameplayPackTests(unittest.TestCase):
    def test_complete_server_closure_is_public_code_and_numeric_content(self):
        value = manifest(ROOT / 'game')
        self.assertIn('content/packs/classic/manifest.tres', value['files'])
        tables = [name for name in value['files'] if name.startswith('content/packs/classic/tables/')]
        self.assertEqual(len(tables), 16)
        self.assertFalse(any(name.startswith(('assets/', 'content/generated/')) for name in value['files']))
        from campaign_fingerprint import manifest as campaign_manifest
        campaign = campaign_manifest(ROOT / 'game')
        for name in ['classic_map_travel.tres', 'classic_loot.tres', 'moonstone_quest.tres', 'visit_clocks.json']:
            self.assertIn('content/packs/classic/campaign/' + name, campaign['files'])
        self.assertFalse(any(name.startswith(('assets/', 'content/generated/', 'scripts/presentation/')) for name in campaign['files']))
        with tempfile.TemporaryDirectory() as directory:
            _, names = stage(Path(directory))
            self.assertTrue(all((Path(directory) / name).is_file() for name in names))
            self.assertFalse((Path(directory) / 'assets').exists())
