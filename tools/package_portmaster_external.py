#!/usr/bin/env python3
"""Package code and import tools only; original game media never enter this ZIP."""
import argparse
import json
from pathlib import Path
import shutil
import tarfile
from zipfile import ZipFile

from build_support import ROOT, config, digest, workspace
from package_builds import add_file
from package_portmaster import extract_pack
from portmaster_content import read_pack, split_pack, write_pack, setup_pack, CONTENT_VERSION


def package(importer, output):
    settings=config()
    manifest_path=ROOT/'outputs'/(settings['artifact_id']+'-build-manifest.json')
    manifest=json.loads(manifest_path.read_text())
    accepted=json.loads((ROOT/'outputs'/(settings['artifact_id']+'-verification.json')).read_text())
    if accepted.get('result')!='PASS' or accepted['build_manifest_sha256']!=digest(manifest_path):raise ValueError('An accepted matching desktop export is required')
    entry=next(row for row in manifest['builds'] if row['platform']=='Linux')
    binary=ROOT/entry['file']
    if not binary.resolve().is_relative_to((ROOT/'outputs').resolve()) or digest(binary)!=entry['sha256']:raise ValueError('Desktop export checksum mismatch')
    helper=json.loads((importer/'manifest.json').read_text())
    if helper['arch']!='aarch64':raise ValueError('Handheld package requires the ARM64 importer')
    for name,expected in helper['files'].items():
        file=importer/name
        if not file.resolve().is_relative_to(importer.resolve()) or digest(file)!=expected:raise ValueError('Importer checksum mismatch: '+name)
    directory=workspace('portmaster-external');stage=directory/'moonstone';stage.mkdir()
    original,_=extract_pack(binary.read_bytes())
    core,media=split_pack(read_pack(original))
    # The media dictionary is used only to prove partitioning; it is not written
    # into the distribution. Users generate a fresh pack from their own disks.
    if 'scripts/presentation/content_mount.gd.remap' not in core:raise ValueError('Export lacks the early content loader')
    (stage/'moonstone.pck').write_bytes(write_pack(core))
    (stage/'importer.pck').write_bytes(setup_pack(ROOT))
    def owner(info):
        info.uid=info.gid=0;info.uname=info.gname='';info.mtime=0
        return info
    # muOS games cards can be FAT/exFAT: store ordinary files, never symlinks or
    # hardlinks, and reject names those case-insensitive filesystems cannot keep.
    folded=set()
    for name in helper['files']:
        if name.casefold() in folded or any(c in name for c in '<>:"\\|?*'):
            raise ValueError('Importer path is not FAT/exFAT compatible: '+name)
        folded.add(name.casefold())
    # Avoid relying on optional gzip/PAX support in the firmware's BusyBox tar.
    # The outer ZIP still compresses the distribution for download.
    with tarfile.open(stage/'importer.tar','w',format=tarfile.USTAR_FORMAT,dereference=True) as archive:
        for name in sorted([*helper['files'],'manifest.json']):archive.add(importer/name,arcname=name,recursive=False,filter=owner)
    (stage/'importer.sha256').write_text(digest(stage/'importer.tar')+'  importer.tar\n')
    for source,target in [('tools/run_portmaster.sh','moonstone-run.sh'),('tools/portmaster.gptk','moonstone.gptk'),
                          ('docs/portmaster.md','READ-ME.txt'),('docs/asset-policy.md','ASSET-POLICY.txt'),('LICENSE','LICENSE.txt'),('THIRD_PARTY.md','THIRD-PARTY.txt')]:
        shutil.copy2(ROOT/source,stage/target)
    (stage/'NOTICES.txt').write_text('''Moonstone remake — code and original-data importer

No original disk images, recovered artwork, fonts, music or sound effects are
supplied. Provide your own supported original data for one-time local conversion.
Original Moonstone content remains the property of its respective rights holders.

New game/importer source is MIT licensed. Godot notices accompany this package.
The separately licensed CAPSImg and Moonstone ACE helpers are included in the
importer archive with their notices and source. Their noncommercial restrictions
remain in force; they are not relicensed as MIT. Python, NumPy and Pillow retain
their included upstream licences. See THIRD-PARTY.txt and importer/licenses.
''')
    licenses=stage/'licenses';licenses.mkdir()
    for name in ['GODOT-COPYRIGHT.txt','GODOT-LICENSE.txt']:
        notice=ROOT/manifest['notices']/name
        if not notice.resolve().is_relative_to((ROOT/'outputs').resolve()):raise ValueError('Unexpected engine notice path')
        shutil.copy2(notice,licenses/name)
    (stage/'override.cfg').write_text('[display]\nwindow/stretch/aspect="keep"\n')
    (stage/'disks').mkdir()
    (stage/'disks/PUT-YOUR-DISKS-HERE.txt').write_text('Supply your own supported original images:\nMoonstone_DiskA.ipf\nMoonstone_DiskB.ipf\nMoonstone_DiskC.ipf\n\nThey are read only. No disk images or converted game content are supplied.\n')
    report={'result':'PASS: code/media partition and package checksums','content_version':CONTENT_VERSION,
            'binary_sha256':digest(binary),'code_sha256':digest(stage/'moonstone.pck'),'code_files':len(core),
            'excluded_media_files':len(media),'supplied_original_media_files':0,'importer_manifest_sha256':digest(importer/'manifest.json'),
            'logs':str(directory.relative_to(ROOT)),
            'limits':{'ARM_import_execution':'NOT_RUN','hardware_import_time_and_memory':'NOT_RUN'}}
    (stage/'verification.json').write_text(json.dumps(report,indent=2)+'\n')
    output.mkdir(parents=True,exist_ok=True)
    archive_path=output/'Moonstone-RG40XXH-External-Assets.zip'
    with ZipFile(archive_path,'w') as archive:
        add_file(archive,'roms/PORTS/Moonstone.sh',(ROOT/'tools/launch_portmaster.sh').read_bytes(),0o755)
        for path in sorted(stage.rglob('*')):
            if path.is_file():add_file(archive,'ports/moonstone/'+str(path.relative_to(stage)),path.read_bytes(),0o755 if path.suffix=='.sh' else 0o644)
    with ZipFile(archive_path) as archive:
        if archive.testzip():raise ValueError('ZIP corruption')
    (output/'SHA256SUMS.txt').write_text(digest(archive_path)+'  '+archive_path.name+'\n')
    shutil.copy2(stage/'verification.json',output/'verification.json')
    print('PASS: no original media supplied; '+str(archive_path.relative_to(ROOT)))
    return stage


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--importer',type=Path,required=True)
    parser.add_argument('--output',type=Path,default=ROOT/'outputs/portmaster-external')
    args=parser.parse_args()
    package(args.importer.resolve(),args.output.resolve())
