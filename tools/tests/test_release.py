from pathlib import Path
import hashlib
import json
import os
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch
from zipfile import ZipFile

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from build_support import ROOT, digest
from portmaster_content import write_pack, read_pack
from import_transfer import checked_source, install_content, export_content
from import_platform import engine_command, installation_lock
from release import collect, validate_tag
from release_source import build_code_pack, script_classes


def fixture(folder, files=None):
    data=write_pack(files or {'content/generated/test.json':b'{"synthetic":true}'})
    sha=hashlib.sha256(data).hexdigest()
    target=folder/('classic-v1-'+sha[:16]);target.mkdir(parents=True)
    (target/'assets.pck').write_bytes(data)
    report={'version':1,'sha256':sha,'startup':'PASS'}
    (target/'manifest.json').write_text(json.dumps(report))
    (folder/'current.json').write_text(json.dumps(report|{'directory':target.name}))
    return target


class PortableContentTests(unittest.TestCase):
    def test_export_install_keeps_only_checked_content_and_preserves_saves(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);source=root/'source';source.mkdir()
            old=fixture(source/'content');(old/'private-extra').write_text('not portable')
            (source/'content/old-generation').mkdir()
            export_content(source,root/'transfer')
            self.assertEqual({p.name for p in (root/'transfer'/old.name).iterdir()},{'assets.pck','manifest.json'})
            target=root/'destination';target.mkdir();save=target/'save.json';save.write_text('keep')
            install_content(target,root/'transfer');install_content(target,root/'transfer')
            self.assertEqual(save.read_text(),'keep')
            self.assertEqual(checked_source(target/'content')[0],checked_source(source/'content')[0])
            with self.assertRaisesRegex(ValueError,'already exists'):export_content(source,root/'transfer')

    def test_invalid_transfers_do_not_change_active_generation(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);game=root/'game';game.mkdir();fixture(game/'content')
            before=(game/'content/current.json').read_bytes()
            for number,files in enumerate([{'scripts/evil.gd':b'extends Node'},
                                            {'assets/classic/evil.gd':b'extends Node'},
                                            {'.moonstone/evil.exe':b'code'}]):
                source=root/str(number);fixture(source,files)
                with self.assertRaisesRegex(ValueError,'media boundary'):install_content(game,source)
                self.assertEqual((game/'content/current.json').read_bytes(),before)
            source=root/'damaged';target=fixture(source);(target/'assets.pck').write_bytes(b'damaged')
            with self.assertRaisesRegex(ValueError,'checksum'):install_content(game,source)
            self.assertEqual((game/'content/current.json').read_bytes(),before)

    def test_wrong_manifest_version_and_existing_invalid_generation_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);target=fixture(root/'source')
            report=json.loads((target/'manifest.json').read_text())
            (target/'manifest.json').write_text(json.dumps(report|{'version':2}))
            with self.assertRaisesRegex(ValueError,'manifest'):checked_source(root/'source')
            (target/'manifest.json').write_text(json.dumps(report))
            game=root/'game';game.mkdir();shutil.copytree(root/'source',game/'content')
            (game/'content'/target.name/'manifest.json').write_text('{}')
            before=(game/'content/current.json').read_bytes()
            with self.assertRaisesRegex(ValueError,'manifest'):install_content(game,root/'source')
            self.assertEqual((game/'content/current.json').read_bytes(),before)

    def test_installer_lock_refuses_concurrent_writers(self):
        with tempfile.TemporaryDirectory() as tmp:
            lock=Path(tmp)/'install.lock'
            with installation_lock(lock):
                with self.assertRaisesRegex(ValueError,'already running'):
                    with installation_lock(lock):pass


