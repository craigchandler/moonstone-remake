#!/usr/bin/env python3
"""Build deterministic player ZIPs from current artifacts, independently of review history."""
from pathlib import Path
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED
import argparse
import json
import os
import shutil
import tempfile
from build_support import ROOT, artifact_path, config, digest, launcher

NOTICES = '''Personal Moonstone remake

Original game/artwork/data: Moonstone - A Hard Days Knight (1991), Mindscape,
Rob Anderson and the original credited contributors. Imported original assets
are included only in these local personal builds; see the project's asset policy.

New native Godot code; no Amiga CPU/chipset emulator or original executable is
required during play. Matching Godot and third-party notices accompany this ZIP.
Offline CAPS/ACE import dependencies have separate licences and are not bundled.
No permission to redistribute original content is implied by the source code.
'''


def add_file(package, name, data, mode=0o644):
    info = ZipInfo(name, (1980, 1, 1, 0, 0, 0))
    info.create_system = 3
    info.external_attr = (0o100000 | mode) << 16
    info.compress_type = ZIP_DEFLATED
    package.writestr(info, data, compresslevel=7)


def package_current(root=ROOT):
    settings = config(root)
    output = root / 'outputs'
    manifest_path = output / (settings['artifact_id'] + '-build-manifest.json')
    verification_path = output / (settings['artifact_id'] + '-verification.json')
    manifest = json.loads(manifest_path.read_text())
    verification = json.loads(verification_path.read_text())
    if manifest['stem'] != settings['stem'] or verification.get('result') != 'PASS' or verification.get('build_manifest_sha256') != digest(manifest_path):
        raise ValueError('Current matching build acceptance is required before packaging.')
    inputs = []
    for row in manifest['builds']:
        binary = artifact_path(root, row['file'])
        if digest(binary) != row['sha256']:
            raise ValueError('Stale executable: ' + row['file'])
        inputs.append((row, binary))
    if {row['platform'] for row, _ in inputs} != set(settings['platforms']) or len(inputs) != len(settings['platforms']):
        raise ValueError('Expected exactly one current executable per platform.')
    notices = artifact_path(root, manifest['notices'] + '/GODOT-LICENSE.txt').read_bytes()
    copyright_text = artifact_path(root, manifest['notices'] + '/GODOT-COPYRIGHT.txt').read_bytes()
    guide = (root / settings['guide']).read_bytes()
    policy = (root / 'docs/asset-policy.md').read_bytes()
    (root / 'work').mkdir(exist_ok=True)
    packages = []
    with tempfile.TemporaryDirectory(prefix='package-', dir=root / 'work') as scratch:
        for row, binary in inputs:
            platform = row['platform']
            target = settings['platforms'][platform]
            name = settings['stem'] + '-' + platform + '.zip'
            temporary = Path(scratch) / name
            with ZipFile(temporary, 'w') as package:
                add_file(package, binary.name, binary.read_bytes(), 0o755 if platform == 'Linux' else 0o644)
                add_file(package, target['launcher'], launcher(platform, binary.name, root), 0o755 if platform == 'Linux' else 0o644)
                for filename, data in [('READ ME.txt', guide), ('NOTICES.txt', NOTICES.encode()), ('ASSET-POLICY.txt', policy),
                                       ('GODOT-LICENSE.txt', notices), ('GODOT-COPYRIGHT.txt', copyright_text),
                                       ('build-manifest.json', manifest_path.read_bytes()), ('verification.json', verification_path.read_bytes())]:
                    add_file(package, filename, data)
            with ZipFile(temporary) as package:
                if package.testzip() is not None or package.read(binary.name) != binary.read_bytes():
                    raise ValueError('Package integrity check failed.')
                if any(Path(n).suffix.lower() in ['.adf', '.ipf', '.rom', '.mp4'] for n in package.namelist()):
                    raise ValueError('A player package must not contain originals or historical review videos.')
            packages.append({'platform': platform, 'archive': name, 'sha256': digest(temporary)})
        # All inputs and both packages are checked before replacing deliverables.
        for row in packages:
            os.replace(Path(scratch) / row['archive'], output / row['archive'])
    result = {'stem': settings['stem'], 'build_manifest_sha256': digest(manifest_path), 'packages': packages}
    package_manifest = output / (settings['artifact_id'] + '-package-manifest.json')
    package_manifest.write_text(json.dumps(result, indent=2) + '\n')
    checksummed = [artifact_path(root, row['file']) for row in manifest['builds']]
    checksummed += [output / row['archive'] for row in packages] + [manifest_path, verification_path, package_manifest]
    (output / (settings['artifact_id'] + '-SHA256SUMS.txt')).write_text(''.join(digest(p) + '  ' + p.name + '\n' for p in checksummed))
    return result


def review_bundle(paths, root=ROOT):
    settings = config(root)
    files = [artifact_path(root, str(Path(path).relative_to(root) if Path(path).is_absolute() else Path(path))) for path in paths]
    if len({p.name for p in files}) != len(files):
        raise ValueError('Review filenames must be distinct.')
    target = root / 'outputs' / (settings['stem'] + '-Review.zip')
    with ZipFile(target, 'w', compression=ZIP_DEFLATED) as package:
        for path in files:
            package.write(path, path.name)
    return target


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--review-file', action='append', help='Make a separate optional review ZIP from explicit outputs paths.')
    arguments = parser.parse_args()
    if arguments.review_file:
        print(review_bundle(arguments.review_file))
    else:
        print(json.dumps(package_current(), indent=2))
