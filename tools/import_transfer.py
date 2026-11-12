"""Validated portable content copies and explicitly approved edited media packs."""
from pathlib import Path
import json
import os
import re
import shutil
import signal
import subprocess
import tempfile
import time
from portmaster_content import CONTENT_VERSION, MEDIA_ROOTS, inspect_pack
from import_platform import installation_lock, engine_command, process_options, stop_group


def checked_media(pack):
    resources = inspect_pack(pack)
    if any(not name.startswith((*MEDIA_ROOTS, '.moonstone/')) or Path(name).suffix not in {'.png','.wav','.json','.tres','.res','.remap','.import','.ctex','.sample'} for name in resources):
        raise ValueError('Content pack contains a file outside the media boundary')
    return resources


def checked_source(folder):
    from portmaster_import import digest
    folder = folder.resolve()
    pointer = json.loads((folder/'current.json').read_text())
    if not isinstance(pointer,dict) or pointer.get('version') != CONTENT_VERSION or not isinstance(pointer.get('directory'),str) or not re.fullmatch(r'classic-v1-[a-f0-9]{16}', pointer['directory']):
        raise ValueError('Unsupported content pointer')
    expected = pointer.get('sha256','')
    if not isinstance(expected,str) or not re.fullmatch(r'[a-f0-9]{64}', expected) or pointer['directory'] != 'classic-v1-' + expected[:16]:
        raise ValueError('Invalid content checksum or generation name')
    generation = folder / pointer['directory']
    pack = generation / 'assets.pck'
    if (generation.is_symlink() or not generation.resolve().is_relative_to(folder)
            or pack.is_symlink() or (generation/'manifest.json').is_symlink() or digest(pack) != expected):
        raise ValueError('Content checksum mismatch or unsafe content path')
    report = json.loads((generation/'manifest.json').read_text())
    if not isinstance(report,dict) or report.get('version') != CONTENT_VERSION or report.get('sha256') != expected or report.get('startup') != 'PASS':
        raise ValueError('Content manifest does not match the verified generation')
    checked_media(pack)
    return pointer, generation


def export_content(game, destination):
    from portmaster_import import atomic_json
    pointer, generation = checked_source(game/'content')
    destination = destination.resolve()
    if destination.exists():raise ValueError('Export destination already exists; choose a new folder')
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix='.moonstone-export-', dir=destination.parent))
    try:
        target = temporary / pointer['directory'];target.mkdir()
        for name in ['assets.pck','manifest.json']:shutil.copy2(generation/name, target/name)
        atomic_json(temporary/'current.json', pointer)
        checked_source(temporary)
        os.rename(temporary, destination)
    finally:
        if temporary.exists():shutil.rmtree(temporary)


def activate_content(content, pointer, temporary):
    """Called with the installation lock held and a fully checked new generation."""
    from portmaster_import import atomic_json, digest
    target = content / pointer['directory']
    if target.exists():
        if target.is_symlink() or (target/'assets.pck').is_symlink() or digest(target/'assets.pck') != pointer['sha256']:
            raise ValueError('Existing generation has a different checksum or unsafe path')
        if (target/'manifest.json').is_symlink():raise ValueError('Existing generation has an invalid manifest')
        report=json.loads((target/'manifest.json').read_text())
        if not isinstance(report,dict) or report.get('version')!=CONTENT_VERSION or report.get('sha256')!=pointer['sha256'] or report.get('startup')!='PASS':
            raise ValueError('Existing generation has an invalid manifest')
    else:
        os.rename(temporary, target)
    atomic_json(content/'current.json', pointer)


