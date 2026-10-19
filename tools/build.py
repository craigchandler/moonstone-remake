#!/usr/bin/env python3
"""Repeatable local source checks, exports, acceptance and lean player packages."""
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from build_support import ROOT, config, digest, godot_binary, isolated_env, run, stage_templates, workspace


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--skip-import', action='store_true', help='Use an already provisioned native asset set.')
    parser.add_argument('--tests-only', action='store_true')
    parser.add_argument('--export-only', action='store_true', help='Reuse a separately verified source tree; no package acceptance claim.')
    args = parser.parse_args()
    if args.tests_only and args.export_only:
        parser.error('Choose tests-only or export-only.')
    settings = config()
    editor, version = godot_binary(settings)
    directory = workspace('build')
    env = isolated_env(directory)
    if not args.skip_import:
        print('Checking one-time native asset imports.', flush=True)
        run(['bash', ROOT / 'tools/import_assets.sh'], directory / 'asset-import.log', env=env, timeout=600)
    run([sys.executable, ROOT / 'tools/network_fingerprint.py'], directory / 'network-fingerprint.log', env=env)
    print('Importing native resources with Godot ' + version, flush=True)
    run([editor, '--headless', '--editor', '--path', ROOT / 'game', '--import'], directory / 'import.log', env=env, timeout=180, allow_editor_socket_errors=True)
    suites = {}
    if not args.export_only:
        for index, path in enumerate(sorted((ROOT / 'game/tests').glob('test_*.gd')), 1):
            command = [editor, '--headless', '--path', ROOT / 'game', '--script', 'res://tests/' + path.name]
            if path.stem == 'test_cleanup':
                command += ['--', '--fixture-dir=' + str(directory / 'fixtures')]
            text = run(command, directory / (path.stem + '.log'), env=env)
            if not re.search(r'^PASS:', text, re.M):
                raise RuntimeError('Suite did not report completion: ' + path.name)
            suites[path.name] = 'PASS'
            if index % 10 == 0:
                print(f'{index} source suites passed.', flush=True)
        run([sys.executable, '-m', 'unittest', 'discover', '-s', 'tools/tests'], directory / 'python-tests.log', env=env)
    report = {'source_suites': suites, 'logs': str(directory.relative_to(ROOT)), 'godot': version}
    if args.tests_only:
        (directory / 'result.json').write_text(json.dumps(report, indent=2) + '\n')
        print(f'PASS: {len(suites)} source suites and build-tool tests. Logs: {directory.relative_to(ROOT)}')
        return
    templates = stage_templates(settings, env)
    outputs = ROOT / 'outputs'
    outputs.mkdir(exist_ok=True)
    notices = outputs / (settings['artifact_id'] + '-notices')
    run([editor, '--headless', '--path', ROOT / 'game', '--script', ROOT / 'tools/godot_notices.gd', '--', notices], directory / 'notices.log', env=env)
    builds = []
    for platform, target in settings['platforms'].items():
        binary = outputs / (settings['stem'] + '-' + target['suffix'])
        print('Exporting ' + platform, flush=True)
        run([editor, '--headless', '--path', ROOT / 'game', '--export-release', target['preset'], binary], directory / ('export-' + platform + '.log'), env=env, timeout=180, allow_editor_socket_errors=True)
        with binary.open('rb') as stream:
            magic = stream.read(4)
        if not (magic == b'\x7fELF' if platform == 'Linux' else magic.startswith(b'MZ')):
            raise RuntimeError('Invalid executable: ' + str(binary))
        builds.append({'platform': platform, 'file': str(binary.relative_to(ROOT)), 'sha256': digest(binary)})
    report.update({'stem': settings['stem'], 'artifact_id': settings['artifact_id'], 'builds': builds,
                   'notices': str(notices.relative_to(ROOT)), 'template_source': templates, 'fixtures': str((directory / 'fixtures').relative_to(ROOT))})
    manifest = outputs / (settings['artifact_id'] + '-build-manifest.json')
    manifest.write_text(json.dumps(report, indent=2) + '\n')
    if args.export_only:
        print('Exports complete; source-suite and package acceptance not run.')
        return
    run([sys.executable, ROOT / 'tools/verify_build.py'], directory / 'acceptance.log', env=env, timeout=180)
    run([sys.executable, ROOT / 'tools/package_builds.py'], directory / 'package.log', env=env, timeout=180)
    print(f'PASS: {len(suites)} source suites, Linux release acceptance, Linux/Windows exports and player ZIPs. Logs: {directory.relative_to(ROOT)}')


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, subprocess.TimeoutExpired) as error:
        raise SystemExit(str(error)) from error
