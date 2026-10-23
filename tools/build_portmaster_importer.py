#!/usr/bin/env python3
"""Build a local, self-contained importer; no original data is a build input."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import re
import urllib.request
from zipfile import ZipFile

from build_support import ROOT, digest
from import_support import require_reference

ACE_PIN='f0d699a2b92d42d5380429ea9f2d94f7534324ef'
CAPS_PIN='ed4cb0912fb1a2a0d5203111c6f6abd50d411b56'


def runtime_media_paths(root):
    # Literal image references in game code supplement references in generated
    # resources. Dynamic lair/colour paths are outside the recovered directory
    # and stay included wholesale. No original data is read to build this list.
    return sorted({value for file in (root/'game').rglob('*.gd')
                   for value in re.findall(r'res://assets/classic/recovered/[^"\'\s]+\.png',file.read_text())})


def trim_python_runtime(output):
    """Remove development/test tools and duplicate interpreter aliases only."""
    python=output/'python'
    if (python/'python.exe').is_file():
        standard=python/'Lib'
        for name in ['idlelib','tkinter','turtledemo','ensurepip','test']:
            shutil.rmtree(standard/name,ignore_errors=True)
        for name in ['include','libs','Scripts','tcl']:shutil.rmtree(python/name,ignore_errors=True)
        for path in (standard/'site-packages').rglob('tests'):
            if path.is_dir():shutil.rmtree(path)
        # Keep python314.dll, VC runtime DLLs, extension DLLs and all notices.
        return
    for path in (python/'bin').iterdir():
        if path.name!='python3.14':path.unlink()
    standard=python/'lib/python3.14'
    for name in ['idlelib','tkinter','turtledemo','ensurepip','test','_pyrepl']:
        shutil.rmtree(standard/name,ignore_errors=True)
    for path in standard.glob('config-*'):shutil.rmtree(path)
    site=standard/'site-packages'
    for pattern in ['pip','pip-*.dist-info','numpy/f2py']:
        for path in site.glob(pattern):shutil.rmtree(path)
    for path in list(site.rglob('tests')):
        if path.is_dir():shutil.rmtree(path)
    for path in (standard/'lib-dynload').glob('_tkinter*'):path.unlink()
    for pattern in ['tcl*','tk*','libtcl*']:
        for path in (python/'lib').glob(pattern):
            if path.is_dir():shutil.rmtree(path)
            else:path.unlink()
    for name in ['include','share']:shutil.rmtree(python/name,ignore_errors=True)
    # This pinned standalone interpreter embeds Python. Check every retained
    # ELF dependency before omitting the separately supplied embedding library
    # and its FAT-expanded alias (two redundant 22 MB files on ARM).
    libraries=list((python/'lib').glob('libpython*'))
    embedding_needed=False
    for path in python.rglob('*'):
        if not path.is_file() or path in libraries:continue
        with path.open('rb') as stream:magic=stream.read(4)
        if magic!=b'\x7fELF':continue
        dynamic=subprocess.check_output(['readelf','-d',str(path)],text=True)
        if re.search(r'Shared library: \[libpython',dynamic):embedding_needed=True;break
    if not embedding_needed:
        for path in libraries:path.unlink()


def build(upstream, cache, output, arch, resume=False, fetch=False):
    if output.exists() and not resume:raise ValueError('Use a new importer output directory or --resume this local build')
    ace=upstream/'moonstone-ace';caps=upstream/'capsimg'
    require_reference(ace,ACE_PIN);require_reference(caps,CAPS_PIN)
    lock=json.loads((ROOT/'tools/portmaster-importer-runtimes.json').read_text())
    entries=[row for row in lock['files'] if row['arch']==arch]
    if len(entries)!=3:raise ValueError('Expected pinned Python, NumPy and Pillow runtimes')
    windows=arch=='windows-x86_64'
    for row in entries:
        if not (cache/row['name']).exists() and fetch:
            cache.mkdir(parents=True,exist_ok=True)
            temporary=cache/(row['name']+'.download')
            with urllib.request.urlopen(row['url'],timeout=120) as source,temporary.open('wb') as dest:shutil.copyfileobj(source,dest)
            if digest(temporary)!=row['sha256']:raise ValueError('Download checksum mismatch: '+row['name'])
            os.replace(temporary,cache/row['name'])
        if digest(cache/row['name'])!=row['sha256']:raise ValueError('Runtime checksum mismatch: '+row['name'])
    output.mkdir(parents=True,exist_ok=resume)
    for row in entries:
        if row['kind']=='python':
            with tarfile.open(cache/row['name']) as archive:archive.extractall(output,filter='data')
        else:
            site=output/('python/Lib/site-packages' if windows else 'python/lib/python3.14/site-packages')
            with ZipFile(cache/row['name']) as archive:
                for name in archive.namelist():
                    if Path(name).is_absolute() or '..' in Path(name).parts:raise ValueError('Unsafe wheel path')
                archive.extractall(site)
    project=output/'project'
    (project/'tools').mkdir(parents=True,exist_ok=True)
    for path in ROOT.glob('tools/import_*.py'):shutil.copy2(path,project/'tools'/path.name)
    for path in ROOT.glob('tools/bake_*.cpp'):shutil.copy2(path,project/'tools'/path.name)
    shutil.copy2(ROOT/'tools/import_accel.cpp',project/'tools/import_accel.cpp')
    for name in ['portmaster_import.py','portmaster_content.py','portmaster_convert.gd']:
        shutil.copy2(ROOT/'tools'/name,project/'tools'/name)
    for name in ['game/content/classic_art.tres','LICENSE','THIRD_PARTY.md']:
        dest=project/name;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/name,dest)
    (project/'runtime_media_paths.json').write_text(json.dumps(runtime_media_paths(ROOT))+'\n')
    reference=project/'work/upstream/moonstone-ace'
    reference.mkdir(parents=True,exist_ok=True)
    # Only source modules/facts needed by converters; no original/compiled data.
    for path in (ace/'tools').rglob('*'):
        if path.suffix not in {'.py','.json'} or '__pycache__' in path.parts:continue
        dest=reference/path.relative_to(ace);dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(path,dest)
    shutil.copy2(ace/'LICENSE',reference/'LICENSE')
    (reference/'SOURCE_REVISION').write_text(ACE_PIN+'\n')
    notices=output/'licenses';notices.mkdir(exist_ok=True)
    shutil.copy2(ace/'LICENSE',notices/'MOONSTONE-ACE.txt')
    shutil.copy2(caps/'LICENCE.txt',notices/'CAPSIMG.txt')
    shutil.copy2(ROOT/'LICENSE',notices/'MOONSTONE-IMPORTER.txt')
    # Retain complete CAPS source and the exact reference sources for the native
    # helpers alongside their licences, separate from our MIT source repository.
    caps_config=output/'caps-config';caps_config.mkdir(exist_ok=True)
    (caps_config/'config.h').write_text('// Little-endian target.\n'+('' if windows else '#define HAVE_STRUCT_DIRENT_D_TYPE 1\n'))
    with tarfile.open(output/'helper-sources.tar.gz','w:gz') as archive:
        archive.add(caps,arcname='capsimg',filter=lambda info: None if '.git' in Path(info.name).parts else info)
        archive.add(caps_config/'config.h',arcname='capsimg/CAPSImg/config.h')
        for name in ['include','src/engine/synth.cpp','src/engine/paula.cpp','src/engine/rnc.cpp','src/engine/modplay.cpp','LICENSE']:
            archive.add(ace/name,arcname='moonstone-ace/'+name)
        for path in ROOT.glob('tools/bake_*.cpp'):archive.add(path,arcname='moonstone/'+path.name)
        archive.add(ROOT/'tools/import_accel.cpp',arcname='moonstone/import_accel.cpp')
    binaries=output/'bin';binaries.mkdir(exist_ok=True)
    # Cross-target Linux x86_64 as well: CI-host glibc must not silently raise
    # the minimum glibc of the downloaded portable Python/game runtime.
    compiler=(['x86_64-w64-mingw32-g++'] if windows else
              ['zig','c++','-target',('aarch64' if arch=='aarch64' else 'x86_64')+'-linux-gnu.2.28'])
    env=os.environ.copy();env['ZIG_GLOBAL_CACHE_DIR']=str(output/'build-cache/global');env['ZIG_LOCAL_CACHE_DIR']=str(output/'build-cache/local')
    def compile(name,sources,flags=()):
        if windows:
            name=name.replace('.so','.dll') if name.endswith('.so') else name+'.exe'
            flags=[flag for flag in flags if flag!='-fPIC']+['-static-libgcc','-static-libstdc++','-static']
        with (output/(name+'.build.log')).open('w') as log:
            subprocess.run([*compiler,'-std=c++17','-O2','-s','-ffile-prefix-map='+str(ROOT)+'=.',*flags,*map(str,sources),'-o',str(binaries/name)],env=env,stdout=log,stderr=subprocess.STDOUT,check=True)
        print('Built '+arch+'/'+name,flush=True)
    synth=[ace/'src/engine/synth.cpp',ace/'src/engine/paula.cpp',ROOT/'tools/bake_synth_data.cpp']
    flags=['-I'+str(ace/'include'),'-DMOONSTONE_EXTERNAL_SYNTH']
    compile('import-accel.so',[ROOT/'tools/import_accel.cpp'],['-shared','-fPIC','-O3'])
    compile('bake-audio',[ROOT/'tools/bake_audio.cpp',*synth],flags)
    compile('bake-menu',[ROOT/'tools/bake_menu_music.cpp',*synth],flags)
    compile('bake-module',[ROOT/'tools/bake_ending_music.cpp',*[ace/f'src/engine/{n}.cpp' for n in ['rnc','modplay','paula']]],['-I'+str(ace/'include')])
    names='Codec/CTRawCodec Codec/CTRawCodecDecompressor Codec/DiskEncoding Core/BaseFile Core/BitBuffer Core/CRC Core/DiskFile Core/MemoryFile CAPSImg/CapsAPI CAPSImg/CapsFDCEmulator CAPSImg/CapsFile CAPSImg/CapsFormatMFM CAPSImg/CapsImage CAPSImg/CapsImageStd CAPSImg/CapsLoader CAPSImg/DiskImage CAPSImg/DiskImageFactory CAPSImg/stdafx CAPSImg/StreamCueImage CAPSImg/StreamImage'.split()
    compile('capsimg.so',[caps/(name+'.cpp') for name in names],['-shared','-fPIC','-fno-exceptions','-fno-rtti','-I'+str(caps_config),*[ '-I'+str(caps/name) for name in ['LibIPF','Codec','Core','Device','CAPSImg']]])
    # Build caches/logs are development evidence, not required on the handheld.
    shutil.rmtree(output/'build-cache',ignore_errors=True)
    # This graphical importer does not use terminal emulation. The bundled
    # terminfo database has case-colliding names that cannot live on FAT/exFAT.
    shutil.rmtree(output/'python/share/terminfo',ignore_errors=True)
    trim_python_runtime(output)
    for folder in list(output.rglob('__pycache__')):shutil.rmtree(folder)
    manifest={'version':1,'arch':arch,'ace_revision':ACE_PIN,'caps_revision':CAPS_PIN,'runtimes':entries,
              'files':{str(p.relative_to(output)):digest(p) for p in sorted(output.rglob('*')) if p.is_file() and p.name!='manifest.json' and not p.name.endswith('.build.log')}}
    (output/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--upstream',type=Path,required=True)
    parser.add_argument('--runtime-cache',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--arch',choices=['aarch64','x86_64','windows-x86_64'],required=True)
    parser.add_argument('--resume',action='store_true')
    parser.add_argument('--fetch-runtimes',action='store_true')
    args=parser.parse_args()
    build(args.upstream.resolve(),args.runtime_cache.resolve(),args.output.resolve(),args.arch,args.resume,args.fetch_runtimes)
