"""Checked Godot PCK I/O and separation of executable resources from local media."""
import hashlib
import mmap
from pathlib import PurePosixPath
import re
import struct

CONTENT_VERSION = 1
MEDIA_ROOTS = ('assets/classic/', 'content/generated/')


def safe_name(name):
    name = name.removeprefix('res://')
    path = PurePosixPath(name)
    if not name or path.is_absolute() or '..' in path.parts or '\\' in name or '\0' in name:
        raise ValueError('Unsafe pack path: ' + name)
    return name


def read_pack(data):
    return _read_pack(data, include_payloads=True)


def inspect_pack(path):
    """Validate every payload without keeping the entire media pack in Python RAM."""
    with path.open('rb') as stream:
        if path.stat().st_size < 108:raise ValueError('Truncated pack')
        with mmap.mmap(stream.fileno(), 0, access=mmap.ACCESS_READ) as data:
            return _read_pack(data, include_payloads=False)


def _read_pack(data, include_payloads, include_offsets=False):
    if len(data) < 108:
        raise ValueError('Truncated pack')
    magic, version, major, minor, patch, flags, base, directory = struct.unpack_from('<4sIIIIIQQ', data)
    if (magic, version, major, minor, flags) != (b'GDPC', 3, 4, 6, 2):
        raise ValueError('Expected ordinary Godot 4.6 PCK v3')
    if not 104 <= base <= directory <= len(data) - 4:
        raise ValueError('Invalid pack offsets')
    count = struct.unpack_from('<I', data, directory)[0]
    if not 0 < count <= 100000:
        raise ValueError('Invalid pack count')
    cursor = directory + 4
    files = {}
    for _ in range(count):
        if cursor + 4 > len(data):
            raise ValueError('Truncated directory')
        size = struct.unpack_from('<I', data, cursor)[0]
        cursor += 4
        if not 0 < size <= 4096 or cursor + size + 36 > len(data):
            raise ValueError('Invalid directory entry')
        name = safe_name(data[cursor:cursor + size].rstrip(b'\0').decode())
        cursor += size
        position, size, checksum, flags = struct.unpack_from('<QQ16sI', data, cursor)
        cursor += 36
        if flags or name in files or base + position + size > directory:
            raise ValueError('Invalid or duplicate payload: ' + name)
        # Release each view before closing a mapped pack, including on failure.
        with memoryview(data)[base + position:base + position + size] as payload:
            if hashlib.md5(payload).digest() != checksum:
                raise ValueError('Corrupt payload: ' + name)
            files[name] = bytes(payload) if include_payloads else ((base + position, size, checksum) if include_offsets else None)
    return files


def merge_packs(paths, destination):
    """Validate disjoint worker packs and stream them into one portable PCK.

    Each source is checked with the same parser as ordinary content validation.
    Only directory entries and one small copy buffer are retained in Python.
    The caller owns the temporary job directory and its cancellation cleanup.
    """
    entries = {}
    for path in paths:
        with path.open('rb') as stream:
            if path.stat().st_size < 108:raise ValueError('Truncated pack')
            with mmap.mmap(stream.fileno(), 0, access=mmap.ACCESS_READ) as data:
                rows = _read_pack(data, include_payloads=False, include_offsets=True)
        for name, row in rows.items():
            if name in entries:raise ValueError('Duplicate worker resource: ' + name)
            entries[name] = (path, *row)
    if not entries:raise ValueError('No worker resources')
    directory_rows = []
    # Validate all workers before opening the destination. Failed workers must
    # never leave a plausible completed pack or replace an installed generation.
    with destination.open('wb') as target:
        target.write(bytes(112))
        for name, (path, position, size, checksum) in sorted(entries.items()):
            target.write(bytes(-target.tell() % 16))
            offset = target.tell() - 112
            with path.open('rb') as source:
                source.seek(position)
                remaining = size
                digest = hashlib.md5()
                while remaining:
                    block = source.read(min(remaining, 256 * 1024))
                    if not block:raise ValueError('Worker resource truncated: ' + name)
                    digest.update(block);target.write(block);remaining -= len(block)
                if digest.digest() != checksum:raise ValueError('Worker resource changed: ' + name)
            directory_rows.append((name, offset, size, checksum))
        directory = target.tell()
        target.write(struct.pack('<I', len(directory_rows)))
        for name, offset, size, checksum in directory_rows:
            encoded = name.encode();encoded += bytes(-len(encoded) % 4)
            target.write(struct.pack('<I', len(encoded)) + encoded + struct.pack('<QQ16sI', offset, size, checksum, 0))
        target.seek(0)
        target.write(struct.pack('<4sIIIIIQQ', b'GDPC', 3, 4, 6, 0, 2, 112, directory))


def write_pack(files):
    """Write unencrypted v3 packs; bytes are portable across CPU architectures."""
    data = bytearray(112)
    entries = []
    names = set()
    for original, payload in sorted(files.items()):
        name = safe_name(original)
        if name in names:
            raise ValueError('Duplicate pack path: ' + name)
        names.add(name)
        data.extend(bytes(-len(data) % 16))
        entries.append((name, len(data) - 112, len(payload), hashlib.md5(payload).digest()))
        data.extend(payload)
    directory = len(data)
    data.extend(struct.pack('<I', len(entries)))
    for name, offset, size, checksum in entries:
        encoded = name.encode()
        encoded += bytes(-len(encoded) % 4)
        data.extend(struct.pack('<I', len(encoded)) + encoded + struct.pack('<QQ16sI', offset, size, checksum, 0))
    struct.pack_into('<4sIIIIIQQ', data, 0, b'GDPC', 3, 4, 6, 0, 2, 112, directory)
    return bytes(data)


def split_pack(files):
    media = {name for name in files if name.startswith(MEDIA_ROOTS)}
    for name in tuple(media):
        if name.endswith(('.import', '.remap')):
            media.update(safe_name(path) for path in re.findall(r'path="(res://[^"\n]+)"', files[name].decode().rstrip('\0')))
    if not media or any(name not in files for name in media):
        raise ValueError('Missing external resource or remap target')
    core = {name: data for name, data in files.items() if name not in media}
    # A missed import target must fail packaging instead of leaking media.
    forbidden = ('.ctex', '.sample', '.png', '.wav', '.ogg', '.mp3', '.jpg')
    if any(name.endswith(forbidden) or name.startswith(MEDIA_ROOTS) for name in core):
        raise ValueError('Unclassified original media remains in code pack')
    return core, {name: files[name] for name in sorted(media)}


def setup_pack(root):
    project='''config_version=5
[application]
config/name="Moonstone Content Setup"
run/main_scene="res://setup.tscn"
[compression]
formats/zstd/compression_level=1
[display]
window/size/viewport_width=640
window/size/viewport_height=480
window/stretch/mode="canvas_items"
[rendering]
renderer/rendering_method="gl_compatibility"
'''
    scene='''[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://setup.gd" id="1"]
[node name="ContentSetup" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
script = ExtResource("1")
'''
    return write_pack({'project.godot':project.encode(),'setup.tscn':scene.encode(),
                       '.godot/global_script_class_cache.cfg':b'list=[]\n',
                       'setup.gd':(root/'tools/portmaster_setup.gd').read_bytes(),
                       'thumbnail.gd':(root/'tools/portmaster_art.gd').read_bytes(),
                       'convert.gd':(root/'tools/portmaster_convert.gd').read_bytes()})
