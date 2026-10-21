#!/usr/bin/env python3
"""Build a minimal dedicated duel host from the game's shared source closure."""
from pathlib import Path
from zipfile import ZipFile
import argparse
import json
import os
import shutil
import tempfile
from build_support import ROOT, artifact_path, config, digest, godot_binary, isolated_env, run, stage_templates, workspace
from network_fingerprint import MANIFEST, manifest
from campaign_fingerprint import MANIFEST as CAMPAIGN_MANIFEST, manifest as campaign_manifest
from package_builds import add_file
from server_version import server_version, validate_tag

PROJECT = '''config_version=5
[application]
config/name="Moonstone Duel Server"
run/main_scene="res://server/duel_server.tscn"
run/flush_stdout_on_print=true
config/features=PackedStringArray("4.6")
[rendering]
renderer/rendering_method="gl_compatibility"
'''


def stage(destination, root=ROOT):
    game = root / 'game'
    compatibility = manifest(game)
    # The client's exact compatibility manifest is retained, but no presentation,
    # artwork, audio, autoloads, original archives or writable caches are copied.
    # Numeric combat definitions remain required gameplay inputs.
    names = set(compatibility['files']) | {MANIFEST, 'server/duel_server.gd', 'server/duel_server.tscn', 'server/version.json'}
    if (game / 'scripts/session/campaign_host.gd').is_file():
        campaign = campaign_manifest(game)
        names.update(campaign['files'])
        names.add(CAMPAIGN_MANIFEST)
    else:
        campaign = None
    for name in sorted(names):
        if name.startswith(('assets/', 'content/generated/')):
            raise ValueError('Dedicated server requires curated source gameplay content: ' + name)
        if Path(name).suffix not in {'.gd', '.tres', '.json', '.tscn'}:
            raise ValueError('Unexpected dedicated-server resource: ' + name)
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(game / name, target)
        uid = game / (name + '.uid')
        if uid.is_file():
            shutil.copyfile(uid, destination / (name + '.uid'))
    (destination / MANIFEST).write_text(json.dumps(compatibility, indent=2) + '\n')
    if campaign is not None:
        (destination / CAMPAIGN_MANIFEST).write_text(json.dumps(campaign, indent=2) + '\n')
    (destination / 'project.godot').write_text(PROJECT.replace('config/name="Moonstone Duel Server"', 'config/name="Moonstone Duel Server"\nconfig/version="' + server_version(root) + '"'))
    presets = (game / 'export_presets.cfg').read_text()
    presets = presets.replace('runnable=true', 'runnable=false\ndedicated_server=true')
    presets = presets.replace('export_filter="all_resources"', 'export_filter="all_resources"\ncustom_features="dedicated_server"')
    presets = presets.replace('[preset.1.options]', '[preset.1.options]\ndebug/export_console_wrapper=2')
    presets += '\n' if not presets.endswith('\n') else ''
    (destination / 'export_presets.cfg').write_text(presets)
    return compatibility, sorted(names)


def build(tag=None):
    release_version = server_version(ROOT)
    if tag is not None:validate_tag(tag, ROOT)
    settings = config()
    editor, version = godot_binary(settings)
    directory = workspace('server-build')
    project = directory / 'project'
    project.mkdir()
    compatibility, names = stage(project)
    env = isolated_env(directory)
    stage_templates(settings, env)
    run([editor, '--headless', '--editor', '--path', project, '--import'], directory / 'import.log', env=env, timeout=180, allow_editor_socket_errors=True)
    output = ROOT / 'outputs'
    output.mkdir(exist_ok=True)
    notices = output / 'duel-server-notices'
    run([editor, '--headless', '--path', project, '--script', ROOT / 'tools/godot_notices.gd', '--', notices], directory / 'notices.log', env=env)
    rows = []
    for platform, target in settings['platforms'].items():
        binary = output / ('Moonstone-Duel-Server-' + target['suffix'])
        run([editor, '--headless', '--path', project, '--export-release', target['preset'], binary], directory / ('export-' + platform + '.log'), env=env, timeout=180, allow_editor_socket_errors=True)
        row = {'platform': platform, 'file': str(binary.relative_to(ROOT)), 'sha256': digest(binary)}
        if platform == 'Windows':
            wrapper = binary.with_suffix('.console.exe')
            if not wrapper.is_file():
                raise RuntimeError('Matching Windows console wrapper is missing.')
            row['console_wrapper'] = {'file': str(wrapper.relative_to(ROOT)), 'sha256': digest(wrapper)}
        rows.append(row)
    linux = output / 'Moonstone-Server.sh'
    linux.write_text('#!/usr/bin/env bash\nset -euo pipefail\ntask_dir="$(cd -- "$(dirname -- "$0")" && pwd)"\nexec "$task_dir/Moonstone-Duel-Server-linux.x86_64" --headless -- "$@"\n')
    linux.chmod(0o755)
    windows = output / 'Moonstone-Server.cmd'
    windows.write_bytes(b'@echo off\r\n"%~dp0Moonstone-Duel-Server-windows.console.exe" --headless -- %*\r\n')
    report = {'version': release_version, 'tag': tag, 'engine': version, 'compatibility': compatibility['digest'], 'resources': names, 'notices': str(notices.relative_to(ROOT)), 'logs': str(directory.relative_to(ROOT)), 'builds': rows, 'runtime_acceptance': 'NOT_RUN'}
    if (project / CAMPAIGN_MANIFEST).is_file():report['campaign_compatibility'] = json.loads((project / CAMPAIGN_MANIFEST).read_text())['digest']
    (output / 'duel-server-build-manifest.json').write_text(json.dumps(report, indent=2) + '\n')
    print('PASS: minimal Linux/Windows server exports; runtime acceptance remains separate. Logs: ' + str(directory.relative_to(ROOT)), flush=True)
    return report



