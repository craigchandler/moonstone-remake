#!/usr/bin/env python3
"""Build, verify and prepare allowlisted server assets; never publish or tag."""
import argparse
import json
import shutil
from pathlib import Path
from zipfile import ZipFile
from build_support import ROOT, artifact_path, digest, isolated_env, run, workspace
from build_server import build, package
from server_version import validate_tag
from verify_server_release import verify


def collect(packages, root=ROOT):
    report = json.loads((root / 'outputs/duel-server-build-manifest.json').read_text())
    validate_tag(report['tag'], root)
    version = report['version']
    expected = {f'Moonstone-Duel-Server-{version}-{platform}.zip' for platform in ['Linux', 'Windows']}
    if {row['file'].split('/')[-1] for row in packages} != expected or len(packages) != 2:
        raise ValueError('Expected exactly the two versioned dedicated-server archives.')
    inputs = [artifact_path(root, row['file']) for row in packages]
    for path, row in zip(inputs, packages):
        if digest(path) != row['sha256']:raise ValueError('Server package changed after verification.')
    inputs += [root / 'outputs/duel-server-build-manifest.json', root / 'outputs/duel-server-verification.json']
    destination = root / 'outputs/server-release'
    destination.mkdir(exist_ok=True)
    # Refuse stale/unknown inputs instead of uploading an entire output tree.
    allowed = expected | {path.name for path in inputs} | {'SHA256SUMS', 'release-notes.md'}
    if any(path.name not in allowed or not path.is_file() for path in destination.iterdir()):
        raise ValueError('Release directory contains unexpected files; use a fresh checkout.')
    for path in inputs:shutil.copyfile(path, destination / path.name)
    (destination / 'SHA256SUMS').write_text(''.join(digest(path) + '  ' + path.name + '\n' for path in inputs))
    (destination / 'release-notes.md').write_text(f'''Moonstone dedicated server {version}.

This server has its own release version. It hosts one classic campaign for up to
four human knights, or one practice duel for two game clients,
using the same authority as in-game hosting, and includes the built-in classic
combat and campaign gameplay definitions. No artwork, audio or original archives are included.

Duel protocol: 2. Combat fingerprint: `{report['compatibility']}`.
Campaign protocol: 1. Campaign fingerprint: `{report.get('campaign_compatibility', 'unavailable')}`.
Clients must have the same protocol and fingerprint; game and server display
versions do not need to match. Earlier client builds with another fingerprint
must be rebuilt or replaced.

Validation: Linux exported server with two asset-free protocol clients on local
UDP, real combat, rematch, snapshot agreement, room reuse and CLI checks.
Also four asset-free campaign clients, classic turns, map agreement, personal
inventory, pause/reserved-seat reconnect and restart from a server save.
Windows x86_64 is exported with Godot 4.6.1 and its console wrapper; Windows
execution, graphical game playtesting and separate-PC LAN tests are NOT_RUN
by this release workflow. Verify downloads against SHA256SUMS.

Extract the platform ZIP and use Moonstone-Server.sh or Moonstone-Server.cmd.
For a campaign add --campaign --players 2 --save campaign.json (UDP27867).
Each archive contains the hosting guide, source attribution and engine notices.
''')
    return destination


def smoke_package(packages, root=ROOT):
    """Check the shipped Linux launcher from the extracted, self-contained ZIP."""
    row = next(row for row in packages if row['platform'] == 'Linux')
    archive = artifact_path(root, row['file'])
    if digest(archive) != row['sha256']:raise ValueError('Release archive changed.')
    directory = workspace('server-package-check', root)
    with ZipFile(archive) as source:
        for info in source.infolist():
            if Path(info.filename).name != info.filename:
                raise ValueError('Unexpected nested server package member.')
            path = directory / info.filename
            path.write_bytes(source.read(info))
            path.chmod((info.external_attr >> 16) & 0o777)
    env = isolated_env(directory)
    env.pop('DISPLAY', None); env.pop('WAYLAND_DISPLAY', None)
    report = json.loads((directory / 'build-manifest.json').read_text())
    for flag in ['--version', '--help']:
        text = run([directory / 'Moonstone-Server.sh', flag], directory / (flag[2:] + '.log'), env=env, cwd=directory)
        if 'Moonstone duel server ' + report['version'] not in text:
            raise ValueError('Packaged server launcher did not report its version.')
    print('PASS: extracted Linux server ZIP launcher, help and release version.', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tag', required=True)
    parser.add_argument('--validate-only', action='store_true')
    args = parser.parse_args()
    validate_tag(args.tag, ROOT)
    if args.validate_only:
        print('PASS: server tag matches the independent server version.');return
    build(args.tag)
    accepted = verify()
    packages = package(accepted, protocol_release=True)
    smoke_package(packages)
    print('PASS: release assets prepared in ' + str(collect(packages).relative_to(ROOT)))


if __name__ == '__main__':main()
