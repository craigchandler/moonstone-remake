"""Shared build identity, isolated execution and artifact contracts."""
from pathlib import Path
import hashlib
import json
import os
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def config(root=ROOT):
    value = json.loads((root / 'tools/build-config.json').read_text())
    for key in ['artifact_id', 'stem', 'engine_version']:
        if not isinstance(value.get(key), str) or not re.fullmatch(r'[A-Za-z0-9_.-]+', value[key]):
            raise ValueError(f'Invalid build identity: {key}')
    return value


def digest(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def workspace(label, root=ROOT):
    parent = root / 'work'
    parent.mkdir(exist_ok=True)
    return Path(tempfile.mkdtemp(prefix=label + '-', dir=parent))


def isolated_env(directory):
    result = os.environ.copy()
    for key, suffix in [('XDG_DATA_HOME', 'data'), ('XDG_CONFIG_HOME', 'config'), ('XDG_CACHE_HOME', 'cache')]:
        result[key] = str(directory / suffix)
    return result


def run(command, log, *, env=None, cwd=ROOT, timeout=45, allow_editor_socket_errors=False):
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open('w') as stream:
        result = subprocess.run([str(x) for x in command], cwd=cwd, env=env, stdout=stream,
                                stderr=subprocess.STDOUT, timeout=timeout, check=False)
    text = log.read_text(errors='replace')
    errors = [line for line in text.splitlines() if line.startswith(('ERROR:', 'SCRIPT ERROR:'))]
    if allow_editor_socket_errors:
        errors = [line for line in errors if not any(x in line for x in ['"_sock == -1"', '"err != OK"'])]
    if result.returncode or errors:
        raise RuntimeError(f'Check failed; see {log}\n' + '\n'.join(errors[:4]))
    return text


def artifact_path(root, relative):
    path = root / relative
    resolved = path.resolve()
    if not resolved.is_relative_to((root / 'outputs').resolve()) or not path.is_file():
        raise ValueError(f'Artifact must be an existing file in outputs: {relative}')
    return path


def launcher(platform, binary_name, root=ROOT):
    name = 'launch_moonstone.sh' if platform == 'Linux' else 'launch_moonstone.cmd'
    template = (root / 'tools' / name).read_text()
    text = template.replace('@BINARY@', binary_name)
    if '@BINARY@' not in template or '\n' in binary_name or '/' in binary_name or '\\' in binary_name:
        raise ValueError('Invalid launcher template or binary name')
    if platform == 'Windows':
        return text.replace('\r\n', '\n').replace('\n', '\r\n').encode()
    return text.encode()


def godot_binary(settings, root=ROOT):
    selected = os.environ.get('GODOT_BIN')
    bundled = root / 'work' / ('godot-' + settings['engine_version']) / ('Godot_v' + settings['engine_version'] + '-stable_linux.x86_64')
    installed = root / 'work/server-toolchain' / bundled.name
    local = next((path for path in [bundled, installed] if path.is_file()), None)
    binary = Path(selected) if selected else local or Path(shutil.which('godot') or '')
    if not binary.is_file():
        raise RuntimeError('Set GODOT_BIN to the matching Godot editor; see docs/development.md.')
    binary = binary.resolve()
    version = subprocess.check_output([str(binary), '--version'], text=True).strip()
    if not version.startswith(settings['engine_version'] + '.'):
        raise RuntimeError(f'Expected Godot {settings["engine_version"]}; found {version}')
    return binary, version


def stage_templates(settings, env, root=ROOT):
    version = settings['engine_version'] + '.stable'
    explicit = os.environ.get('GODOT_TEMPLATES_DIR')
    candidates = [Path(explicit)] if explicit else [
        Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share')) / 'godot/export_templates' / version,
        Path.home() / '.local/share/godot/export_templates' / version,
    ]
    installed = root / 'work/server-toolchain/templates'
    identity = installed / 'version.txt'
    if not explicit and identity.is_file() and identity.read_text().strip() == version:
        candidates.insert(0, installed)
    source = next((p for p in candidates if (p / 'linux_release.x86_64').is_file() and (p / 'windows_release_x86_64.exe').is_file()), None)
    if source is None:
        raise RuntimeError('Install matching Linux/Windows export templates or set GODOT_TEMPLATES_DIR.')
    target = Path(env['XDG_DATA_HOME']) / 'godot/export_templates' / version
    target.mkdir(parents=True, exist_ok=True)
    for path in source.iterdir():
        if not path.is_file():
            continue
        dest = target / path.name
        try:
            dest.symlink_to(path.resolve())
        except OSError:
            shutil.copy2(path, dest)
    return str(source.resolve())
