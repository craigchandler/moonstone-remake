#!/usr/bin/env python3
"""Check approved source/documentation objects without reading private working files."""
from pathlib import Path, PurePosixPath
import argparse
import re
import subprocess
import struct
import zlib

PUBLIC_DOCS = frozenset('architecture.md art-packs.md asset-policy.md development.md importing.md player-guide.md roadmap.md screenshots.md server-guide.md gameplay-packs.md portmaster.md releases.md upstream-sources.json'.split())
PUBLIC_TOOLS = frozenset('build-config.json build.py build.sh build_support.py build_server.py server_version.py verify_server_release.py server_release.py install_server_toolchain.py server-toolchain.json network_fingerprint.py campaign_fingerprint.py verify_campaign.py verify_network.py verify_server.py check_public_tree.py godot_notices.gd import_assets.sh launch_moonstone.sh launch_moonstone.cmd package_builds.py package_portmaster.py launch_portmaster.sh run_portmaster.sh portmaster-runtimes.json portmaster_art.gd portmaster_content.py portmaster_convert.gd portmaster_import.py portmaster_setup.gd portmaster-importer-runtimes.json build_portmaster_importer.py package_portmaster_external.py verify_build.py'.split())
PUBLIC_TOOLS |= frozenset('release.py release_source.py release_launcher.py release-toolchain.json install_release_toolchain.py verify_release.py'.split())
PUBLIC_TOOLS |= frozenset('portmaster_metadata.py portmaster-port.json'.split())
PUBLIC_DOCS |= frozenset(['portmaster-readme.md', 'portmaster-testing.md'])
PUBLIC_SCREENSHOTS = frozenset('docs/screenshots/' + name + '.png' for name in
    'intro main-menu practice-menu world-map battle town-highwood town-waterdeep town-tavern'.split())
