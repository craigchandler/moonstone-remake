#!/usr/bin/env python3
"""Fetch pinned build-only dependencies into work/, never original game data."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import tarfile
import tempfile
import urllib.request
from build_support import ROOT, digest


def download(url, path, expected):
    if path.is_file() and digest(path) == expected:return path
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + '.partial')
    try:
        with urllib.request.urlopen(url, timeout=120) as source, temporary.open('wb') as target:
            shutil.copyfileobj(source, target)
        if digest(temporary) != expected:raise ValueError('Dependency checksum mismatch: ' + path.name)
        os.replace(temporary, path)
    finally:temporary.unlink(missing_ok=True)
    return path


def extract_root(archive, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():raise ValueError('Dependency destination already exists: ' + str(destination))
    with tempfile.TemporaryDirectory(prefix='.extract-', dir=destination.parent) as temporary:
        with tarfile.open(archive) as source:source.extractall(temporary, filter='data')
        entries = list(Path(temporary).iterdir())
        if len(entries) != 1 or not entries[0].is_dir():raise ValueError('Expected one dependency root')
        shutil.move(entries[0], destination)


def install(directory, *, compiler=True):
    lock = json.loads((ROOT/'tools/release-toolchain.json').read_text())
    cache = directory/'downloads';upstream = directory/'upstream'
    for row in lock['sources']:
        archive = download(row['url'], cache/(row['name']+'.tar.gz'), row['sha256'])
        target = upstream/row['name']
        if not target.exists():
            extract_root(archive, target)
            (target/'SOURCE_REVISION').write_text(row['revision']+'\n')
            (target/'SOURCE_ARCHIVE_SHA256').write_text(row['sha256']+'\n')
        if (target/'SOURCE_REVISION').read_text().strip()!=row['revision'] or (target/'SOURCE_ARCHIVE_SHA256').read_text().strip()!=row['sha256']:
            raise ValueError('Dependency directory does not match the pinned source: '+row['name'])
    if compiler:
        row = lock['zig'];target = directory/('zig-'+lock['zig_version'])
        archive = download(row['url'], cache/'zig.tar.xz', row['sha256'])
        if not target.exists():extract_root(archive, target)
        if 'GITHUB_PATH' in os.environ:
            with Path(os.environ['GITHUB_PATH']).open('a') as stream:stream.write(str(target.resolve())+'\n')
        print('Zig compiler directory: '+str(target.resolve()))
    print('Pinned importer sources: '+str(upstream.resolve()))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, default=ROOT/'work/release-toolchain')
    parser.add_argument('--skip-compiler', action='store_true')
    args=parser.parse_args();install(args.directory.resolve(), compiler=not args.skip_compiler)