def package(acceptance, root=ROOT, *, protocol_release=False):
    output = root / 'outputs'
    report_path = output / 'duel-server-build-manifest.json'
    report = json.loads(report_path.read_text())
    verified = json.loads(acceptance.read_text())
    settings = config(root)
    if {row['platform'] for row in report['builds']} != set(settings['platforms']) or len(report['builds']) != len(settings['platforms']):
        raise ValueError('Expected exactly one current server executable per platform.')
    linux = next(row for row in report['builds'] if row['platform'] == 'Linux')
    if verified.get('result') != 'PASS' or digest(artifact_path(root, linux['file'])) != verified.get('server_sha256'):
        raise ValueError('Matching exported server acceptance is required before packaging.')
    if report.get('campaign_compatibility') and (verified.get('campaign_compatibility') != report['campaign_compatibility'] or verified.get('campaign', {}).get('result') != 'PASS'):
        raise ValueError('Matching exported campaign-server acceptance is required.')
    if protocol_release:
        validate_tag(report.get('tag'), root)
        if verified.get('kind') != 'server-protocol-release' or verified.get('compatibility') != report['compatibility'] or verified.get('version') != report['version']:
            raise ValueError('Matching asset-free server release acceptance is required.')
    else:
        client_report = json.loads((output / (settings['artifact_id'] + '-build-manifest.json')).read_text())
        client = next(row for row in client_report['builds'] if row['platform'] == 'Linux')
        client_binary = artifact_path(root, client['file'])
        if digest(client_binary) != verified.get('client_sha256') or digest(client_binary) != client['sha256']:
            raise ValueError('Matching exported server and client acceptance is required before packaging.')
    # Validate every platform and input before replacing any previous package.
    inputs = []
    for row in report['builds']:
        binary = artifact_path(root, row['file'])
        if digest(binary) != row['sha256']:
            raise ValueError('Stale server executable.')
        wrapper = None
        if row['platform'] == 'Windows':
            wrapper = artifact_path(root, row['console_wrapper']['file'])
            if digest(wrapper) != row['console_wrapper']['sha256']:
                raise ValueError('Stale Windows console wrapper.')
        launcher = artifact_path(root, 'outputs/' + ('Moonstone-Server.sh' if row['platform'] == 'Linux' else 'Moonstone-Server.cmd'))
        inputs.append((row, binary, launcher, wrapper))
    notices = [(name, artifact_path(root, report['notices'] + '/' + name).read_bytes())
               for name in ['GODOT-LICENSE.txt', 'GODOT-COPYRIGHT.txt']]
    guide = (root / 'docs/server-guide.md').read_bytes()
    attribution = [('SOURCE-LICENSE.txt', (root / 'LICENSE').read_bytes()), ('ATTRIBUTION.txt', (root / 'THIRD_PARTY.md').read_bytes())]
    verification = {'result': 'PASS', 'Linux': 'PASS', 'Windows': 'NOT_RUN',
                    'build_manifest_sha256': digest(report_path), 'acceptance_sha256': digest(acceptance),
                    'scope': verified['scope']}
    verification_bytes = (json.dumps(verification, indent=2) + '\n').encode()
    verification_path = output / 'duel-server-verification.json'
    packages = []
    (root / 'work').mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='server-package-', dir=root / 'work') as scratch:
        for row, binary, launcher, wrapper in inputs:
            platform = row['platform']
            archive = Path(scratch) / ('Moonstone-Duel-Server-' + (report['version'] + '-' if protocol_release else '') + platform + '.zip')
            with ZipFile(archive, 'w') as zipfile:
                mode = 0o755 if platform == 'Linux' else 0o644
                add_file(zipfile, binary.name, binary.read_bytes(), mode)
                add_file(zipfile, launcher.name, launcher.read_bytes(), mode)
                if wrapper:
                    add_file(zipfile, wrapper.name, wrapper.read_bytes())
                add_file(zipfile, 'READ ME.txt', guide)
                for name, data in notices + attribution:
                    add_file(zipfile, name, data)
                add_file(zipfile, 'build-manifest.json', report_path.read_bytes())
                add_file(zipfile, 'verification.json', verification_bytes)
            with ZipFile(archive) as zipfile:
                if zipfile.testzip() is not None or zipfile.read(binary.name) != binary.read_bytes():
                    raise ValueError('Server archive integrity check failed.')
            packages.append({'platform': platform, 'file': 'outputs/' + archive.name, 'sha256': digest(archive)})
        for row in packages:
            os.replace(Path(scratch) / Path(row['file']).name, output / Path(row['file']).name)
    verification_path.write_bytes(verification_bytes)
    (output / 'duel-server-package-manifest.json').write_text(json.dumps({'packages': packages}, indent=2) + '\n')
    files = [artifact_path(root, row['file']) for row in report['builds']] + [artifact_path(root, row['file']) for row in packages]
    files += [artifact_path(root, row['console_wrapper']['file']) for row in report['builds'] if 'console_wrapper' in row]
    files += [report_path, verification_path, output / 'duel-server-package-manifest.json']
    (output / 'duel-server-SHA256SUMS.txt').write_text(''.join(digest(path) + '  ' + path.name + '\n' for path in files))
    print('PASS: accepted Linux and exported Windows server packages; Windows execution remains NOT_RUN.', flush=True)
    return packages


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package', type=Path, help='Package separately accepted server/client exports without rebuilding.')
    parser.add_argument('--tag', help='Require a matching server-vVERSION release tag.')
    args = parser.parse_args()
    if args.package:
        package(args.package)
    else:
        build(args.tag)