class SourceReleaseTests(unittest.TestCase):
    def test_source_pack_contains_classes_and_shaders_without_generated_media(self):
        data,files=build_code_pack(ROOT,'0.1.0')
        self.assertEqual(read_pack(data),files)
        self.assertTrue(any(name.endswith('.gdshader') for name in files))
        self.assertFalse(any(name.startswith(('assets/','content/generated/')) for name in files))
        classes=files['.godot/global_script_class_cache.cfg'].decode()
        self.assertIn('CombatSimulation',classes)
        self.assertIn('content_mount.gd',files['project.godot'].decode())

    def test_class_cache_handles_script_inheritance_and_rejects_cycles_duplicates(self):
        scripts={'base.gd':b'extends Node','child.gd':b'extends "res://base.gd"\nclass_name Child'}
        self.assertIn('"base": "Node"',script_classes(scripts).decode())
        with self.assertRaisesRegex(ValueError,'Duplicate'):script_classes(scripts|{'duplicate.gd':scripts['child.gd']})
        with self.assertRaisesRegex(ValueError,'Cyclic'):script_classes(scripts|{'base.gd':b'extends "res://base.gd"'})

    def test_desktop_engine_commands_use_adjacent_packs(self):
        with patch.dict(os.environ,MOONSTONE_ENGINE_PACK_MODE='adjacent'):
            command=engine_command('engine','unused.pck',['--convert','source'])
            self.assertNotIn('--main-pack',command)
            self.assertEqual(command[-3:],['--','--convert','source'])
        with patch.dict(os.environ,MOONSTONE_ENGINE_PACK_MODE=''):
            self.assertIn('--main-pack',engine_command('engine','importer.pck'))

    def test_release_tag_must_match_source(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);(root/'game').mkdir();(root/'game/version.json').write_text('{"version":"1.2.3-rc.1"}')
            self.assertEqual(validate_tag('v1.2.3-rc.1',root),'1.2.3-rc.1')
            for tag in ['v1.2.3','server-v1.2.3-rc.1','v1.2.4']:
                with self.assertRaises(ValueError):validate_tag(tag,root)

    def release_fixture(self,root):
        (root/'game/server').mkdir(parents=True)
        for file in ['game/version.json','game/server/version.json']:(root/file).write_text('{"version":"0.1.0"}')
        source=root/'inputs';source.mkdir()
        for platform in ['Linux','Windows','PortMaster']:
            path=source/f'Moonstone-0.1.0-{platform}.zip'
            with ZipFile(path,'w') as archive:archive.writestr('README.txt','test')
            (source/(platform+'-build.json')).write_text(json.dumps({'tag':'v0.1.0','version':'0.1.0','platform':platform,'archive':path.name,'sha256':digest(path),'supplied_original_media_files':0,'code_sha256':'same-code','compatibility':'combat','campaign_compatibility':'campaign'}))
            if platform!='PortMaster':(source/(platform+'-acceptance.json')).write_text(json.dumps({'result':'PASS','platform':platform,'execution':'native','archive_sha256':digest(path)}))
        binary=b'synthetic server';sha=hashlib.sha256(binary).hexdigest()
        rows=[{'platform':p,'file':p+'.binary','sha256':sha} for p in ['Linux','Windows']]
        rows[1]['console_wrapper']={'file':'console.exe','sha256':sha}
        build=source/'duel-server-build-manifest.json'
        build.write_text(json.dumps({'version':'0.1.0','tag':'server-v0.1.0','builds':rows,'compatibility':'combat','campaign_compatibility':'campaign'}))
        check=source/'duel-server-verification.json';check.write_text(json.dumps({'result':'PASS','Linux':'PASS','build_manifest_sha256':digest(build)}))
        for row in rows:
            with ZipFile(source/f"Moonstone-Duel-Server-0.1.0-{row['platform']}.zip",'w') as archive:
                archive.writestr(row['file'],binary)
                if row['platform']=='Windows':archive.writestr('console.exe',binary)
                archive.writestr('build-manifest.json',build.read_bytes());archive.writestr('verification.json',check.read_bytes())
        return source

    def test_release_collection_requires_matching_native_and_server_evidence(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);source=self.release_fixture(root)
            (source/'private.ipf').write_text('must not publish')
            collect(source,root/'release','v0.1.0',root)
            self.assertFalse((root/'release/private.ipf').exists())
            self.assertEqual(len(list((root/'release').glob('*.zip'))),5)
            for file,change in [('Windows-acceptance.json',{'result':'FAIL'}),
                                ('Windows-acceptance.json',{'execution':'wine'}),
                                ('Windows-build.json',{'compatibility':'stale-gameplay'}),
                                ('Linux-build.json',{'code_sha256':'different-source'}),
                                ('duel-server-verification.json',{'result':'FAIL'})]:
                path=source/file;before=path.read_bytes();path.write_text(json.dumps(json.loads(before)|change))
                with self.assertRaises((ValueError,KeyError)):collect(source,root/'bad','v0.1.0',root)
                path.write_bytes(before)
            archive_path=source/'Moonstone-Duel-Server-0.1.0-Windows.zip'
            with ZipFile(archive_path) as archive:files={name:archive.read(name) for name in archive.namelist()}
            files['Windows.binary']=b'changed'
            with ZipFile(archive_path,'w') as archive:
                for name,data in files.items():archive.writestr(name,data)
            with self.assertRaisesRegex(ValueError,'executable changed'):collect(source,root/'bad','v0.1.0',root)


if __name__=='__main__':unittest.main()
