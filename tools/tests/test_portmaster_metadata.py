import json
from pathlib import Path
import sys
import tempfile
import unittest
from zipfile import ZipFile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from build_support import ROOT
from package_builds import add_file
from portmaster_metadata import metadata_files, validate_archive
import test_public_tree


class PortMasterPackageTests(unittest.TestCase):
    def members(self):
        members = {'moonstone/' + name: data for name, data in metadata_files(ROOT).items()}
        members['Moonstone.sh'] = b'#!/bin/bash\nexit 0\n'
        for name in ['moonstone.pck', 'importer.pck', 'importer.tar', 'importer.sha256', 'moonstone-run']:
            members['moonstone/' + name] = b'synthetic package fixture'
        members['moonstone/muos-thumbnail.png'] = test_public_tree.PublicTreeTests.screenshot(320, 200)
        return members

    def check(self, members):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'test.zip'
            with ZipFile(path, 'w') as archive:
                for name, data in members.items():
                    add_file(archive, name, data, 0o755 if name == 'Moonstone.sh' else 0o644)
            return validate_archive(path)

    def test_installed_metadata_resolves_actual_files_and_requires_original_data(self):
        members = self.members()
        result = self.check(members)
        self.assertEqual(result['result'], 'PASS')
        self.assertEqual(result['hardware_execution'], 'NOT_RUN')
        info = json.loads(members['moonstone/port.json'])
        self.assertFalse(info['attr']['rtr'])
        self.assertTrue(info['attr']['exp'])
        self.assertEqual(info['attr']['porter'], ['Craig Chandler'])
        self.assertNotIn('conf', info['items'])

    def test_old_sd_root_layout_and_bundled_player_content_are_rejected(self):
        members = self.members()
        old = {'roms/PORTS/Moonstone.sh': members.pop('Moonstone.sh')}
        old.update({'ports/' + name: data for name, data in members.items()})
        with self.assertRaisesRegex(ValueError, 'archive path'):
            self.check(old)
        for name in ['moonstone/content/current.json', 'moonstone/disks/game.ipf',
                     'moonstone/conf/save.json', '../Moonstone.sh']:
            with self.subTest(name=name), self.assertRaises(ValueError):
                self.check(self.members() | {name: b'not distributable'})

    def test_xml_references_and_catalogue_image_dimensions_cannot_drift(self):
        for name, replacement in [
            ('moonstone/gameinfo.xml', self.members()['moonstone/gameinfo.xml'].replace(b'./Moonstone.sh', b'./Other.sh')),
            ('moonstone/screenshot.png', test_public_tree.PublicTreeTests.screenshot()),
            ('moonstone/muos-thumbnail.png', test_public_tree.PublicTreeTests.screenshot(640, 480)),
        ]:
            with self.subTest(name=name), self.assertRaises(ValueError):
                self.check(self.members() | {name: replacement})

    def test_missing_or_misleading_requirements_are_rejected(self):
        members = self.members()
        for attr, value in [('rtr', True), ('arch', []), ('runtime', []), ('min_glibc', ''), ('porter', ['wrong name'])]:
            info = json.loads(members['moonstone/port.json'])
            info['attr'][attr] = value
            with self.subTest(attr=attr), self.assertRaisesRegex(ValueError, 'requirements'):
                self.check(members | {'moonstone/port.json': json.dumps(info).encode()})
        del members['moonstone/gameinfo.xml']
        with self.assertRaisesRegex(ValueError, 'Missing PortMaster'):
            self.check(members)
