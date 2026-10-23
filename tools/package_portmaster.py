#!/usr/bin/env python3
"""Package a verified desktop build's unchanged Godot PCK for local PortMaster use."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import urllib.request
from zipfile import ZipFile

from build_support import ROOT, config, digest, isolated_env, run, workspace
from package_builds import NOTICES, add_file


def extract_pack(binary):
    """Godot 4.6 PCK v3 offsets are relative, including in embedded exports.

    See godotengine/godot 4.6.1-stable core/io/file_access_pack.cpp.
    Restrict this to ordinary complete, unencrypted v3 packs. Verify each payload.
    """
    if len(binary) < 116 or binary[-4:] != b'GDPC':
        raise ValueError('No embedded Godot PCK footer.')
    size = struct.unpack_from('<Q', binary, len(binary) - 12)[0]
    start = len(binary) - 12 - size
    if start < 0 or size < 104:
        raise ValueError('Invalid embedded PCK length.')
    pack = binary[start:-12]
    magic, version, major, minor, patch, flags, base, directory = struct.unpack_from('<4sIIIIIQQ', pack)
    if magic != b'GDPC' or version != 3 or flags != 2 or (major, minor) != (4, 6):
        raise ValueError('Only ordinary, relative-offset Godot 4.6 PCK v3 exports are supported.')
    if not 104 <= base <= directory <= len(pack) - 4:
        raise ValueError('Invalid PCK offsets.')
    count = struct.unpack_from('<I', pack, directory)[0]
    if not 1 <= count <= 100000:
        raise ValueError('Invalid PCK file count.')
    offset = directory + 4
    names = set()
    for _ in range(count):
        if offset + 4 > len(pack):
            raise ValueError('Truncated PCK directory.')
        length = struct.unpack_from('<I', pack, offset)[0]
        offset += 4
        if not 1 <= length <= 4096 or offset + length + 36 > len(pack):
            raise ValueError('Invalid PCK path length.')
        name = pack[offset:offset + length].rstrip(b'\0').decode('utf-8')
        offset += length
        position, length, checksum, file_flags = struct.unpack_from('<QQ16sI', pack, offset)
        offset += 36
        if name in names or '..' in Path(name).parts or file_flags:
            raise ValueError('Unsupported PCK entry: ' + name)
        names.add(name)
        if Path(name).suffix.lower() in {'.so', '.dll', '.dylib', '.gdextension'}:
            raise ValueError('Native extension requires an ARM port: ' + name)
        if base + position + length > directory:
            raise ValueError('PCK payload outside data area: ' + name)
        payload = pack[base + position:base + position + length]
        if hashlib.md5(payload).digest() != checksum:
            raise ValueError('PCK payload checksum failed: ' + name)
    if not {'project.binary', 'res://project.binary'} & names:
        raise ValueError('Pack has no project.binary.')
    return pack, {'engine': f'{major}.{minor}.{patch}', 'files': count,
                  'payload_checksums': 'PASS', 'native_extensions': 0,
                  'embedded_pack_offset': start}


def runtime_files(cache, fetch):
    lock = json.loads((ROOT / 'tools/portmaster-runtimes.json').read_text())
    for entry in lock['files']:
        path = cache / entry['name']
        if not path.is_file() and fetch:
            cache.mkdir(parents=True, exist_ok=True)
            temporary = path.with_suffix('.download')
            print('Downloading ' + entry['name'], flush=True)
            with urllib.request.urlopen(entry['url'], timeout=120) as source, temporary.open('wb') as dest:
                shutil.copyfileobj(source, dest)
            if digest(temporary) != entry['sha256']:
                temporary.unlink()
                raise ValueError('Runtime checksum mismatch: ' + entry['name'])
            os.replace(temporary, path)
        if not path.is_file() or digest(path) != entry['sha256']:
            raise ValueError('Missing or mismatched runtime: ' + str(path) + '; use --fetch-runtimes.')
    return lock


def acceptance(runtime, pack, directory):
    env = isolated_env(directory)
    checks = {}
    golden = json.loads((ROOT / 'game/tests/fixtures/combat_traces.json').read_text())
    for label, arguments, prefix in [
        ('startup', ['--smoke'], 'LAUNCH_MODE_STATE='),
        ('controllers', ['--debug', '--controller-probe'], 'CONTROLLER_STATE='),
        ('practice', ['--debug', '--practice-probe'], 'PRACTICE_STATE='),
        ('layers', ['--debug', '--layered-graphics-probe'], 'LAYERED_GRAPHICS_STATE='),
        ('debug-guard', ['--debug', '--debug-mode-probe'], 'DEBUG_MODE_STATE='),
    ]:
        output = run([runtime, '--headless', '--audio-driver', 'Dummy', '--fixed-fps', '50',
                      '--main-pack', pack, '--', *arguments], directory / (label + '.log'),
                     env=env, cwd=directory, timeout=90)
        if 'PASS:' not in output:
            raise ValueError('No completion marker: ' + label)
        state = json.loads(next(line[len(prefix):] for line in output.splitlines() if line.startswith(prefix)))
        if state.get('failures'):
            raise ValueError('Runtime probe failed: ' + label)
        if label == 'controllers' and state['session_traces'] != golden['session_traces']:
            raise ValueError('Combat traces changed under the PortMaster runtime.')
        if label == 'practice' and (len(state['replays']) != 12 or state['file_isolation'] != 'PASS'):
            raise ValueError('Practice coverage or save isolation failed.')
        checks[label] = state
        print('PASS: desktop PortMaster runtime / ' + label, flush=True)
    return checks


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runtime-cache', type=Path, default=ROOT / 'work/portmaster-runtimes')
    parser.add_argument('--fetch-runtimes', action='store_true', help='Download pinned public ARM and desktop test runtimes.')
    parser.add_argument('--graphical', action='store_true', help='Also capture desktop GLES rendering at 640x480; requires X11.')
    args = parser.parse_args()
    settings = config()
    manifest_path = ROOT / 'outputs' / (settings['artifact_id'] + '-build-manifest.json')
    manifest = json.loads(manifest_path.read_text())
    verified = json.loads((ROOT / 'outputs' / (settings['artifact_id'] + '-verification.json')).read_text())
    if verified.get('result') != 'PASS' or verified.get('build_manifest_sha256') != digest(manifest_path):
        raise ValueError('A matching accepted desktop build is required; run tools/build.sh first.')
    build = next(row for row in manifest['builds'] if row['platform'] == 'Linux')
    binary = (ROOT / build['file']).resolve()
    if not binary.is_relative_to((ROOT / 'outputs').resolve()) or digest(binary) != build['sha256']:
        raise ValueError('Desktop binary does not match its accepted build.')
    cache = args.runtime_cache.resolve()
    lock = runtime_files(cache, args.fetch_runtimes)
    directory = workspace('portmaster')
    stage = directory / 'moonstone'
    stage.mkdir()
    pack_bytes, pack_info = extract_pack(binary.read_bytes())
    pack = stage / 'moonstone.pck'
    pack.write_bytes(pack_bytes)
    # Only the desktop runtime is extracted on the build host. ARM archives stay intact.
    runtime_dir = directory / 'runtime'
    run(['7z', 'x', '-y', '-o' + str(runtime_dir), cache / 'godot_4.6.3.x86_64.squashfs'], directory / 'runtime-extract.log')
    runtime = runtime_dir / 'godot463.x86_64'
    runtime.chmod(0o755)
    version = subprocess.check_output([runtime, '--version'], text=True).strip()
    if not version.startswith('4.6.3.'):
        raise ValueError('Unexpected PortMaster test runtime version: ' + version)
    checks = acceptance(runtime, pack, directory)
    graphical = 'NOT_RUN'
    if args.graphical:
        capture = directory / 'battle-640x480.png'
        run([runtime, '--display-driver', 'x11', '--rendering-method', 'gl_compatibility',
             '--rendering-driver', 'opengl3_es', '--audio-driver', 'Dummy', '--resolution', '640x480',
             '--main-pack', pack, '--', '--debug', '--balok', '--capture=' + str(capture)],
            directory / 'graphical.log', env=isolated_env(directory / 'graphical'), cwd=stage, timeout=45)
        if not capture.is_file():
            raise ValueError('Desktop graphical capture was not produced.')
        graphical = {'result': 'PASS: desktop GLES capture; not handheld validation',
                     'capture': str(capture.relative_to(ROOT)), 'sha256': digest(capture)}
    notices = stage / 'licenses'
    run([runtime, '--headless', '--main-pack', pack, '--script', ROOT / 'tools/godot_notices.gd', '--', notices],
        directory / 'notices.log', env=isolated_env(directory), cwd=directory)
    for source, target in [('LICENSE', 'licenses/MOONSTONE-SOURCE.txt'), ('docs/asset-policy.md', 'ASSET-POLICY.txt'),
                           ('docs/player-guide.md', 'PLAYER-GUIDE.txt'), ('docs/portmaster.md', 'READ-ME.txt')]:
        shutil.copy2(ROOT / source, stage / target)
    (stage / 'NOTICES.txt').write_text(NOTICES)
    shutil.copy2(ROOT / 'tools/run_portmaster.sh', stage / 'moonstone-run.sh')
    shutil.copy2(ROOT / 'tools/portmaster.gptk', stage / 'moonstone.gptk')
    # External project overrides affect presentation only, never simulation ticks.
    (stage / 'override.cfg').write_text('[display]\nwindow/stretch/aspect="keep"\n')
    report = {'result': 'PASS: packaging and desktop runtime probes', 'binary_sha256': digest(binary),
              'pck_sha256': digest(pack), 'pack': pack_info, 'runtime': version,
              'checks': checks, 'desktop_graphical': graphical, 'logs': str(directory.relative_to(ROOT)),
              'limits': {'ARM_execution': 'NOT_RUN', 'RG40XXH_muOS_graphics_audio_controls_performance': 'NOT_RUN',
                         'network_cross_version': 'NOT_RUN', 'Windows': 'NOT_RUN', 'original_game_comparison': 'NOT_RUN'}}
    (stage / 'verification.json').write_text(json.dumps(report, indent=2) + '\n')
    (stage / 'runtime-sources.json').write_text(json.dumps(lock, indent=2) + '\n')
    launcher = (ROOT / 'tools/launch_portmaster.sh').read_bytes()
    run(['bash', '-n', ROOT / 'tools/launch_portmaster.sh'], directory / 'launcher-syntax.log')
    output = ROOT / 'outputs/portmaster'
    output.mkdir(exist_ok=True)
    archives = []
    for name, launch_path, game_path in [
        ('Moonstone-RG40XXH-muOS.zip', 'roms/PORTS/Moonstone.sh', 'ports/moonstone'),
        ('moonstone.zip', 'Moonstone.sh', 'moonstone'),
    ]:
        target = directory / name
        with ZipFile(target, 'w') as archive:
            add_file(archive, launch_path, launcher, 0o755)
            for path in sorted(stage.rglob('*')):
                if path.is_file():
                    add_file(archive, game_path + '/' + path.relative_to(stage).as_posix(), path.read_bytes(),
                             0o755 if path.suffix == '.sh' else 0o644)
        with ZipFile(target) as archive:
            if archive.testzip() is not None:
                raise ValueError('ZIP integrity check failed: ' + name)
        archives.append(target)
    artwork = directory / 'Moonstone-muOS-Artwork.zip'
    thumbnail = directory / 'Moonstone.png'
    run([runtime, '--headless', '--main-pack', pack, '--script', ROOT / 'tools/portmaster_art.gd',
         '--', ROOT / 'docs/screenshots/battle.png', thumbnail], directory / 'artwork.log',
        env=isolated_env(directory), cwd=directory)
    with ZipFile(artwork, 'w') as archive:
        for kind in ('box', 'preview'):
            add_file(archive, f'MUOS/info/catalogue/External - Ports/{kind}/Moonstone.png',
                     thumbnail.read_bytes())
    archives.append(artwork)
    offline = directory / 'Moonstone-PortMaster-Runtimes-aarch64.zip'
    with ZipFile(offline, 'w') as archive:
        for entry in lock['files']:
            if entry['arch'] == 'aarch64':
                add_file(archive, 'MUOS/PortMaster/libs/' + entry['name'], (cache / entry['name']).read_bytes())
    with ZipFile(offline) as archive:
        if archive.testzip() is not None:
            raise ValueError('Offline runtime ZIP integrity check failed.')
    archives.append(offline)
    for path in archives:
        os.replace(path, output / path.name)
    shutil.copy2(stage / 'READ-ME.txt', output / 'READ-ME.txt')
    shutil.copy2(stage / 'verification.json', output / 'verification.json')
    (output / 'SHA256SUMS.txt').write_text(''.join(digest(output / p.name) + '  ' + p.name + '\n' for p in archives))
    print('PASS: local packages in outputs/portmaster. RG40XX H execution remains NOT_RUN.')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, RuntimeError, OSError, subprocess.SubprocessError) as error:
        raise SystemExit(str(error)) from error
