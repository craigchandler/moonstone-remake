#!/usr/bin/env python3
"""Native desktop package acceptance using generated test media, never game disks."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform as host
import subprocess
import tempfile
from zipfile import ZipFile
from build_support import ROOT, digest
from portmaster_content import inspect_pack, MEDIA_ROOTS
from import_transfer import checked_source


def extract(archive, directory):
    with ZipFile(archive) as source:
        names=set()
        for info in source.infolist():
            name=PurePosixPath(info.filename)
            if (name.is_absolute() or '..' in name.parts or '\\' in info.filename
                    or info.filename.casefold() in names or (info.external_attr>>16)&0o170000==0o120000):
                raise ValueError('Unsafe or duplicate ZIP member: '+info.filename)
            names.add(info.filename.casefold())
            target=directory.joinpath(*name.parts)
            if info.is_dir():target.mkdir(parents=True,exist_ok=True);continue
            target.parent.mkdir(parents=True,exist_ok=True)
            target.write_bytes(source.read(info))
            if os.name!='nt':target.chmod((info.external_attr>>16)&0o777 or 0o644)


def verify(archive, platform, output):
    if host.system()!=platform:raise ValueError('Acceptance must execute on native '+platform)
    ROOT.joinpath('work').mkdir(exist_ok=True)
    directory=Path(tempfile.mkdtemp(prefix='release acceptance ',dir=ROOT/'work'))
    game=directory/'game with spaces';game.mkdir();extract(archive,game)
    windows=platform=='Windows'
    python=game/'importer/python'/('python.exe' if windows else 'bin/python3.14')
    launcher=game/('Moonstone.cmd' if windows else 'Moonstone.sh')
    engine=game/('moonstone-importer.console.exe' if windows else 'moonstone-importer')
    env=os.environ.copy();env.update(PYTHONDONTWRITEBYTECODE='1',OPENBLAS_NUM_THREADS='1',
        MOONSTONE_GAME_DIR=str(game),MOONSTONE_IMPORT_BIN=str(game/'importer/bin'),
        PYTHONPATH=str(game/'importer/project/tools'),
        XDG_DATA_HOME=str(directory/'data'),XDG_CONFIG_HOME=str(directory/'config'),
        XDG_CACHE_HOME=str(directory/'cache'),APPDATA=str(directory/'appdata'))
    for name in ['MOONSTONE_CONTENT_PACK','MOONSTONE_LAUNCHER_PYTHON','MOONSTONE_GAME_ENGINE',
                 'DISPLAY','WAYLAND_DISPLAY']:env.pop(name,None)
    checks=[]
    def run(name, command, *, success=True, marker=None):
        result=subprocess.run(command if isinstance(command,str) else list(map(str,command)),cwd=directory,env=env,capture_output=True,text=True,timeout=120)
        text=result.stdout+result.stderr;(directory/(name+'.log')).write_text(text,encoding='utf-8')
        if (result.returncode==0)!=success or (success and any(line.startswith(('ERROR:','SCRIPT ERROR:')) for line in text.splitlines())) or (marker and marker not in text):
            raise ValueError('Packaged check failed: '+name+'; see '+str(directory/(name+'.log')))
        checks.append(name);return text
    def launch(*args):
        # cmd receives one fully quoted command line; filenames/arguments in
        # this acceptance are generated locally, never shell interpolation.
        if windows:return subprocess.list2cmdline([os.environ.get('COMSPEC','cmd.exe')])+' /d /s /c "'+subprocess.list2cmdline([str(launcher),*map(str,args)])+'"'
        return [launcher,*args]
    files=inspect_pack(game/'moonstone.pck')
    if any(name.startswith(MEDIA_ROOTS) or Path(name).suffix in {'.png','.wav','.ctex','.sample','.exe','.dll'} for name in files):
        raise ValueError('Media/binary in code-only game PCK')
    for name in ['project.godot','.godot/global_script_class_cache.cfg','scripts/presentation/content_mount.gd']:
        if name not in files:raise ValueError('Missing code resource: '+name)
    checks.append('code-only-pack')
    run('launcher-help',launch('--help'),marker='--import-content')
    run('missing-disks',launch('--import-content'),success=False,marker='three IPF')
    run('setup', [engine,'--headless','--audio-driver','Dummy','--','--setup-probe'],marker='SETUP_STATE=')
    source=directory/'synthetic';(source/'game/assets/classic').mkdir(parents=True)
    (source/'game/content/generated').mkdir(parents=True)
    (source/'runtime_media_paths.json').write_text('[]')
    native='''import ctypes,sys,wave,json
from pathlib import Path
import numpy,PIL,import_accel
from PIL import Image
assert import_accel.library() is not None
assert import_accel.lzss_decode(b'\\0example')==b'example'
cap=ctypes.CDLL(str(Path(sys.argv[1])/('capsimg.dll' if sys.platform=='win32' else 'capsimg.so')))
assert cap.CAPSInit()==0
cap.CAPSExit()
root=Path(sys.argv[2]);Image.new('RGBA',(4,4),(12,34,56,255)).save(root/'assets/classic/test.png')
with wave.open(str(root/'assets/classic/test.wav'),'wb') as w:
 w.setnchannels(1);w.setsampwidth(2);w.setframerate(22050);w.writeframes(bytes(4410))
(root/'content/generated/test.json').write_text('{"synthetic":true}')
print('PASS: native Python, NumPy, Pillow, LZSS and CAPSImg')
'''
    run('native-importer',[python,'-B','-c',native,game/'importer/bin',source/'game'],marker='PASS: native')
    content=directory/'portable content';content.mkdir()
    pack=directory/'synthetic.pck'
    run('native-resource-packing',[engine,'--headless','--audio-driver','Dummy','--','--convert',source/'game',pack,directory/'resources'],marker='CONTENT_PACK_FILES=3')
    sha=digest(pack);generation=content/('classic-v1-'+sha[:16]);generation.mkdir()
    (generation/'assets.pck').write_bytes(pack.read_bytes())
    (generation/'manifest.json').write_text(json.dumps({'version':1,'sha256':sha,'startup':'PASS','scope':'synthetic CI fixture, not game content'}))
    (content/'current.json').write_text(json.dumps({'version':1,'sha256':sha,'directory':generation.name}))
    checked_source(content)
    run('install-content',launch('--install-content',content),marker='Content installed')
    run('verify-content',launch('--verify-content'),marker='assets.pck')
    # Same headless verifier used before PortMaster has unpacked Python.
    run('copied-content-bootstrap',[engine,'--headless','--audio-driver','Dummy','--','--verify-content',game],marker='CONTENT_PACK_PATH=')
    exported=directory/'exported content'
    run('export-content',launch('--export-content',exported),marker='Portable content copied')
    pointer,copied=checked_source(exported)
    if digest(copied/'assets.pck')!=sha:raise ValueError('Transfer changed pack bytes')
    old_pointer=(game/'content/current.json').read_bytes()
    run('failed-rebuild-preserves-content',launch('--import-content','--force'),success=False,marker='three IPF')
    if (game/'content/current.json').read_bytes()!=old_pointer:raise ValueError('Failed rebuild changed active content')
    (copied/'assets.pck').write_bytes(b'damaged')
    run('corrupt-transfer-rejected',launch('--install-content',exported),success=False,marker='checksum')
    if (game/'content/current.json').read_bytes()!=old_pointer:raise ValueError('Rejected transfer changed active content')
    execution='wine' if os.environ.get('WINEPREFIX') else 'native'
    result={'result':'PASS','platform':platform,'execution':execution,'archive_sha256':digest(archive),'checks':checks,
            'scope':execution+' packaged launchers, libraries, setup, synthetic resource conversion and content round trip. Original-disk conversion, graphical game and ARM hardware NOT_RUN.',
            'logs':str(directory.relative_to(ROOT))}
    output.parent.mkdir(parents=True,exist_ok=True);output.write_text(json.dumps(result,indent=2)+'\n')
    print('PASS: '+platform+' '+execution+' package acceptance; logs '+str(directory))
    return result


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--platform',choices=['Linux','Windows'],required=True)
    parser.add_argument('--archive',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();verify(args.archive.resolve(),args.platform,args.output.resolve())
