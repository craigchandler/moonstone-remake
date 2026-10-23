from pathlib import Path
import hashlib
import json
import os
import subprocess
import signal
import shutil
import tarfile
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from portmaster_content import inspect_pack, read_pack, split_pack, write_pack, merge_packs
from portmaster_import import atomic_json, import_content, installed_content
from import_support import ImportProgress


class ContentPackTests(unittest.TestCase):
    def fixture(self):
        return {'project.binary': b'code', 'scripts/game.gdc': b'program',
                'assets/classic/a.png.import': b'[remap]\npath="res://.godot/imported/a.ctex"\n',
                '.godot/imported/a.ctex': b'private pixels',
                'content/generated/art.tres.remap': b'[remap]\npath="res://.godot/exported/art.res"\n',
                '.godot/exported/art.res': b'private animation resources'}

    def test_round_trip_and_external_remaps(self):
        files = self.fixture()
        self.assertEqual(read_pack(write_pack(files)), files)
        code, media = split_pack(files)
        self.assertEqual(set(code), {'project.binary', 'scripts/game.gdc'})
        self.assertEqual(code | media, files)
        self.assertEqual(read_pack(write_pack(media)), media)

    def test_media_cannot_leak_or_disappear(self):
        for mutate in [lambda f: f.update({'unclassified.sample': b'audio'}),
                       lambda f: f.pop('.godot/exported/art.res')]:
            files = self.fixture()
            mutate(files)
            with self.assertRaises(ValueError):split_pack(files)

    def test_corruption_and_paths_rejected(self):
        data = write_pack(self.fixture())
        for corrupt in [data[:-3], data.replace(b'private pixels', b'changed pixels'), b'not a pack']:
            with self.assertRaises(ValueError):read_pack(corrupt)
        for name in ['../private', '/absolute', 'a/../../escape', 'a\\escape']:
            with self.assertRaises(ValueError):write_pack({name: b'data'})

    def test_mapped_audit_checks_payloads_without_retaining_them(self):
        files=self.fixture()
        with tempfile.TemporaryDirectory() as tmp:
            pack=Path(tmp)/'content.pck';data=write_pack(files);pack.write_bytes(data)
            self.assertEqual(inspect_pack(pack),dict.fromkeys(files))
            self.assertEqual(read_pack(data),files)
            for corrupt in [data.replace(b'private pixels',b'changed pixels'),data[:-3],b'']:
                pack.write_bytes(corrupt)
                with self.assertRaises(ValueError):inspect_pack(pack)
            # Failed audits must also close their memory views and file maps.
            pack.write_bytes(data)
            self.assertEqual(inspect_pack(pack),dict.fromkeys(files))

    def test_worker_merge_preserves_payloads_and_rejects_duplicates_or_corruption(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);paths=[root/'a.pck',root/'b.pck'];target=root/'merged.pck'
            left={'assets/classic/a.png.remap':b'first', '.moonstone/a.res':b'a'*(512*1024+9)}
            right={'content/generated/art.tres':b'declarations','.moonstone/b.res':b'audio'}
            paths[0].write_bytes(write_pack(left));paths[1].write_bytes(write_pack(right))
            merge_packs(paths,target)
            self.assertEqual(read_pack(target.read_bytes()),left|right)
            before=target.read_bytes()
            paths[1].write_bytes(write_pack(left))
            with self.assertRaisesRegex(ValueError,'Duplicate worker'):merge_packs(paths,target)
            self.assertEqual(target.read_bytes(),before)
            paths[1].write_bytes(write_pack(right).replace(b'audio',b'wrong'))
            with self.assertRaisesRegex(ValueError,'Corrupt payload'):merge_packs(paths,target)
            self.assertEqual(target.read_bytes(),before)
            with self.assertRaisesRegex(ValueError,'No worker'):merge_packs([],target)


