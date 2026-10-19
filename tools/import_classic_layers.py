#!/usr/bin/env python3
"""Losslessly factor provisioned native combat art into reusable pose layers.

Reads existing RGBA atlases and their exact baked class variants, never original
disks or executable data. Pixel differences identify class registers without
mistaking equal RGB values on a monster for knight colours. Original assets are
read-only inputs. Generated art remains local under assets/classic/layered/.
"""
from pathlib import Path
import argparse
import hashlib
import json
import math
import re

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'game/assets/classic'
OUT = ART / 'layered'
RAMPS = [[0x00a, 0x007, 0x004], [0xf80, 0xc50, 0xa30],
         [0x8c6, 0x593, 0x251], [0xf22, 0xb22, 0x700], [0x206, 0x103, 0x001]]
RGB = np.array([[[(v >> s & 15) * 17 for s in (8, 4, 0)] for v in row]
                for row in RAMPS], dtype=np.uint8)
RECT = re.compile(r'"region": Rect2\(\s*(-?\d+),\s*(-?\d+),\s*(\d+),\s*(\d+)\), "offset": Vector2\(\s*(-?\d+),\s*(-?\d+)\)')


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def read(path):
    array = np.array(Image.open(ROOT / 'game' / path.removeprefix('res://')).convert('RGBA'))
    # Transparent RGB is invisible and is not part of the visual parity contract.
    array[array[:, :, 3] == 0] = 0
    if not np.isin(array[:, :, 3], [0, 255]).all():
        raise ValueError('Classic conversion requires binary source alpha: ' + path)
    return array


def canonical(path, variants):
    choices = variants.get(path, [path])
    pixels = read(choices[0])
    indices = np.zeros(pixels.shape[:2], dtype=np.uint8)
    if len(choices) > 1:
        changed = np.any(pixels != read(choices[1]), axis=2)
        for shade in range(3):
            indices[changed & np.all(pixels[:, :, :3] == RGB[0, shade], axis=2)] = shade + 1
        if np.any(changed != (indices != 0)):
            raise ValueError('Unrecognised class colour change: ' + path)
    neutral = pixels.copy()
    neutral[indices != 0, :3] = 255
    return neutral, indices, choices


def encoded(value):
    if isinstance(value, dict):return '{' + ', '.join(json.dumps(k) + ': ' + encoded(v) for k, v in value.items()) + '}'
    if isinstance(value, list):return '[' + ', '.join(encoded(v) for v in value) + ']'
    if isinstance(value, bool):return 'true' if value else 'false'
    if isinstance(value, str):return json.dumps(value)
    return str(value)


def gd_pose(pose):
    modes = []
    for mode, pieces in pose.items():
        items = []
        for p in pieces:
            x, y, w, h = p['region']
            ox, oy = p['offset']
            items.append('{"page": %d, "region": Rect2(%d, %d, %d, %d), "offset": Vector2(%d, %d), "size": Vector2(%d, %d), "slot": %d}' %
                         (p['page'], x, y, w, h, ox, oy, w, h, p['slot']))
        modes.append(json.dumps(mode) + ': [' + ', '.join(items) + ']')
    return '{' + ', '.join(modes) + '}'


def pack(tiles):
    """Pack trimmed, deduplicated pieces; every page is at most 2048 square."""
    placements = {}
    pages = []
    x = y = row = 2
    max_x = max_y = 1
    page = Image.new('RGBA', (2048, 2048))

    def flush():
        width = 2 ** max(5, math.ceil(math.log2(max_x)))
        height = 2 ** max(5, math.ceil(math.log2(max_y)))
        pages.append(page.crop((0, 0, width, height)))

    for key, tile in sorted(tiles.items(), key=lambda item: (-item[1].height, -item[1].width, item[0])):
        if tile.width + 4 > 2048 or tile.height + 4 > 2048:
            raise ValueError('A pose piece exceeds a page')
        if x + tile.width + 2 > 2048:
            x = 2
            y += row + 2
            row = 0
        if y + tile.height + 2 > 2048:
            flush()
            page = Image.new('RGBA', (2048, 2048))
            x = y = 2
            row = 0
            max_x = max_y = 1
        page.paste(tile, (x, y))
        placements[key] = {'page': len(pages), 'region': [x, y, tile.width, tile.height]}
        max_x = max(max_x, x + tile.width + 2)
        max_y = max(max_y, y + tile.height + 2)
        row = max(row, tile.height)
        x += tile.width + 2
    flush()
    return pages, placements