def install_content(game, source):
    from portmaster_import import digest
    pointer, generation = checked_source(source)
    content = game/'content';content.mkdir(exist_ok=True)
    with installation_lock(content/'install.lock'):
        temporary = Path(tempfile.mkdtemp(prefix='.copy-', dir=content))
        try:
            for name in ['assets.pck','manifest.json']:shutil.copy2(generation/name, temporary/name)
            if digest(temporary/'assets.pck') != pointer['sha256']:raise ValueError('Content changed while copying')
            # Validate the copied manifest as well, before making it active.
            report=json.loads((temporary/'manifest.json').read_text())
            if not isinstance(report,dict) or report.get('version')!=CONTENT_VERSION or report.get('sha256')!=pointer['sha256'] or report.get('startup')!='PASS':
                raise ValueError('Content manifest changed while copying')
            activate_content(content, pointer, temporary)
        finally:
            if temporary.exists():shutil.rmtree(temporary)


def install_pack(game, source, godot):
    """Check an explicitly selected edited pack; activate only after game startup passes."""
    from portmaster_import import atomic_json, digest, ImportCancelled
    game=game.resolve();source=source.absolute()
    if source.is_symlink() or not source.is_file():raise ValueError('Select a regular assets.pck file')
    content=game/'content';content.mkdir(exist_ok=True)
    def progress(message, percent):
        atomic_json(game/'import-status.json', {'state':'running','message':message,'percent':percent})
    def check_cancel():
        if (game/'import-cancel').exists():raise ImportCancelled('Check cancelled; active content and saves are unchanged')
    def interrupted(signum, frame):
        raise ImportCancelled('Check cancelled; active content and saves are unchanged')
    with installation_lock(content/'install.lock'):
        work=Path(tempfile.mkdtemp(prefix='.edited-',dir=content))
        child=None
        handlers={n:signal.signal(n,interrupted) for n in (signal.SIGINT,signal.SIGTERM)}
        try:
            check_cancel();progress('Checking edited game content',10)
            result=work/'result';result.mkdir()
            pack=result/'assets.pck';shutil.copy2(source,pack)
            resources=checked_media(pack)
            checksum=digest(pack)
            if digest(source)!=checksum:raise ValueError('Edited content changed while copying; try again')
            check_cancel();progress('Checking that the game can load the edited content',50)
            env=os.environ.copy();env['MOONSTONE_CONTENT_PACK']=str(pack)
            for key in ['XDG_DATA_HOME','XDG_CONFIG_HOME','XDG_CACHE_HOME']:env[key]=str(work/key)
            engine=Path(env.get('MOONSTONE_GAME_ENGINE',str(godot)))
            log_path=game/'import.log'
            with log_path.open('w') as log:
                child=subprocess.Popen(engine_command(engine,game/'moonstone.pck',['--debug','--smoke']),
                                       cwd=game,env=env,stdout=log,stderr=subprocess.STDOUT,**process_options())
                deadline=time.monotonic()+60
                while True:
                    check_cancel()
                    if time.monotonic()>deadline:raise ValueError('Edited content startup check timed out. See import.log.')
                    try:code=child.wait(timeout=0.2);break
                    except subprocess.TimeoutExpired:pass
            text=log_path.read_text(errors='replace')
            if code or 'LAUNCH_MODE_STATE=' not in text or any(line.startswith(('ERROR:','SCRIPT ERROR:')) for line in text.splitlines()):
                raise ValueError('Edited content did not pass the game startup check. See import.log.')
            if digest(pack)!=checksum or digest(source)!=checksum:raise ValueError('Edited content changed during validation; try again')
            pointer={'version':CONTENT_VERSION,'directory':'classic-v1-'+checksum[:16],'sha256':checksum}
            atomic_json(result/'manifest.json',{'version':CONTENT_VERSION,'sha256':checksum,
                        'resource_files':len(resources),'startup':'PASS','kind':'custom'})
            check_cancel()
            activate_content(content,pointer,result)
            atomic_json(game/'import-status.json',{'state':'complete','message':'Edited content is ready','percent':100})
            return content/pointer['directory']/'assets.pck'
        finally:
            for number,handler in handlers.items():signal.signal(number,handler)
            if child is not None and child.poll() is None:
                stop_group(child)
                try:child.wait(timeout=5)
                except subprocess.TimeoutExpired:stop_group(child,force=True);child.wait()
            shutil.rmtree(work)