class ContentInstallationTests(unittest.TestCase):
    def test_progress_detail_preserves_stage_and_cannot_replace_completion(self):
        with tempfile.TemporaryDirectory() as tmp:
            status=Path(tmp)/'status.json'
            original={'state':'running','message':'Preparing art','stage':30,'stages':37,'percent':65}
            atomic_json(status,original)
            with patch.dict(os.environ,{'MOONSTONE_IMPORT_STATUS':str(status)}),patch('import_support.time.monotonic',side_effect=[0,0.5,2,3]):
                reporter=ImportProgress();reporter.update(1,20,'Colour sheet')
                self.assertEqual(json.loads(status.read_text()),original|{'detail':'Colour sheet 1 of 20'})
                reporter.update(2,20,'Colour sheet')
                self.assertEqual(json.loads(status.read_text())['detail'],'Colour sheet 1 of 20')
                atomic_json(status,{'state':'complete','percent':100})
                reporter.update(20,20,'Colour sheet')
                self.assertEqual(json.loads(status.read_text()),{'state':'complete','percent':100})
                status.write_text('unreadable status')
                reporter.update(20,20,'Colour sheet')  # Cosmetic failure is nonfatal.
                self.assertEqual(status.read_text(),'unreadable status')

    def provision(self, root):
        data=b'previous completed content'
        sha=hashlib.sha256(data).hexdigest()
        folder=root/'content'/('classic-v1-'+sha[:16]);folder.mkdir(parents=True)
        (folder/'assets.pck').write_bytes(data)
        atomic_json(folder/'manifest.json',{'version':1,'sha256':sha,'startup':'PASS'})
        atomic_json(root/'content/current.json',{'version':1,'directory':folder.name,'sha256':sha})
        return folder/'assets.pck'

    def test_completed_content_works_without_disks_and_rejects_corruption(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);pack=self.provision(root)
            self.assertEqual(installed_content(root),pack)
            import_content(root,root/'absent-importer',root/'absent-engine')
            self.assertEqual(json.loads((root/'import-status.json').read_text())['state'],'complete')
            pack.write_bytes(b'corrupt')
            self.assertIsNone(installed_content(root))

    def test_wrong_version_and_escaping_manifest_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);self.provision(root)
            manifest=root/'content/current.json';valid=json.loads(manifest.read_text())
            for changes in [{'version':2},{'directory':'../../conf'},{'sha256':'bad'}]:
                atomic_json(manifest,valid|changes)
                self.assertIsNone(installed_content(root))

    def test_failed_reimport_keeps_previous_generation_and_save(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);pack=self.provision(root)
            save=root/'conf/godot/app_userdata/Moonstone Remake/journey.json'
            save.parent.mkdir(parents=True);save.write_bytes(b'user progress')
            before=(root/'content/current.json').read_bytes()
            with self.assertRaisesRegex(ValueError,'three IPF'):
                import_content(root,root/'absent-importer',root/'absent-engine',force=True)
            self.assertEqual((root/'content/current.json').read_bytes(),before)
            self.assertEqual(installed_content(root),pack)
            self.assertEqual(save.read_bytes(),b'user progress')

    def test_cancel_during_converter_wait_stops_child_and_preserves_content(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);pack=self.provision(root)
            before=(root/'content/current.json').read_bytes()
            save=root/'conf/journey.json';save.parent.mkdir();save.write_bytes(b'user progress')
            (root/'disks').mkdir()
            for letter in 'ABC':(root/'disks'/('Moonstone_Disk'+letter+'.ipf')).write_bytes(b'test disk')
            helper=root/'importer';scripts=helper/'project/tools';scripts.mkdir(parents=True)
            marker=root/'converter-started'
            script=scripts/'import_ipf.py'
            script.write_text('import os,time\nfrom pathlib import Path\nPath('+repr(str(marker))+').write_text(str(os.getpid()))\ntime.sleep(60)\n')
            (helper/'manifest.json').write_text(json.dumps({'files':{'project/tools/import_ipf.py':hashlib.sha256(script.read_bytes()).hexdigest()}}))
            command=[sys.executable,str(Path(__file__).resolve().parents[1]/'portmaster_import.py'),
                     '--game-dir',str(root),'--importer',str(helper),'--godot',str(root/'unused-engine'),'--force']
            worker=subprocess.Popen(command,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,start_new_session=True)
            try:
                deadline=time.monotonic()+5
                while not marker.exists() and worker.poll() is None and time.monotonic()<deadline:time.sleep(0.02)
                self.assertTrue(marker.exists(),'Converter did not start')
                worker.terminate()
                stdout,stderr=worker.communicate(timeout=5)
                self.assertNotEqual(worker.returncode,0,stdout+stderr)
                self.assertIn('Import cancelled',stderr)
                with self.assertRaises(ProcessLookupError):os.kill(int(marker.read_text()),0)
                self.assertEqual((root/'content/current.json').read_bytes(),before)
                self.assertEqual(installed_content(root),pack)
                self.assertEqual(save.read_bytes(),b'user progress')
                self.assertEqual(list((root/'content').glob('.import-*')),[])
            finally:
                if worker.poll() is None:os.killpg(worker.pid,signal.SIGKILL)
                worker.communicate()