PUBLIC_SCREENSHOTS |= frozenset(['docs/screenshots/portmaster.png', 'docs/screenshots/portmaster-thumbnail.png'])
PUBLIC_ROOT = frozenset('.gitattributes .gitignore AGENTS.md CONTRIBUTING.md LICENSE README.md THIRD_PARTY.md requirements-import.txt'.split())
BLOCKED_SUFFIXES = frozenset('.ipf .adf .hdf .mp4 .mkv .webm .mov .avi .wav .mp3 .ogg .zip .7z .tar .gz .exe .dll .so .x86_64 .png .jpg .jpeg .gif .webp .blend .fbx .glb .gltf .pem .key .pfx .p12'.split())
MAX_BYTES = 2 * 1024 * 1024
SIGNATURES = [
    (re.compile(rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'), 'private key'),
    (re.compile(rb'gh[pousr]_[A-Za-z0-9]{30,}'), 'GitHub credential'),
    (re.compile(rb'github_pat_[A-Za-z0-9_]{40,}'), 'GitHub credential'),
    (re.compile(rb'AKIA[0-9A-Z]{16}'), 'AWS credential'),
    (re.compile(rb'(?<![A-Za-z0-9_/.])/(?:home|Users)/[A-Za-z0-9_.-]+/'), 'machine-specific home path'),
    (re.compile(rb'[A-Za-z]:\\Users\\[^\\\s]+\\'), 'machine-specific home path'),
]


def git(root, *arguments, input=None):
    return subprocess.check_output(['git', '-C', str(root), *arguments], input=input, stderr=subprocess.PIPE)


def allowed_path(name):
    path = PurePosixPath(name)
    if path.is_absolute() or '..' in path.parts:
        return False
    if any(part in {'.codex', '.git', '.godot', '.vscode', '.idea', '__pycache__'} for part in path.parts):
        return False
    if path.name.startswith('.env') and path.name != '.env.example':
        return False
    if name in {'.github/workflows/server-release.yml', '.github/workflows/release.yml'}:
        return True
    if name in PUBLIC_SCREENSHOTS:
        return True
    if path.suffix.lower() in BLOCKED_SUFFIXES or name == 'STATUS.md':
        return False
    if path.parts[0] in {'work', 'outputs'}:
        return len(path.parts) == 2 and path.name == '.gitkeep'
    if path.parts[0] == 'reference':
        return name == 'reference/.gdignore'
    if name.startswith('game/assets/'):
        return name in {'game/assets/classic/.gitkeep', 'game/assets/modern/.gitkeep'}
    if name.startswith('game/content/generated/'):
        return False
    if path.parts[0] == 'docs':
        return len(path.parts) == 2 and path.name in PUBLIC_DOCS
    if path.parts[0] == 'tools':
        if name.startswith('tools/tests/'):
            return path.suffix == '.py'
        return len(path.parts) == 2 and (path.name in PUBLIC_TOOLS or path.name == 'import_accel.cpp' or
            (path.name.startswith('import_') and path.suffix == '.py') or
            (path.name.startswith('bake_') and path.suffix == '.cpp'))
    return path.parts[0] == 'game' or (len(path.parts) == 1 and name in PUBLIC_ROOT)


def valid_screenshot(content, dimensions=(640, 400)):
    """Require a complete PNG with the dimensions permitted for its exact path."""
    if not content.startswith(b'\x89PNG\r\n\x1a\n'):
        return False
    offset, chunks = 8, []
    while offset + 12 <= len(content):
        size = int.from_bytes(content[offset:offset+4], 'big')
        kind = content[offset+4:offset+8]
        end = offset + 12 + size
        if end > len(content):
            return False
        payload = content[offset+8:offset+8+size]
        crc = int.from_bytes(content[end-4:end], 'big')
        if zlib.crc32(kind + payload) != crc:
            return False
        if not chunks and (kind != b'IHDR' or size != 13 or
                           struct.unpack('>II', payload[:8]) != dimensions):
            return False
        chunks.append(kind)
        if kind == b'IEND':
            return size == 0 and end == len(content) and b'IDAT' in chunks
        offset = end
    return False


def entries(root, ref=None):
    rows = git(root, 'ls-tree', '-r', '-z', '--full-tree', ref) if ref else git(root, 'ls-files', '--stage', '-z')
    result = []
    for row in rows.split(b'\0'):
        if not row:
            continue
        header, name = row.split(b'\t', 1)
        fields = header.split()
        mode, oid = (fields[0], fields[2]) if ref else (fields[0], fields[1])
        if not ref and fields[2] != b'0':
            raise ValueError('Resolve unmerged paths before publication checks')
        result.append((mode.decode(), oid.decode(), name.decode('utf-8')))
    return result


def check_tree(root, ref=None):
    items = entries(root, ref)
    if not items:
        return ['No staged/committed source files'], 0
    # Batch object reads use Git's index/tree, so an unstaged replacement cannot
    # hide sensitive material that remains in the next commit.
    request = ''.join(oid + '\n' for _, oid, _ in items).encode()
    data = git(root, 'cat-file', '--batch', input=request)
    position, issues = 0, []
    for mode, oid, name in items:
        end = data.index(b'\n', position)
        header = data[position:end].split()
        if len(header) != 3 or header[0].decode() != oid or header[1] != b'blob':
            issues.append(name + ': unsupported object')
            position = end + 1
            continue
        size = int(header[2]); position = end + 1
        content = data[position:position+size]; position += size+1
        if mode not in {'100644', '100755'}:
            issues.append(name + ': symlink/submodule is not a public source file')
        if not allowed_path(name):
            issues.append(name + ': local-only or non-source path')
        if size > MAX_BYTES:
            issues.append(name + ': exceeds source-file size limit')
        if name in PUBLIC_SCREENSHOTS:
            dimensions = {'docs/screenshots/portmaster.png': (640, 480),
                          'docs/screenshots/portmaster-thumbnail.png': (320, 200)}.get(name, (640, 400))
            if not valid_screenshot(content, dimensions):
                issues.append(name + ': expected a complete %dx%d PNG screenshot' % dimensions)
        elif b'\0' in content:
            issues.append(name + ': binary content')
        for pattern, label in SIGNATURES:
            if pattern.search(content):
                issues.append(name + ': ' + label)  # Never echo matched values.
    return issues, len(items)


def audit(root, ref=None, history=False):
    references = git(root, 'rev-list', ref).decode().splitlines() if history else [ref]
    issues, count = [], 0
    for reference in references:
        found, checked = check_tree(root, reference)
        issues.extend((reference[:12] + ': ' if reference else '') + issue for issue in found)
        count += checked
    return issues, count, len(references)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ref', help='Check a committed ref instead of the index')
    parser.add_argument('--history', action='store_true', help='Check every commit reachable from --ref')
    args = parser.parse_args()
    if args.history and not args.ref:
        parser.error('--history requires --ref')
    root = Path(__file__).resolve().parents[1]
    try:
        issues, count, trees = audit(root, args.ref, args.history)
    except (subprocess.CalledProcessError, ValueError) as error:
        raise SystemExit('FAIL: unable to inspect Git objects: ' + str(error))
    if issues:
        print('\n'.join('FAIL: ' + issue for issue in issues))
        raise SystemExit(1)
    print(f'PASS: {count} source/documentation objects across {trees} tree(s); local asset packs, notes, unapproved binary media and detected credentials excluded')


if __name__ == '__main__':
    main()
