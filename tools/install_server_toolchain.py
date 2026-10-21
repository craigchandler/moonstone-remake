#!/usr/bin/env python3
"""Install checksum-pinned official Linux Godot and release templates under work/."""
import hashlib
import json
import os
from pathlib import Path
import platform
import urllib.request
from zipfile import ZipFile
from build_support import ROOT, config


def sha512(path):
    with path.open('rb') as stream:return hashlib.file_digest(stream, 'sha512').hexdigest()


def download(url, path, expected):
    if not path.is_file() or sha512(path) != expected:
        partial = path.with_suffix(path.suffix + '.partial')
        with urllib.request.urlopen(url, timeout=120) as response, partial.open('wb') as output:
            while block := response.read(1024 * 1024):output.write(block)
        if sha512(partial) != expected:raise ValueError('Official toolchain checksum mismatch: ' + path.name)
        os.replace(partial, path)
    return path


def main():
    if platform.system() != 'Linux' or platform.machine() != 'x86_64':
        raise SystemExit('This CI toolchain installer requires Linux x86_64.')
    settings = json.loads((ROOT / 'tools/server-toolchain.json').read_text())
    if settings['version'] != config()['engine_version']:
        raise ValueError('Server toolchain must match the game engine version.')
    directory = ROOT / 'work/server-toolchain'
    directory.mkdir(parents=True, exist_ok=True)
    version = settings['version']
    editor_name = f'Godot_v{version}-stable_linux.x86_64'
    editor = directory / editor_name
    templates = directory / 'templates'
    templates.mkdir(exist_ok=True)
    wanted = {'linux_release.x86_64', 'windows_release_x86_64.exe', 'windows_release_x86_64_console.exe', 'version.txt'}
    for name, checksum in settings['archives'].items():
        archive = download(settings['base_url'] + name, directory / name, checksum)
        with ZipFile(archive) as source:
            if name.endswith('.zip'):
                editor.write_bytes(source.read(editor_name));editor.chmod(0o755)
            else:
                for item in sorted(wanted):(templates / item).write_bytes(source.read('templates/' + item))
    if (templates / 'version.txt').read_text().strip() != version + '.stable':
        raise ValueError('Official templates report another version.')
    variables = {'GODOT_BIN': str(editor), 'GODOT_TEMPLATES_DIR': str(templates)}
    if 'GITHUB_ENV' in os.environ:
        with Path(os.environ['GITHUB_ENV']).open('a') as output:
            for key, value in variables.items():output.write(key + '=' + value + '\n')
    print('PASS: checksum-pinned Godot ' + version + ' and dedicated-server export templates under work/.')


if __name__ == '__main__':main()