def family(resource, variants):
    text = resource.read_text()
    refs = dict((i, p) for p, i in re.findall(r'path="(res://assets/[^\"]+\.png)" id="([^\"]+)"', text))
    atlas_line = next(line for line in text.splitlines() if line.startswith('atlases = '))
    bindings = dict(re.findall(r'"([^\"]+)": ExtResource\("([^\"]+)"\)', atlas_line))
    paths = {v: refs[i] for v, i in bindings.items()}
    if resource.parent.name == 'knight':
        gore_path, clean_path = paths['blue'], paths['blue_clean']
    elif 'gore' in paths:
        gore_path = paths['gore']
        clean_path = gore_path
    else:
        gore_path, clean_path = paths['blue'], paths['blue_clean']
    g, gi, gchoices = canonical(gore_path, variants)
    c, ci, cchoices = canonical(clean_path, variants)
    if g.shape != c.shape:raise ValueError('Clean/gore dimensions differ')
    shared = np.all(g == c, axis=2) & (gi == ci)
    rects = [list(map(int, match)) for match in RECT.findall(text)]
    tiles, poses = {}, []
    for x, y, width, height, _, _ in rects:
        pose = {}
        for mode, pixels, indices, selection in [('shared', g, gi, shared),
                                                 ('clean', c, ci, ~shared),
                                                 ('gore', g, gi, ~shared)]:
            a = pixels[y:y+height, x:x+width]
            ix = indices[y:y+height, x:x+width]
            keep = selection[y:y+height, x:x+width] & (a[:, :, 3] != 0)
            pieces = []
            for slot in (-1, 0, 1, 2):
                mask = keep & (ix == slot + 1)
                if not mask.any():continue
                yy, xx = np.nonzero(mask)
                left, top, right, bottom = int(xx.min()), int(yy.min()), int(xx.max())+1, int(yy.max())+1
                tile = a[top:bottom, left:right].copy()
                tile[~mask[top:bottom, left:right]] = 0
                key = hashlib.sha256(str(tile.shape).encode() + tile.tobytes()).hexdigest()
                tiles.setdefault(key, Image.fromarray(tile))
                pieces.append({'tile': key, 'offset': [left, top], 'slot': slot})
            pose[mode] = pieces
        poses.append(pose)
    pages, placements = pack(tiles)
    for pose in poses:
        for pieces in pose.values():
            for piece in pieces:piece.update(placements[piece.pop('tile')])
    folder = OUT / resource.parent.name
    folder.mkdir(parents=True, exist_ok=True)
    for i, page in enumerate(pages):page.save(folder / f'page-{i}.png')
    # The legacy purple knight is the fixed rival identity, not the chosen human.
    if resource.parent.name == 'knight':
        for path, choices in [(paths['purple'], gchoices), (paths['purple_clean'], cchoices)]:
            if not np.array_equal(read(path), read(choices[4])):
                raise ValueError('Purple rival differs from palette identity 4')
    layer_variants = {key: {'gore': not key.endswith('_clean'), 'colour': 4 if resource.parent.name == 'knight' and key.startswith('purple') else -1}
                      for key in paths}
    # Each pixel belongs to exactly one piece, so composition cannot build up
    # extra alpha at antialiased boundaries. This is checked for every source.
    checked = 0
    for mode, choices in [('gore', gchoices), ('clean', cchoices)]:
        for identity, path in enumerate(choices):
            expected = read(path)
            for index, (x, y, width, height, _, _) in enumerate(rects):
                actual = np.zeros((height, width, 4), dtype=np.uint8)
                for piece in poses[index]['shared'] + poses[index][mode]:
                    px, py, pw, ph = piece['region']
                    pixels = np.array(pages[piece['page']].crop((px, py, px+pw, py+ph)))
                    mask = pixels[:, :, 3] != 0
                    if piece['slot'] >= 0:pixels[mask, :3] = RGB[identity, piece['slot']]
                    ox, oy = piece['offset']
                    dest = actual[oy:oy+ph, ox:ox+pw]
                    if np.any(mask & (dest[:, :, 3] != 0)):raise ValueError('Overlapping layer pixels')
                    dest[mask] = pixels[mask]
                if not np.array_equal(actual, expected[y:y+height, x:x+width]):
                    raise ValueError(f'Layer mismatch: {resource.parent.name}/{mode}/{identity}/{index}')
                checked += 1
    header = f'[gd_resource type="Resource" load_steps={len(pages)+2} format=3]\n'
    header += '[ext_resource type="Script" path="res://scripts/content/sprite_layers.gd" id="script"]\n'
    for i in range(len(pages)):
        header += f'[ext_resource type="Texture2D" path="res://assets/classic/layered/{resource.parent.name}/page-{i}.png" id="p{i}"]\n'
    header += '\n[resource]\nscript = ExtResource("script")\npages = [' + ', '.join(f'ExtResource("p{i}")' for i in range(len(pages))) + ']\n'
    header += 'palette = PackedColorArray(' + ', '.join(str(int(channel)/255) for row in RGB for colour in row for channel in [*colour, 255]) + ')\n'
    header += 'poses = [\n' + ',\n'.join(gd_pose(p) for p in poses) + '\n]\n'
    (folder / 'layers.tres').write_text(header)
    # Preserve every clip, frame index, hold and logical anchor from native art.
    lines = [line for line in text.splitlines() if not line.startswith('[ext_resource type="Texture2D"')]
    lines[0] = '[gd_resource type="Resource" load_steps=3 format=3]'
    at = lines.index('[resource]')
    lines.insert(at, f'[ext_resource type="Resource" path="res://assets/classic/layered/{resource.parent.name}/layers.tres" id="layers"]')
    lines = ['atlases = {}' if line.startswith('atlases = ') else line for line in lines]
    lines += ['layers = ExtResource("layers")', 'layer_variants = ' + encoded(layer_variants)]
    (folder / 'animations.tres').write_text('\n'.join(lines) + '\n')
    (folder / 'layout.json').write_text(json.dumps({'poses': poses, 'variants': layer_variants, 'source_regions': rects}, indent=2) + '\n')
    return {'family': resource.parent.name, 'poses': len(poses), 'page_sizes': [list(p.size) for p in pages],
            'unique_pieces': len(tiles), 'pixel_comparisons': checked,
            'recolourable': len(gchoices) > 1 or len(cchoices) > 1,
            'source_files': sorted(set([*paths.values(), *gchoices, *cchoices]))}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Check source/output fingerprints without reconverting.')
    args = parser.parse_args()
    if args.check:
        try:
            report = json.loads((OUT / 'provenance.json').read_text())
            valid = bool(report.get('generated_files')) and all(
                (ROOT / path).is_file() and digest(ROOT / path) == value
                for category in ['source_files', 'generated_files']
                for path, value in report[category].items())
        except (OSError, ValueError, KeyError):
            valid = False
        print('PASS: layered native pack is current.' if valid else 'Layered native pack needs conversion.')
        raise SystemExit(0 if valid else 1)
    selection = (ART / 'knight_selection/art.tres').read_text()
    variants = json.loads(next(line.removeprefix('variants = ') for line in selection.splitlines() if line.startswith('variants = ')))
    resources = sorted(ART.glob('*/animations.tres'))
    source_paths = {str(p.relative_to(ROOT)): digest(p) for p in resources}
    for path in [ART / 'knight_selection/art.tres', ROOT / 'game/content/classic_art.tres']:
        source_paths[str(path.relative_to(ROOT))] = digest(path)
    for choices in variants.values():
        for path in choices:
            file = ROOT / 'game' / path.removeprefix('res://')
            source_paths[str(file.relative_to(ROOT))] = digest(file)
    rows = []
    for resource in resources:
        row = family(resource, variants)
        rows.append(row)
        print(row['family'], row['poses'], 'poses;', len(row['page_sizes']), 'pages;', row['pixel_comparisons'], 'exact comparisons', flush=True)
        for path in row['source_files']:
            file = ROOT / 'game' / path.removeprefix('res://')
            source_paths.setdefault(str(file.relative_to(ROOT)), digest(file))
    classic = (ROOT / 'game/content/classic_art.tres').read_text()
    def replace(match):
        folder = Path(match[1]).parent.name
        return f'path="res://assets/classic/layered/{folder}/animations.tres"'
    classic = re.sub(r'path="(res://assets/classic/[^/]+/animations\.tres)"', replace, classic)
    classic = classic.replace('pack_id = &"classic"', 'pack_id = &"classic_layered"')
    generated = ROOT / 'game/content/generated/classic_layered_art.tres'
    generated.write_text(classic)
    if not all(digest(ROOT / path) == value for path, value in source_paths.items()):
        raise ValueError('An original input changed')
    report = {'result': 'PASS', 'families': rows, 'pixel_comparisons': sum(r['pixel_comparisons'] for r in rows),
              'source_files': source_paths, 'source_files_unchanged': True,
              'scope': 'All combat poses, original class colours, gore/clean variants. UI and cinematics retain their existing art.',
              'method': 'Shared body, neutral class masks, disjoint clean/gore replacements; trimmed and deduplicated in <=2048px pages. No new drawing or altered animation clocks.'}
    report['generated_files'] = {str(p.relative_to(ROOT)): digest(p) for p in [generated, *OUT.rglob('*.tres'), *OUT.rglob('page-*.png')]}
    (OUT / 'provenance.json').write_text(json.dumps(report, indent=2) + '\n')
    print('PASS:', len(rows), 'families;', report['pixel_comparisons'], 'pixel-exact pose/colour/gore comparisons; original inputs unchanged.')


if __name__ == '__main__':
    main()
