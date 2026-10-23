"""Validated portable content copies. No saves, caches, disks or code are copied."""
from pathlib import Path
import json
import os
import re
import shutil
import tempfile
from portmaster_content import CONTENT_VERSION, MEDIA_ROOTS, inspect_pack
from import_platform import installation_lock


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
    resources = inspect_pack(pack)
    if any(not name.startswith((*MEDIA_ROOTS, '.moonstone/')) or Path(name).suffix not in {'.png','.wav','.json','.tres','.res','.remap','.import','.ctex','.sample'} for name in resources):
        raise ValueError('Content pack contains a file outside the media boundary')
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


def install_content(game, source):
    from portmaster_import import atomic_json, digest
    pointer, generation = checked_source(source)
    content = game/'content';content.mkdir(exist_ok=True)
    with installation_lock(content/'install.lock'):
        temporary = Path(tempfile.mkdtemp(prefix='.copy-', dir=content))
        try:
            target = content / pointer['directory']
            if target.exists():
                if target.is_symlink() or (target/'assets.pck').is_symlink() or digest(target/'assets.pck') != pointer['sha256']:
                    raise ValueError('Existing generation has a different checksum or unsafe path')
                report=json.loads((target/'manifest.json').read_text())
                if (target/'manifest.json').is_symlink() or not isinstance(report,dict) or report.get('version')!=1 or report.get('sha256')!=pointer['sha256'] or report.get('startup')!='PASS':
                    raise ValueError('Existing generation has an invalid manifest')
            else:
                for name in ['assets.pck','manifest.json']:shutil.copy2(generation/name, temporary/name)
                if digest(temporary/'assets.pck') != pointer['sha256']:raise ValueError('Content changed while copying')
                os.rename(temporary, target)
            # Manifest names are relative, so the same content folder works on
            # Windows, Linux and PortMaster. Save paths are independent.
            atomic_json(content/'current.json', pointer)
        finally:
            if temporary.exists():shutil.rmtree(temporary)
