"""Shared desktop and packaged-importer dependency boundaries."""
import os
import json
from pathlib import Path
import struct
import subprocess
import time
import re


class ImportProgress:
    """Optional, rate-limited detail for the active handheld conversion stage."""
    def __init__(self):
        self.path = os.environ.get('MOONSTONE_IMPORT_STATUS')
        self.last = float('-inf')

    def update(self, current, total, unit):
        now = time.monotonic()
        if not self.path or (current != total and now - self.last < 1):return
        self.last = now
        try:
            path = Path(self.path)
            status = json.loads(path.read_text())
            if not isinstance(status, dict) or status.get('state') != 'running':return
            status['detail'] = f'{unit} {current} of {total}'
            temporary = path.with_suffix(path.suffix + '.new')
            temporary.write_text(json.dumps(status) + '\n')
            os.replace(temporary, path)
        except (OSError, ValueError):
            # A cosmetic progress update must never fail the actual import.
            pass


def rgba_array(path):
    """Read RGBA pixels, releasing Pillow's decoded image before further copies."""
    import numpy as np
    from PIL import Image
    with Image.open(path) as image:
        rgba = image if image.mode == 'RGBA' else image.convert('RGBA')
        try:
            # Pillow exposes an independent bytes buffer. This array stays
            # valid after close and is read only; callers copy before editing.
            return np.asarray(rgba)
        finally:
            if rgba is not image:rgba.close()
            image.close()


def compact_pose_atlases(keys, render, origin, width=1024):
    """Pack each distinct draw program once, retaining both gore/clean anchors.

    Keys describe source cells and transforms, not RGB values: identical-looking
    pixels can come from different palette registers and must remain distinct.
    Rendering and cropping are offline presentation operations only.
    """
    from PIL import Image
    unique = {}
    placements = {}
    x = y = row_height = 2
    used_width = used_height = 1
    for key in keys:
        if key in unique:continue
        images = render(key)
        if not images or any(im.size != images[0].size for im in images):
            raise ValueError('Expected matching pose variant dimensions')
        occupied = [im.getchannel('A').getbbox() for im in images]
        occupied = [bounds for bounds in occupied if bounds is not None]
        bounds = ((min(b[0] for b in occupied), min(b[1] for b in occupied),
                   max(b[2] for b in occupied), max(b[3] for b in occupied))
                  if occupied else (0, 0, 1, 1))
        tiles = [im.crop(bounds) for im in images]
        tw, th = tiles[0].size
        if tw + 4 > width:raise ValueError('Pose exceeds compact atlas width')
        if x + tw + 2 > width:
            x = 2
            y += row_height + 2
            row_height = 0
        unique[key] = tiles
        placements[key] = (x, y, tw, th, origin[0]+bounds[0], origin[1]+bounds[1])
        used_width, used_height = max(used_width, x+tw+2), max(used_height, y+th+2)
        row_height = max(row_height, th)
        x += tw + 2
    atlases = [Image.new('RGBA', (used_width, used_height)) for _ in next(iter(unique.values()))]
    for key, tiles in unique.items():
        for atlas, tile in zip(atlases, tiles):atlas.paste(tile, placements[key][:2])
    return atlases, [placements[key] for key in keys]


def compact_source_atlas(root, name):
    """Trim legacy fixed-cell atlases before colour-mask extraction.

    Keep each logical frame distinct, including visually equal pixels sourced
    from different palette registers. The resource retains its original clips
    and each frame's absolute drawing anchor; only texture placement changes.
    """
    from PIL import Image
    folder = root/'game/assets/classic'/name
    resource = folder/'animations.tres'
    text = resource.read_text()
    pattern = re.compile(r'"region": Rect2\(\s*(-?\d+),\s*(-?\d+),\s*(\d+),\s*(\d+)\), "offset": Vector2\(\s*(-?\d+),\s*(-?\d+)\)')
    rects = [tuple(map(int, match)) for match in pattern.findall(text)]
    paths = sorted(set(re.findall(r'path="(res://assets/[^\"]+\.png)"', text)))
    images = []
    files = [root/'game'/p.removeprefix('res://') for p in paths]
    for file in files:
        with Image.open(file) as image:images.append(image.convert('RGBA'))
    def render(index):
        x,y,w,h,*_=rects[index]
        return [im.crop((x,y,x+w,y+h)) for im in images]
    atlases,regions = compact_pose_atlases(range(len(rects)),render,(0,0))
    for file,atlas in zip(files,atlases):atlas.save(file)
    packed = [(x,y,w,h,ox+old[4],oy+old[5]) for (x,y,w,h,ox,oy),old in zip(regions,rects)]
    record_compact_layout(root,name,rects,packed)
    replacements = iter(packed)
    text = pattern.sub(lambda _: '"region": Rect2(%d,%d,%d,%d), "offset": Vector2(%d,%d)' % next(replacements),text)
    resource.write_text(text)


def record_compact_layout(root, name, original, packed):
    # The final layered resource must retain the old logical canvas as well as
    # visible pixel positions: practice previews use that canvas for framing.
    folder=root/'work/compact-atlas-layouts';folder.mkdir(parents=True,exist_ok=True)
    (folder/(name+'.json')).write_text(json.dumps({'version':1,'original':original,'packed':packed})+'\n')


def require_reference(upstream, pin):
    marker = upstream / 'SOURCE_REVISION'
    actual = marker.read_text().strip() if marker.is_file() else subprocess.check_output(
        ['git', '-C', str(upstream), 'rev-parse', 'HEAD'], text=True).strip()
    if actual != pin:
        raise ValueError('Importer requires the pinned reference helper: ' + pin)


def audio_helper(root, upstream, work, name, sources, tables=None):
    """On handhelds read owned sound tables as data; never invoke a compiler."""
    packaged = os.environ.get('MOONSTONE_IMPORT_BIN')
    if packaged:
        binary = Path(packaged) / (name + ('.exe' if os.name == 'nt' else ''))
        if not binary.is_file():
            raise ValueError('Missing importer helper: ' + name)
        if tables is not None:
            blob, instruments, waves = tables.build()
            if (len(blob), len(instruments), len(waves)) != (5890, 131, 170):
                raise ValueError('Unexpected sound table dimensions')
            target = work / 'synth-tables.bin'
            target.write_bytes(b'MSST0001' + blob + waves + b''.join(
                struct.pack('<hHHHIH', *row) for row in instruments))
            os.environ['MOONSTONE_SYNTH_TABLES'] = str(target)
        return binary
    source_files = list(sources)
    if tables is not None:
        generated = work / 'synth_data.cpp'
        generated.write_text(tables.render())
        source_files.append(generated)
    binary = work / name
    subprocess.run(['c++', '-std=c++17', '-O2', '-I' + str(upstream / 'include'),
                    *map(str, source_files), '-o', str(binary)], check=True)
    return binary
