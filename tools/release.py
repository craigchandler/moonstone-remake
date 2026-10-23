#!/usr/bin/env python3
"""Build external-content platform ZIPs and collect a checked release allowlist."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import tarfile
from zipfile import ZipFile
from build_support import ROOT, digest, run, isolated_env, workspace
from package_builds import add_file
from portmaster_content import setup_pack, read_pack, MEDIA_ROOTS
from release_source import build_code_pack
from portmaster_metadata import metadata_files, validate_archive as validate_portmaster_archive
from network_fingerprint import MANIFEST
from campaign_fingerprint import MANIFEST as CAMPAIGN_MANIFEST

PLATFORMS = {'Linux':'x86_64', 'Windows':'windows-x86_64', 'PortMaster':'aarch64'}
SEMVER = r'(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?'


def validate_tag(tag, root=ROOT):
    version=json.loads((root/'game/version.json').read_text())['version']
    if not re.fullmatch(SEMVER, version) or tag!='v'+version:
        raise ValueError('Release tag must be v'+version+', matching game/version.json')
    return version


def importer_files(folder, arch):
    manifest=json.loads((folder/'manifest.json').read_text())
    if manifest.get('arch')!=arch:raise ValueError('Wrong importer architecture')
    rows=[];folded=set()
    for name,sha in manifest['files'].items():
        path=folder/name
        if Path(name).is_absolute() or '..' in Path(name).parts or not path.resolve().is_relative_to(folder.resolve()):
            raise ValueError('Unsafe importer member')
        if name.casefold() in folded or any(c in name for c in '<>:"\\|?*'):raise ValueError('Importer is not FAT/Windows compatible: '+name)
        if digest(path)!=sha:raise ValueError('Importer checksum mismatch: '+name)
        folded.add(name.casefold());rows.append((name,path))
    rows.append(('manifest.json',folder/'manifest.json'))
    return rows


def package(platform, importer, templates, output, tag, *, root=ROOT):
    version=validate_tag(tag, root)
    arch=PLATFORMS[platform]
    rows=importer_files(importer, arch)
    directory=workspace('release-'+platform.lower(),root);stage=directory/'stage';stage.mkdir()
    code,code_files=build_code_pack(root,version)
    if any(name.startswith(MEDIA_ROOTS) or Path(name).suffix in {'.png','.wav','.sample','.ctex'} for name in code_files):
        raise ValueError('Original media entered the code pack')
    (stage/'moonstone.pck').write_bytes(code)
    if platform=='PortMaster':
        (stage/'importer.pck').write_bytes(setup_pack(root))
        def owner(info):
            info.uid=info.gid=0;info.uname=info.gname='';info.mtime=0
            return info
        with tarfile.open(stage/'importer.tar','w',format=tarfile.USTAR_FORMAT,dereference=True) as archive:
            for name,path in rows:archive.add(path,arcname=name,recursive=False,filter=owner)
        (stage/'importer.sha256').write_text(digest(stage/'importer.tar')+'  importer.tar\n')
        shutil.copy2(root/'tools/run_portmaster.sh',stage/'moonstone-run')
    else:
        for name,path in rows:
            target=stage/'importer'/name;target.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(path,target,follow_symlinks=True)
        windows=platform=='Windows';suffix='.exe' if windows else ''
        source=templates/('windows_release_x86_64.exe' if windows else 'linux_release.x86_64')
        if not source.is_file():raise ValueError('Missing official release template: '+str(source))
        for stem in ['moonstone','moonstone-importer']:
            shutil.copy2(source,stage/(stem+suffix));(stage/(stem+suffix)).chmod(0o755)
            if windows:shutil.copy2(templates/'windows_release_x86_64_console.exe',stage/(stem+'.console.exe'))
        (stage/'moonstone-importer.pck').write_bytes(setup_pack(root))
        shutil.copy2(root/'tools/release_launcher.py',stage/'moonstone-launcher.py')
        if windows:
            launch='@echo off\r\n"%~dp0importer\\python\\python.exe" -B "%~dp0moonstone-launcher.py" %*\r\nexit /b %errorlevel%\r\n'
            command='@echo off\r\ncall "%~dp0Moonstone.cmd" --import-content %*\r\nexit /b %errorlevel%\r\n'
            (stage/'Moonstone.cmd').write_bytes(launch.encode());(stage/'Import-Content.cmd').write_bytes(command.encode())
        else:
            launch='#!/usr/bin/env bash\nset -euo pipefail\ntask_dir="$(cd -- "$(dirname -- "$0")" && pwd)"\nexec "$task_dir/importer/python/bin/python3.14" -B "$task_dir/moonstone-launcher.py" "$@"\n'
            command='#!/usr/bin/env bash\nset -euo pipefail\ntask_dir="$(cd -- "$(dirname -- "$0")" && pwd)"\nexec "$task_dir/Moonstone.sh" --import-content "$@"\n'
            (stage/'Moonstone.sh').write_text(launch);(stage/'Moonstone.sh').chmod(0o755)
            (stage/'Import-Content.sh').write_text(command);(stage/'Import-Content.sh').chmod(0o755)
    (stage/'disks').mkdir();(stage/'content').mkdir()
    readme='README.md' if platform=='PortMaster' else 'README.txt'
    (stage/'disks/PUT-YOUR-DISKS-HERE.txt').write_text('Supply your own supported retail images:\nMoonstone_DiskA.ipf\nMoonstone_DiskB.ipf\nMoonstone_DiskC.ipf\n\nOr copy a verified content folder from another Moonstone platform. See '+readme+'.\n')
    (stage/'content/PUT-CONTENT-HERE.txt').write_text('Copy current.json and its classic-v1-<checksum> directory here. Do not nest another content directory. See '+readme+'.\n')
    if platform=='PortMaster':
        for name,data in metadata_files(root).items():(stage/name).write_bytes(data)
    else:
        for name in ['releases.md','importing.md','portmaster.md','portmaster-readme.md','portmaster-testing.md','player-guide.md','asset-policy.md','server-guide.md']:
            target=stage/'docs'/name;target.parent.mkdir(exist_ok=True);shutil.copy2(root/'docs'/name,target)
        for source,target in [('docs/releases.md','README.txt'),('LICENSE','SOURCE-LICENSE.txt'),('THIRD_PARTY.md','ATTRIBUTION.txt')]:shutil.copy2(root/source,stage/target)
    # Notices come from the matching official editor, rather than copied from a
    # previously provisioned private export.
    editor=Path(os.environ.get('GODOT_BIN',root/'work/server-toolchain/Godot_v4.6.1-stable_linux.x86_64'))
    if not editor.is_file():raise ValueError('Install the pinned Godot toolchain or set GODOT_BIN')
    notices=stage/'licenses'
    notice_project=directory/'notice-project';notice_project.mkdir()
    (notice_project/'project.godot').write_text('config_version=5\n')
    run([editor,'--headless','--path',notice_project,'--script',root/'tools/godot_notices.gd','--',notices],directory/'notices.log',env=isolated_env(directory))
    if platform=='PortMaster':
        for source,target in [('LICENSE','SOURCE-LICENSE.txt'),('THIRD_PARTY.md','ATTRIBUTION.txt')]:
            shutil.copy2(root/source,notices/target)
        # Expose bundled dependency notices without requiring a first-run unpack.
        for name,path in rows:
            if name.startswith('licenses/') or any(word in Path(name).name.lower() for word in ['license','licence','copying','copyright']):
                target=notices/'importer'/name
                target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(path,target)
    report={'version':version,'platform':platform,'tag':tag,'code_sha256':hashlib.sha256(code).hexdigest(),
            'compatibility':json.loads(code_files[MANIFEST])['digest'],
            'campaign_compatibility':json.loads(code_files[CAMPAIGN_MANIFEST])['digest'],
            'code_files':len(code_files),'supplied_original_media_files':0,'content_version':1,
            'importer_manifest_sha256':digest(importer/'manifest.json'),
            'runtime_acceptance':'NOT_RUN','stage':str(stage.relative_to(root))}
    if platform=='PortMaster':report['documentation_images']=['screenshot.png','muos-thumbnail.png']
    if platform!='PortMaster':
        (stage/'build-manifest.json').write_text(json.dumps(report,indent=2)+'\n')
    output.mkdir(parents=True,exist_ok=True)
    archive_path=output/f'Moonstone-{version}-{platform}.zip'
    with ZipFile(archive_path,'w') as archive:
        if platform=='PortMaster':add_file(archive,'Moonstone.sh',(root/'tools/launch_portmaster.sh').read_bytes(),0o755)
        for path in sorted(stage.rglob('*')):
            if not path.is_file():continue
            relative=path.relative_to(stage).as_posix()
            name=('moonstone/' if platform=='PortMaster' else '')+relative
            mode=0o755 if path.suffix=='.sh' or path.name=='moonstone-run' or (platform=='Linux' and os.access(path,os.X_OK)) else 0o644
            add_file(archive,name,path.read_bytes(),mode)
    with ZipFile(archive_path) as archive:
        if archive.testzip():raise ValueError('Release ZIP integrity failure')
    if platform=='PortMaster':report['portmaster_package']=validate_portmaster_archive(archive_path)
    report.update(archive=archive_path.name,sha256=digest(archive_path))
    (output/f'{platform}-build.json').write_text(json.dumps(report,indent=2)+'\n')
    print('PASS: external-content '+platform+' ZIP: '+str(archive_path));return stage


def collect(source, destination, tag, root=ROOT):
    version=validate_tag(tag,root)
    expected={f'Moonstone-{version}-{platform}.zip' for platform in PLATFORMS}
    server_version=json.loads((root/'game/server/version.json').read_text())['version']
    server_names={f'Moonstone-Duel-Server-{server_version}-{platform}.zip' for platform in ['Linux','Windows']}
    paths=[]
    for name in sorted(expected|server_names):
        matches=list(source.rglob(name))
        if len(matches)!=1:raise ValueError('Expected exactly one release archive: '+name)
        with ZipFile(matches[0]) as archive:
            if archive.testzip():raise ValueError('Damaged release ZIP: '+name)
        paths.append(matches[0])
    # Require each platform's source/package check and Linux/Windows native CI
    # acceptance, not merely the existence of files named *.zip.
    game_reports=[]
    for platform in PLATFORMS:
        records=list(source.rglob(platform+'-build.json'))
        if len(records)!=1:raise ValueError('Missing unique build report: '+platform)
        report=json.loads(records[0].read_text())
        path=next(p for p in paths if p.name==report['archive'])
        if (report['tag']!=tag or report.get('version')!=version or report.get('platform')!=platform
                or report['archive']!=f'Moonstone-{version}-{platform}.zip'
                or report['sha256']!=digest(path) or report['supplied_original_media_files']!=0):raise ValueError('Build report mismatch: '+platform)
        game_reports.append(report)
        paths.append(records[0])
    for platform in ['Linux','Windows']:
        records=list(source.rglob(platform+'-acceptance.json'))
        if len(records)!=1:raise ValueError('Missing native acceptance: '+platform)
        report=json.loads(records[0].read_text())
        archive=next(p for p in paths if p.name==f'Moonstone-{version}-{platform}.zip')
        if report.get('result')!='PASS' or report.get('execution')!='native' or report.get('platform')!=platform or report.get('archive_sha256')!=digest(archive):raise ValueError('Stale, non-native or failed acceptance: '+platform)
        paths.append(records[0])
    for name in ['duel-server-build-manifest.json','duel-server-verification.json']:
        records=list(source.rglob(name))
        if len(records)!=1:raise ValueError('Missing server evidence: '+name)
        paths.append(records[0])
    server_build=next(p for p in paths if p.name=='duel-server-build-manifest.json')
    server_check=next(p for p in paths if p.name=='duel-server-verification.json')
    server=json.loads(server_build.read_text());verification=json.loads(server_check.read_text())
    if (server['version']!=server_version or server['tag']!='server-v'+server_version
            or verification.get('result')!='PASS' or verification.get('Linux')!='PASS'
            or verification.get('build_manifest_sha256')!=digest(server_build)):
        raise ValueError('Server acceptance does not match this build')
    if {row['platform'] for row in server['builds']}!={'Linux','Windows'} or len(server['builds'])!=2:
        raise ValueError('Expected two server builds')
    if len({r['code_sha256'] for r in game_reports})!=1:
        raise ValueError('Game platforms contain different code packs')
    for report in game_reports:
        if any(report.get(key)!=server.get(key) or not report.get(key) for key in ['compatibility','campaign_compatibility']):
            raise ValueError('Client and server gameplay fingerprints do not match')
    for row in server['builds']:
        path=next(p for p in paths if p.name==f"Moonstone-Duel-Server-{server_version}-{row['platform']}.zip")
        with ZipFile(path) as archive:
            if archive.read('build-manifest.json')!=server_build.read_bytes() or archive.read('verification.json')!=server_check.read_bytes():
                raise ValueError('Server ZIP contains stale evidence')
            for binary in [row]+([row['console_wrapper']] if row['platform']=='Windows' else []):
                if hashlib.sha256(archive.read(Path(binary['file']).name)).hexdigest()!=binary['sha256']:
                    raise ValueError('Server ZIP executable changed')
    destination.mkdir(parents=True,exist_ok=True)
    allowed={p.name for p in paths}|{'SHA256SUMS','release-notes.md'}
    if any(p.name not in allowed for p in destination.iterdir()):raise ValueError('Unexpected files in release output directory')
    for path in paths:shutil.copy2(path,destination/path.name)
    (destination/'SHA256SUMS').write_text(''.join(digest(p)+'  '+p.name+'\n' for p in sorted(destination.iterdir()) if p.name not in {'SHA256SUMS','release-notes.md'}))
    (destination/'release-notes.md').write_text(f'''Moonstone {version}

Linux x86_64, Windows x86_64 and PortMaster ARM64 game packages use external
content generated locally from your own supported original IPF disks. No original
runtime artwork, music, sounds or disk images are included. PortMaster includes
documentation screenshots for its menu/catalogue. First launch opens setup;
command-line import is also available. A generated content folder can be copied
between all three platforms. Read README.txt (moonstone/README.md for PortMaster)
in your ZIP for exact paths/commands. PortMaster uses Moonstone.sh + moonstone/;
muOS users place the launcher in roms/PORTS and the folder in ports on their games
SD card. The PortMaster build is experimental; other CFWs/devices need testing.

The lightweight Linux/Windows server ZIPs need no original content or importer.
Server version: {server_version}. Use clients and servers from this release.

Native Linux and Windows CI checks cover the shipped launchers, importer libraries,
setup entry point and synthetic portable-content round trips. CI never receives
original disks and therefore does not claim a real-disk conversion or graphical
playtest. PortMaster ARM execution remains a separate physical-device check.
Verify downloaded ZIPs against SHA256SUMS. All packages include instructions,
attribution and their relevant dependency notices.
''')
    return destination


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tag',required=True)
    parser.add_argument('--validate-only',action='store_true')
    parser.add_argument('--platform',choices=PLATFORMS)
    parser.add_argument('--importer',type=Path)
    parser.add_argument('--templates',type=Path,default=Path(os.environ.get('GODOT_TEMPLATES_DIR',ROOT/'work/server-toolchain/templates')))
    parser.add_argument('--output',type=Path,default=ROOT/'outputs/release-build')
    parser.add_argument('--collect',type=Path)
    args=parser.parse_args();validate_tag(args.tag)
    if args.validate_only:print('PASS: release tag matches game/version.json')
    elif args.collect:print(collect(args.collect.resolve(),args.output.resolve(),args.tag))
    elif args.platform and args.importer:package(args.platform,args.importer.resolve(),args.templates.resolve(),args.output.resolve(),args.tag)
    else:parser.error('Select --validate-only, --collect DIRECTORY, or --platform with --importer')
