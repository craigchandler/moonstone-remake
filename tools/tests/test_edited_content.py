"""Explicit edited-content acceptance preserves integrity and existing installations."""
from pathlib import Path
import contextlib
import hashlib
import importlib.util
import io
import json
import os
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from portmaster_content import write_pack
from portmaster_import import installed_content, ImportCancelled
from import_transfer import install_pack, install_content, export_content, checked_source
from test_release import fixture


class EditedContentTests(unittest.TestCase):
    def setUp(self):
        self.temporary=tempfile.TemporaryDirectory(prefix='edited content ')
        self.root=Path(self.temporary.name)
        self.game=self.root/'game';self.game.mkdir()
        self.original=fixture(self.game/'content')
        self.old_pack=(self.original/'assets.pck').read_bytes()
        self.pointer=(self.game/'content/current.json').read_bytes()
        self.save=self.game/'conf/save.json';self.save.parent.mkdir();self.save.write_bytes(b'keep progress')
        self.source=self.root/'translated.pck'
        self.source.write_bytes(write_pack({'content/generated/test.json':b'{"language":"translated"}'}))
        self.engine=self.root/'probe.py'
        self.engine.write_text('''import json,os,time
from pathlib import Path
pack=Path(os.environ['MOONSTONE_CONTENT_PACK'])
Path('probe-record.json').write_text(json.dumps({'pack':str(pack),'data':os.environ['XDG_DATA_HOME']}))
mode=Path('probe-mode').read_text() if Path('probe-mode').exists() else ''
if mode=='cancel':
    Path('import-cancel').touch()
    time.sleep(60)
if mode=='mutate':Path(os.environ['EDITED_SOURCE']).write_bytes(b'changed during check')
print('LAUNCH_MODE_STATE={"mode":"competitive"}')
if mode=='error':print('SCRIPT ERROR: invalid resource')
''')
        self.env=patch.dict(os.environ,{'EDITED_SOURCE':str(self.source)});self.env.start()
        self.command=patch('import_transfer.engine_command',side_effect=lambda engine,pack,args:[sys.executable,str(self.engine)])
        self.command_mock=self.command.start()

    def tearDown(self):
        self.command.stop();self.env.stop();self.temporary.cleanup()

    def unchanged(self):
        self.assertEqual((self.game/'content/current.json').read_bytes(),self.pointer)
        self.assertEqual((self.original/'assets.pck').read_bytes(),self.old_pack)
        self.assertEqual(self.save.read_bytes(),b'keep progress')
        self.assertEqual(list((self.game/'content').glob('.edited-*')),[])

    def test_new_identity_verifies_and_transfers_over_an_older_installation(self):
        pack=install_pack(self.game,self.source,self.engine)
        sha=hashlib.sha256(self.source.read_bytes()).hexdigest()
        self.assertEqual(pack.parent.name,'classic-v1-'+sha[:16])
        self.assertNotEqual(pack.parent,self.original)
        self.command_mock.assert_called_once_with(self.engine,self.game/'moonstone.pck',['--debug','--smoke'])
        self.assertEqual(installed_content(self.game),pack)
        self.assertEqual(checked_source(self.game/'content')[0]['sha256'],sha)
        self.assertEqual(json.loads((pack.parent/'manifest.json').read_text())['kind'],'custom')
        self.assertEqual((self.original/'assets.pck').read_bytes(),self.old_pack)
        self.assertEqual(self.save.read_bytes(),b'keep progress')
        record=json.loads((self.game/'probe-record.json').read_text())
        self.assertIn('.edited-',record['data'])
        self.assertFalse(Path(record['data']).exists())
        transfer=self.root/'transfer';export_content(self.game,transfer)
        target=self.root/'second';target.mkdir();old=fixture(target/'content')
        install_content(target,transfer)
        self.assertEqual(installed_content(target).read_bytes(),self.source.read_bytes())
        self.assertTrue((old/'assets.pck').exists())
        install_content(target,transfer)  # Repeat installation remains valid.
        self.assertEqual(installed_content(target).read_bytes(),self.source.read_bytes())

    def test_in_place_edit_gets_a_new_generation_without_reconverting_disks(self):
        path=self.original/'assets.pck';path.write_bytes(self.source.read_bytes())
        self.assertIsNone(installed_content(self.game))
        pack=install_pack(self.game,path,self.engine)
        self.assertEqual(installed_content(self.game),pack)
        self.assertNotEqual(pack,path)
        self.assertEqual(path.read_bytes(),self.source.read_bytes())
        self.assertEqual(self.save.read_bytes(),b'keep progress')

    def test_empty_corrupt_and_executable_packs_never_replace_active_content(self):
        for data in [b'',b'broken',write_pack({'assets/classic/extra.gd':b'extends Node'})]:
            with self.subTest(data=data[:10]):
                self.source.write_bytes(data)
                with self.assertRaises(ValueError):install_pack(self.game,self.source,self.engine)
                self.unchanged()
        self.assertFalse((self.game/'probe-record.json').exists())

    def test_startup_errors_and_source_changes_do_not_activate(self):
        for mode in ['error','mutate']:
            with self.subTest(mode=mode):
                self.source.write_bytes(write_pack({'content/generated/test.json':b'{"edited":true}'}))
                (self.game/'probe-mode').write_text(mode)
                with self.assertRaises(ValueError):install_pack(self.game,self.source,self.engine)
                self.unchanged()

    def test_cancellation_stops_the_probe_and_preserves_content(self):
        (self.game/'probe-mode').write_text('cancel')
        with self.assertRaises(ImportCancelled):install_pack(self.game,self.source,self.engine)
        self.unchanged()

    def test_existing_corrupt_destination_is_reported_instead_of_silently_reused(self):
        sha=hashlib.sha256(self.source.read_bytes()).hexdigest()
        existing=self.game/'content'/('classic-v1-'+sha[:16]);existing.mkdir()
        (existing/'assets.pck').write_bytes(b'broken')
        with self.assertRaisesRegex(ValueError,'different checksum'):install_pack(self.game,self.source,self.engine)
        self.unchanged()
        self.assertEqual((existing/'assets.pck').read_bytes(),b'broken')

    def test_desktop_command_uses_the_same_checked_installation(self):
        spec=importlib.util.spec_from_file_location('desktop_launcher',Path(__file__).resolve().parents[1]/'release_launcher.py')
        launcher=importlib.util.module_from_spec(spec);spec.loader.exec_module(launcher)
        with patch.object(launcher,'GAME',self.game),contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(launcher.main(['--install-pack',str(self.source)]),0)
            self.assertEqual(launcher.main(['--verify-content']),0)
        self.assertIn('Edited content ready:',output.getvalue())
        self.assertEqual(installed_content(self.game).read_bytes(),self.source.read_bytes())


if __name__=='__main__':unittest.main()
