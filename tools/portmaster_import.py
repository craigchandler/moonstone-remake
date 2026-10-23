#!/usr/bin/env python3
"""One-time, transactional owned-disk import for an installed Moonstone port."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time

from portmaster_content import CONTENT_VERSION, MEDIA_ROOTS, inspect_pack, merge_packs
from import_parallel import run_lanes
from import_worker import warm_modules, start_converter
from import_platform import installation_lock, child_usage, usage_delta, stop_group, engine_command

DISKS=tuple('Moonstone_Disk'+letter+'.ipf' for letter in 'ABC')
MOG_SHA1='bb38bc0b39f146b30bac959bea717202cf13b965'
STAGES=[
    ('knight_animations',[]),('spear_trogg',[]),('axe_trogg',[]),('troll',[]),
    ('hit_effects',[]),('balok',[]),('world_art',[]),('loot',[]),
    ('creature_pack',[]),('creature_pack',['--combat-corrections']),('creature_pack',['--tree-beast']),
    ('beast_frames',[]),('map_travel',[]),('finishes',[]),('death_frames',[]),
    ('hit_recovery',[]),('knockback',[]),('guardian_timing',[]),('stonehenge',[]),
    ('moonstone_quest',[]),('ending_opening',[]),('ratman_tree',[]),('map_locations',[]),
    ('intro_menu',[]),('targeted_scrolls',[]),('town_locations',[]),('ending_complete',[]),
    ('knight_selection',[]),('beast_entries',[]),('trogg_timing',[]),('monster_timing',[]),
    ('audio',[]),('classic_layers',[]),
]
# The four lanes write disjoint output families. Keep successive fixes
# to the same combat family in one lane; ending_complete reads ending_opening,
# and map_locations extends world_art. Selection and timing wait at the barrier.
PARALLEL_LANES = [
    [8,9,10,11,13,14,15,16,17,21],
    [1,2,3,6,7,12,18,19,22,24,25],
    [0,4,5,20,26],
    [23],
]
AFTER_LANES = [27,28,29,30]


class ImportCancelled(RuntimeError):
    # multiprocessing treats OSError (including InterruptedError) as an OS-level
    # wait interruption. Use a distinct exception so cancellation unwinds fully.
    pass


def digest(path):
    with path.open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()


def atomic_json(path,value):
    temporary=path.with_suffix(path.suffix+'.new')
    with temporary.open('w') as stream:
        json.dump(value,stream,indent=2);stream.write('\n');stream.flush();os.fsync(stream.fileno())
    os.replace(temporary,path)


def installed_content(game, verify=True):
    try:
        record=json.loads((game/'content/current.json').read_text())
        name=record['directory']
        if record['version']!=CONTENT_VERSION or not re.fullmatch(r'classic-v1-[a-f0-9]{16}',name):return None
        if not re.fullmatch(r'[a-f0-9]{64}',record['sha256']):return None
        if name!='classic-v1-'+record['sha256'][:16]:return None
        pack=game/'content'/name/'assets.pck'
        if not pack.is_file() or pack.resolve().parent.parent!=(game/'content').resolve():return None
        report=json.loads((pack.parent/'manifest.json').read_text())
        if not isinstance(report,dict) or report.get('version')!=CONTENT_VERSION or report.get('sha256')!=record['sha256'] or report.get('startup')!='PASS':return None
        if verify and digest(pack)!=record['sha256']:return None
        return pack
    except (OSError,ValueError,KeyError,TypeError):return None


def import_content(game, importer, godot, force=False, keep_work=False):
    game=game.resolve();importer=importer.resolve();godot=godot.resolve()
    content=game/'content';content.mkdir(exist_ok=True)
    with installation_lock(content/'install.lock'):
        return _import_locked(game,importer,godot,force,keep_work)


def _import_locked(game,importer,godot,force,keep_work):
    content=game/'content'
    status=game/'import-status.json'
    def progress(message,percent,state='running',stage=None,detail=None):
        record={'state':state,'message':message,'percent':percent}
        if stage is not None:record.update(stage=stage,stages=len(STAGES)+4)
        if detail:record['detail']=detail
        atomic_json(status,record)
    if not force and installed_content(game):
        progress('Content is ready',100,'complete');return
    missing=[name for name in DISKS if not (game/'disks'/name).is_file()]
    if missing:raise ValueError('Copy your three IPF images into ports/moonstone/disks: '+', '.join(missing))
    if shutil.disk_usage(content).free<1024**3:raise ValueError('At least 1 GB free space is needed during conversion')
    started=time.monotonic()
    timings=[]
    batches=[]
    input_hashes={name:digest(game/'disks'/name) for name in DISKS}
    job=Path(tempfile.mkdtemp(prefix='.import-',dir=content))
    child=None
    def check_cancel():
        if (game/'import-cancel').exists():raise ImportCancelled('Import cancelled; previous content is unchanged')
    def interrupted(signum,frame):
        # Unwind Popen.wait before waiting again: its internal waitpid lock is
        # not reentrant when a signal arrives while the converter is running.
        raise ImportCancelled('Import cancelled; previous content is unchanged')
    old_handlers={n:signal.signal(n,interrupted) for n in (signal.SIGINT,signal.SIGTERM)}
    try:
        check_cancel()
        progress('Checking importer files',1)
        manifest=json.loads((importer/'manifest.json').read_text())
        for name,expected in manifest['files'].items():
            path=importer/name
            if not path.resolve().is_relative_to(importer) or digest(path)!=expected:
                raise ValueError('Importer is incomplete or damaged: '+name)
        project=job/'project';shutil.copytree(importer/'project',project)
        for folder in ['docs','outputs','reference','game/assets/classic','game/content/generated','game/tests/fixtures']:(project/folder).mkdir(parents=True,exist_ok=True)
        env=os.environ.copy();env.update(MOONSTONE_IMPORT_BIN=str(importer/'bin'),MOONSTONE_IMPORT_STATUS=str(status),
                                        MOONSTONE_COMPACT_LAYERS='1',MOONSTONE_IMPORT_WARM_WORKERS='1',
                                        PYTHONDONTWRITEBYTECODE='1',OPENBLAS_NUM_THREADS='1')
        warm_modules()
        # Compact intermediates permit four disjoint lanes on the quad-core
        # target. Smaller hosts can select fewer without changing dependencies.
        workers=max(1,min(4,os.cpu_count() or 1,int(env.get('MOONSTONE_IMPORT_JOBS','4'))))
        env['MOONSTONE_IMPORT_JOBS']=str(workers)
        python=Path(sys.executable)
        with (game/'import.log').open('w') as log:
            def run(command,label,percent,environment=env):
                nonlocal child
                progress(label,percent,stage=len(timings)+1)
                log.write('\n'+label+'\n');log.flush()
                stage_started=time.monotonic()
                check_cancel()
                usage_before=child_usage()
                child=start_converter(command,project,environment,log)
                while True:
                    try:code=child.wait(timeout=0.2);break
                    except subprocess.TimeoutExpired:check_cancel()
                check_cancel()
                if code:raise RuntimeError(label+' failed. Details are in '+str(game/'import.log'))
                child=None
                seconds=round(time.monotonic()-stage_started,3)
                usage=usage_delta(usage_before)
                timings.append({'stage':label,'seconds':seconds,**usage})
                log.write(f'Completed in {seconds:.3f} seconds; usage {json.dumps(usage)}\n');log.flush()
            run([python,project/'tools/import_ipf.py',*[game/'disks'/name for name in DISKS],
                 '--caps-library',importer/'bin'/('capsimg.dll' if os.name=='nt' else 'capsimg.so'),'--files-only','--out',project/'reference/extracted'],'Reading and checking the three disks',3)
            mog=project/'reference/extracted/A/mog'
            if hashlib.sha1(mog.read_bytes()).hexdigest()!=MOG_SHA1:raise ValueError('This disk release is not supported; original files were left unchanged')
            run([python,project/'work/upstream/moonstone-ace/tools/artconv.py','export','--disks',project/'reference/extracted',
                 '--out',project/'game/assets/classic/recovered'],'Extracting original artwork',8)
            def command(index):
                name,args=STAGES[index]
                return ([python,project/'tools'/('import_'+name+'.py'),*args], 'Preparing '+name.replace('_',' '))
            def batch(lanes):
                before=len(timings)
                folder=job/f'parallel-{len(batches)}'
                def update(active,completed):
                    check_cancel()
                    details=[]
                    for label,path in active:
                        detail=label.removeprefix('Preparing ')
                        try:
                            record=json.loads(path.read_text())
                            if record.get('detail'):detail+=': '+record['detail']
                        except (OSError,ValueError):pass
                        details.append(detail)
                    done=before+len(completed)
                    progress('Preparing game content',12+int((done-2)*65/len(STAGES)),
                             stage=min(done+1,len(STAGES)+2),detail='\n'.join(details))
                try:
                    rows,usage=run_lanes([[command(i) for i in lane] for lane in lanes],
                                         project,env,folder,update,workers)
                    batches.append(usage)
                    timings.extend({k:v for k,v in row.items() if k not in ('log','exit')} for row in rows)
                    for row in rows:log.write(f"\n{row['stage']}: {row['seconds']:.3f} seconds (parallel)\n")
                    log.write('Parallel batch: '+json.dumps(usage)+'\n')
                finally:
                    # Preserve errors in import.log before the transactional
                    # workspace is removed, including cancellation/failure logs.
                    for path in sorted(folder.glob('*.log')):
                        log.write('\n'+path.read_text(errors='replace'))
                    log.flush()
            batch(PARALLEL_LANES)
            for index in AFTER_LANES:
                cmd,label=command(index)
                run(cmd,label,12+int((len(timings)-2)*65/len(STAGES)))
            batch([[31],[32]])  # Audio reads final provenance; layers write a separate folder.
            result=job/'result';result.mkdir()
            label='Building external game content'
            progress(label,80,stage=len(timings)+1)
            log.write('\n'+label+'\n');log.flush()
            pack_started=time.monotonic()
            folder=job/'pack-workers'
            packs=[job/f'worker-{i}.pck' for i in range(workers)]
            lanes=[[(
                engine_command(godot,game/'importer.pck',
                    ['--convert',project/'game',packs[i],job/f'resources-{i}',str(i),str(workers)]),
                f'Packing resource group {i+1} of {workers}')]
                for i in range(workers)]
            def packing_progress(active,completed):
                check_cancel()
                details=[]
                for group,path in active:
                    detail=group
                    try:
                        record=json.loads(path.read_text())
                        if record.get('detail'):detail+=': '+record['detail']
                    except (OSError,ValueError):pass
                    details.append(detail)
                progress(label,80,stage=len(timings)+1,detail='\n'.join(details))
            try:
                rows,usage=run_lanes(lanes,project,env,folder,packing_progress,workers)
                merge_packs(packs,result/'assets.pck')
                timings.append({'stage':label,'seconds':round(time.monotonic()-pack_started,3),
                                'workers':workers,'worker_seconds':[row['seconds'] for row in rows],
                                'cpu_seconds':usage['cpu_seconds'],'major_page_faults':usage['major_page_faults']})
                log.write('Packing workers and merge: '+json.dumps(timings[-1])+'\n')
            finally:
                for path in sorted(folder.glob('*.log')):log.write('\n'+path.read_text(errors='replace'))
                log.flush()
            resources=inspect_pack(result/'assets.pck')
            if any(not name.startswith((*MEDIA_ROOTS,'.moonstone/')) or name.endswith(('.gd','.gdc','.gdextension','.so')) for name in resources):
                raise ValueError('Content pack contains a file outside the media boundary')
            pack_hash=digest(result/'assets.pck')
            probe_env=env.copy();probe_env.update(MOONSTONE_CONTENT_PACK=str(result/'assets.pck'))
            for variable in ['XDG_DATA_HOME','XDG_CONFIG_HOME','XDG_CACHE_HOME']:probe_env[variable]=str(job/variable)
            game_engine=Path(env.get('MOONSTONE_GAME_ENGINE',str(godot)))
            run(engine_command(game_engine,game/'moonstone.pck',['--smoke']),
                'Checking the generated content',95,probe_env)
            log.flush()
            text=(game/'import.log').read_text(errors='replace')
            if 'LAUNCH_MODE_STATE=' not in text or 'SCRIPT ERROR:' in text or '\nERROR:' in text:
                raise ValueError('Generated content did not pass the game startup check; see import.log')
            if any(digest(game/'disks'/name)!=value for name,value in input_hashes.items()):raise ValueError('Disk input changed during conversion')
            check_cancel()
            report={'version':CONTENT_VERSION,'sha256':pack_hash,'disks':input_hashes,'resource_files':len(resources),
                    'seconds':round(time.monotonic()-started,2),'stages':timings,'parallel_batches':batches,'startup':'PASS'}
            atomic_json(result/'manifest.json',report)
            target=content/('classic-v1-'+pack_hash[:16])
            if target.exists():
                if digest(target/'assets.pck')!=pack_hash:raise ValueError('Existing content generation has a different checksum')
            else:os.replace(result,target)
            check_cancel()
            atomic_json(content/'current.json',{'version':CONTENT_VERSION,'directory':target.name,'sha256':pack_hash})
            progress('Content is ready',100,'complete')
    finally:
        for n,handler in old_handlers.items():signal.signal(n,handler)
        if child is not None and child.poll() is None:
            # Converters may themselves launch native audio helpers. Stop the
            # whole converter group before removing its temporary workspace.
            stop_group(child)
            try:child.wait(timeout=10)
            except subprocess.TimeoutExpired:
                stop_group(child,force=True)
                child.wait()
        if not keep_work:shutil.rmtree(job)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--game-dir',type=Path,required=True)
    parser.add_argument('--importer',type=Path)
    parser.add_argument('--godot',type=Path)
    parser.add_argument('--verify',action='store_true')
    parser.add_argument('--force',action='store_true')
    parser.add_argument('--keep-work',action='store_true')
    args=parser.parse_args()
    if args.verify:
        pack=installed_content(args.game_dir)
        if pack:print(pack);return 0
        return 1
    if args.importer is None or args.godot is None:parser.error('--importer and --godot are required for conversion')
    try:import_content(args.game_dir,args.importer,args.godot,args.force,args.keep_work)
    except Exception as error:
        atomic_json(args.game_dir/'import-status.json',{'state':'failed','message':str(error),'percent':0})
        print(str(error),file=sys.stderr);return 1
    return 0


if __name__=='__main__':raise SystemExit(main())