class ImporterLaunchTests(unittest.TestCase):
    def launch(self, ready=False, corrupt=False, plain_tar_only=False,
               cancel=True, noisy_failure=False, preload=False, bad_success=False, bootstrap_cancel=False,
               setup_exit=0, abort_before_import=False, corrupt_after_import=False, copied=False):
        with tempfile.TemporaryDirectory(prefix='moonstone external ') as tmp:
            root=Path(tmp);helper=root/'build'
            python_stub = """#!/usr/bin/env python3
import os,sys,json
from pathlib import Path
root=Path.cwd();pack=root/'content with spaces/assets.pck'
if os.environ.get('LD_PRELOAD'):
    print('Crusty startup diagnostics');sys.exit(1)
if '--verify' in sys.argv:
    if pack.exists():
        if (root/'bad-success').exists():print('unrelated diagnostics')
        print(pack)
        sys.exit(1 if (root/'noisy-failure').exists() else 0)
    sys.exit(1)
pack.parent.mkdir(exist_ok=True);pack.write_bytes(b'generated content')
(root/'import-status.json').write_text(json.dumps({'state':'complete','message':'Content is ready','percent':100}))
"""
            files={'python/bin/python3.14':python_stub,'manifest.json':'{}',
                   'project/tools/portmaster_import.py':'',
                   'bin/bake-audio':'','bin/bake-menu':'','bin/bake-module':''}
            for name,value in files.items():
                path=helper/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_text(value)
                if '/bin/' in name:path.chmod(0o755)
            with tarfile.open(root/'importer.tar','w',format=tarfile.USTAR_FORMAT) as archive:
                for name in files:archive.add(helper/name,arcname=name)
            sha=hashlib.sha256((root/'importer.tar').read_bytes()).hexdigest()
            (root/'importer.sha256').write_text(sha+'  importer.tar\n')
            if corrupt:
                with (root/'importer.tar').open('ab') as stream:stream.write(b'broken')
            (root/'importer.pck').write_bytes(b'setup');(root/'cache').mkdir()
            if ready:
                shutil.copytree(helper,root/'cache'/('importer-'+sha))
                (root/'content with spaces').mkdir();(root/'content with spaces/assets.pck').write_bytes(b'content')
            if copied:
                (root/'content').mkdir();(root/'content/current.json').write_text('{}')
                (root/'content with spaces').mkdir();(root/'content with spaces/assets.pck').write_bytes(b'copied content')
            for marker,value in [('cancel',cancel),('noisy-failure',noisy_failure),('bad-success',bad_success),('cancel-bootstrap',bootstrap_cancel)]:
                if value:(root/marker).touch()
            (root/'setup-exit').write_text(str(setup_exit))
            if abort_before_import:(root/'abort-before-import').touch()
            if corrupt_after_import:(root/'corrupt-after-import').touch()
            engine=root/'engine.py';engine.write_text("""#!/usr/bin/env python3
import os,sys,json,subprocess,time
from pathlib import Path
file=Path('engine.json');records=json.loads(file.read_text()) if file.exists() else []
setup=sys.argv[-1].endswith('importer.pck')
records.append({'setup':setup,'verify':'--verify-content' in sys.argv,'args':sys.argv[1:],'content':os.environ.get('MOONSTONE_CONTENT_PACK'),
                'preload':os.environ.get('LD_PRELOAD'),'cache_ready':(Path(os.environ['MOONSTONE_IMPORTER_DIR'])/'manifest.json').exists()})
file.write_text(json.dumps(records))
if '--verify-content' in sys.argv:
    assert not os.environ.get('LD_PRELOAD')
    print('CONTENT_PACK_PATH='+str(Path.cwd()/'content with spaces/assets.pck'))
    sys.exit(0)
if setup:
    if Path('cancel').exists():sys.exit(2)
    if Path('abort-before-import').exists():sys.exit(134)
    if Path('cancel-bootstrap').exists():
        worker=subprocess.Popen(['bash','run.sh','--prepare-content',str(Path(__file__).resolve())])
        try:
            deadline=time.monotonic()+5
            while not Path('tar-pid').exists() and time.monotonic()<deadline:time.sleep(0.02)
            assert Path('tar-pid').exists()
            worker.terminate();worker.wait(timeout=3)
            try:os.kill(int(Path('tar-pid').read_text()),0)
            except ProcessLookupError:pass
            else:raise AssertionError('Bootstrap child survived cancellation')
            assert not list(Path('cache').glob('importer-*'))
            sys.exit(worker.returncode)
        finally:
            if worker.poll() is None:worker.kill();worker.wait()
    result=subprocess.run(['bash','run.sh','--prepare-content',str(Path(__file__).resolve())])
    if Path('corrupt-after-import').exists():Path('content with spaces/assets.pck').unlink()
    sys.exit(result.returncode or int(Path('setup-exit').read_text()))
""");engine.chmod(0o755)
            script=(Path(__file__).resolve().parents[1]/'run_portmaster.sh').read_text().replace('/tmp/moonstone-godot/godot463.aarch64',str(engine))
            (root/'run.sh').write_text(script)
            env=os.environ.copy()
            if preload:env['LD_PRELOAD']='/missing/moonstone-test-graphics-preload.so'
            if plain_tar_only or bootstrap_cancel:
                commands=root/'commands';commands.mkdir();shim=commands/'tar'
                shim.write_text('#!/bin/bash\nfor option in "$@"; do\ncase "$option" in -*z*) echo "tar: invalid option -- z" >&2; exit 86;; esac\ndone\nexec "'+shutil.which('tar')+'" "$@"\n')
                if bootstrap_cancel:shim.write_text('#!/bin/bash\nprintf "%s\\n" "$$" > "$PWD/tar-pid"\nexec sleep 60\n')
                shim.chmod(0o755);env['PATH']=str(commands)+os.pathsep+env['PATH']
                self.assertEqual((root/'importer.tar').read_bytes()[257:263],b'ustar\0')
            result=subprocess.run(['bash',root/'run.sh'],cwd=root,env=env,capture_output=True,text=True,timeout=10)
            records=json.loads((root/'engine.json').read_text()) if (root/'engine.json').exists() else []
            status=json.loads((root/'import-status.json').read_text()) if (root/'import-status.json').exists() else None
            return result.returncode,records,result.stdout+result.stderr,status

    def test_cancelled_setup_cannot_launch_the_game_or_unpack_tools(self):
        code,records,output,_=self.launch()
        self.assertEqual(code,2,output)
        self.assertEqual(len(records),1)
        self.assertTrue(records[0]['setup'])
        self.assertFalse(records[0]['cache_ready'])

    def test_verified_content_skips_setup_and_preserves_spaces(self):
        code,records,output,_=self.launch(ready=True)
        self.assertEqual(code,0,output)
        self.assertEqual(len(records),1)
        self.assertFalse(records[0]['setup'])
        self.assertTrue(records[0]['content'].endswith('/content with spaces/assets.pck'))

    def test_copied_content_skips_unpacking_tools_and_gui_setup(self):
        code,records,output,_=self.launch(copied=True,preload=True)
        self.assertEqual(code,0,output)
        self.assertEqual([r['verify'] for r in records],[True,False])
        self.assertFalse(any(r['setup'] or r['cache_ready'] for r in records))
        self.assertTrue(records[-1]['content'].endswith('/content with spaces/assets.pck'))

    def test_damaged_importer_reports_failure_without_launching_game(self):
        code,records,output,status=self.launch(corrupt=True,cancel=False)
        self.assertNotEqual(code,0,output)
        self.assertEqual(len(records),1)
        self.assertTrue(records[0]['setup'])
        self.assertEqual(status['state'],'failed')

    def test_firmware_tar_without_gzip_support_installs_after_screen_opens(self):
        code,records,output,status=self.launch(plain_tar_only=True,cancel=False)
        self.assertEqual(code,0,output)
        self.assertEqual([r['setup'] for r in records],[True,False])
        self.assertFalse(records[0]['cache_ready'])
        self.assertTrue(records[1]['cache_ready'])
        self.assertEqual(status['state'],'complete')

    def test_failed_verification_stdout_cannot_become_a_content_path(self):
        code,records,output,_=self.launch(ready=True,noisy_failure=True)
        self.assertEqual(code,2,output)
        self.assertEqual([r['setup'] for r in records],[True])

    def test_multiline_success_output_is_not_a_content_path(self):
        code,records,output,_=self.launch(ready=True,bad_success=True)
        self.assertEqual(code,2,output)
        self.assertEqual([r['setup'] for r in records],[True])

    def test_graphics_preload_is_removed_only_for_import_tools(self):
        for ready in [False,True]:
            with self.subTest(ready=ready):
                code,records,output,_=self.launch(ready=ready,preload=True,cancel=False)
                self.assertEqual(code,0,output)
                self.assertFalse(records[-1]['setup'])
                self.assertTrue(records[-1]['content'].endswith('/content with spaces/assets.pck'))
                self.assertEqual(records[-1]['preload'],'/missing/moonstone-test-graphics-preload.so')

    def test_cancel_during_unpack_stops_child_and_removes_partial_cache(self):
        code,records,output,status=self.launch(cancel=False,bootstrap_cancel=True)
        self.assertEqual(code,2,output)
        self.assertEqual([r['setup'] for r in records],[True])
        self.assertIn('cancelled',status['message'])

    def test_setup_shutdown_abort_continues_only_with_verified_content(self):
        code,records,output,status=self.launch(cancel=False,setup_exit=134)
        self.assertEqual(code,0,output)
        self.assertEqual([r['setup'] for r in records],[True,False])
        self.assertEqual(status['state'],'complete')
        self.assertIn('completed content checksum verified',output)
        self.assertTrue(records[-1]['content'].endswith('/content with spaces/assets.pck'))

    def test_setup_abort_before_or_without_valid_content_does_not_launch(self):
        for changes in [{'abort_before_import':True},{'setup_exit':134,'corrupt_after_import':True},
                        {'setup_exit':134,'noisy_failure':True},{'setup_exit':134,'bad_success':True}]:
            with self.subTest(changes=changes):
                code,records,output,_=self.launch(cancel=False,**changes)
                self.assertEqual(code,134,output)
                self.assertEqual([r['setup'] for r in records],[True])

    def test_cancel_and_other_setup_errors_stay_failures_even_after_activation(self):
        for setup_exit in [2,7,139]:
            with self.subTest(setup_exit=setup_exit):
                code,records,output,status=self.launch(cancel=False,setup_exit=setup_exit)
                self.assertEqual(code,setup_exit,output)
                self.assertEqual([r['setup'] for r in records],[True])
                self.assertEqual(status['state'],'complete')
