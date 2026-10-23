#!/usr/bin/env python3
"""Losslessly factor provisioned native combat art into reusable pose layers.

Reads existing RGBA atlases and their exact baked class variants, never original
disks or executable data. The handheld path uses separately recovered register
masks instead of intermediate colour variants. Both paths distinguish equal RGB
values at fixed and knight-colour registers. Original assets are read-only inputs.
Generated art remains local under assets/classic/layered/.
"""
from pathlib import Path
import argparse
import hashlib
import json
import math
import os
import re
import multiprocessing
from concurrent.futures import ProcessPoolExecutor

import numpy as np
import import_accel
import copy
from PIL import Image
from import_support import ImportProgress, rgba_array

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'game/assets/classic'
OUT = ART / 'layered'
RAMPS = [[0x00a, 0x007, 0x004], [0xf80, 0xc50, 0xa30],
         [0x8c6, 0x593, 0x251], [0xf22, 0xb22, 0x700], [0x206, 0x103, 0x001]]
RGB = np.array([[[(v >> s & 15) * 17 for s in (8, 4, 0)] for v in row]
                for row in RAMPS], dtype=np.uint8)
RGBA_WORDS = np.concatenate((RGB, np.full((5, 3, 1), 255, dtype=np.uint8)), axis=2).view(np.uint32).reshape(5, 3)
RECT = re.compile(r'"region": Rect2\(\s*(-?\d+),\s*(-?\d+),\s*(\d+),\s*(\d+)\), "offset": Vector2\(\s*(-?\d+),\s*(-?\d+)\)')


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def read(path):
    array = rgba_array(ROOT / 'game' / path.removeprefix('res://')).copy()
    # Transparent RGB is invisible and is not part of the visual parity contract.
    alpha = array[:, :, 3]
    np.copyto(pixel_words(array), 0, where=alpha == 0)
    if np.any((alpha != 0) & (alpha != 255)):
        raise ValueError('Classic conversion requires binary source alpha: ' + path)
    return array


def pixel_words(array):
    """Compare/clear contiguous RGBA pixels as opaque words, independent of endian order."""
    return array.view(np.uint32).reshape(array.shape[:2])


def rgb_mask(array, colour):
    # Avoid a temporary HxWx3 boolean array and a reduction for every colour.
    return ((array[:, :, 0] == colour[0]) & (array[:, :, 1] == colour[1]) &
            (array[:, :, 2] == colour[2]))


def colour_indices(path, compact, pixels):
    entry = compact[path]
    file = ROOT / 'game' / path.removeprefix('res://')
    if digest(file) != entry['source_sha256']:
        raise ValueError('Combat source changed after mask conversion: ' + path)
    mask_file = ROOT / entry['mask']
    if digest(mask_file) != entry['mask_sha256']:
        raise ValueError('Combat colour mask changed: ' + path)
    with Image.open(mask_file) as image:
        if image.mode != 'L' or image.size != (pixels.shape[1], pixels.shape[0]):
            raise ValueError('Combat colour mask dimensions/mode differ: ' + path)
        indices = np.array(image)
    if np.any(indices > 3):raise ValueError('Unknown combat colour register: ' + path)
    indices[pixels[:, :, 3] == 0] = 0
    return indices


def recolour(pixels, indices, identity):
    words = pixel_words(pixels)
    for shade in range(3):
        np.copyto(words, RGBA_WORDS[identity, shade], where=indices == shade + 1)
    return pixels


def canonical(path, variants, compact=None):
    choices = variants.get(path, [path])
    pixels = read(choices[0])
    if compact is not None and path in compact:
        indices = colour_indices(path, compact, pixels)
        choices = [path] * (5 if np.any(indices) else 1)
    else:
        indices = np.zeros(pixels.shape[:2], dtype=np.uint8)
    if compact is None and len(choices) > 1:
        changed = pixel_words(pixels) != pixel_words(read(choices[1]))
        for shade in range(3):
            indices[changed & rgb_mask(pixels, RGB[0, shade])] = shade + 1
        if np.any(changed != (indices != 0)):
            raise ValueError('Unrecognised class colour change: ' + path)
    # read() returns an owned writable array; its original colours are no longer
    # needed once the register indices have been checked.
    neutral = pixels
    tinted = indices != 0
    np.copyto(pixel_words(neutral), np.uint32(0xffffffff), where=tinted)
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


def pose_pieces(g, gi, c, ci, rects):
    """Keep full-sheet masks and views scoped to the factoring step."""
    tiles, poses, seen = {}, [], {}
    for x, y, width, height, _, _ in rects:
        rectangle_key=(x,y,width,height)
        if rectangle_key in seen:
            # Repeated draw programs share this exact source rectangle. Keep
            # independent mutable piece dictionaries for later placement.
            poses.append(copy.deepcopy(seen[rectangle_key]));continue
        # Compute only this pose's mask, never a full-sheet inverse per pose.
        # The atlases can contain tens of millions of mostly empty pixels.
        ga, ca = g[y:y+height, x:x+width], c[y:y+height, x:x+width]
        gix, cix = gi[y:y+height, x:x+width], ci[y:y+height, x:x+width]
        bounds = mask_bounds((ga[:, :, 3] != 0) | (ca[:, :, 3] != 0))
        if bounds is None:
            poses.append({'shared': [], 'clean': [], 'gore': []})
            continue
        bx, by, br, bb = bounds
        ga, ca = ga[by:bb, bx:br], ca[by:bb, bx:br]
        gix, cix = gix[by:bb, bx:br], cix[by:bb, bx:br]
        shared = (pixel_words(ga) == pixel_words(ca)) & (gix == cix)
        pose = {}
        for mode, a, ix, selection in [('shared', ga, gix, shared),
                                      ('clean', ca, cix, ~shared),
                                      ('gore', ga, gix, ~shared)]:
            keep = selection & (a[:, :, 3] != 0)
            pieces = []
            for slot in (-1, 0, 1, 2):
                mask = keep & (ix == slot + 1)
                if not mask.any():continue
                left, top, right, bottom = mask_bounds(mask)
                tile = a[top:bottom, left:right].copy()
                np.copyto(pixel_words(tile), 0, where=~mask[top:bottom, left:right])
                key = hashlib.sha256(str(tile.shape).encode() + tile.tobytes()).hexdigest()
                tiles.setdefault(key, Image.fromarray(tile))
                pieces.append({'tile': key, 'offset': [left + bx, top + by], 'slot': slot})
            pose[mode] = pieces
        poses.append(pose)
        seen[rectangle_key]=pose
    return tiles, poses


def mask_bounds(mask):
    """Find occupied bounds without allocating coordinates for every pixel."""
    columns = np.flatnonzero(mask.any(axis=0))
    if not columns.size:return None
    rows = np.flatnonzero(mask.any(axis=1))
    return int(columns[0]), int(rows[0]), int(columns[-1])+1, int(rows[-1])+1


def comparison_bounds(target, pieces):
    # read() already canonicalizes every transparent source pixel to zero.
    # The union covers every nonzero expected pixel AND every drawn piece, so
    # comparing it proves equality of the entire logical pose, including any
    # missing, extra or overlapping pixels. Padding outside it is zero on both
    # sides. Do not restrict the comparison to the expected bounds alone.
    bounds = mask_bounds(target[:, :, 3] != 0)
    rectangles = [] if bounds is None else [bounds]
    for piece in pieces:
        ox, oy = piece['offset']
        rectangles.append((ox, oy, ox+piece['region'][2], oy+piece['region'][3]))
    if not rectangles:return (0, 0, 0, 0)
    return (min(r[0] for r in rectangles), min(r[1] for r in rectangles),
            max(r[2] for r in rectangles), max(r[3] for r in rectangles))


def family_task(arguments):
    return family(*arguments)


def family(resource, variants, compact=None):
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
    if compact is not None and resource.parent.name != 'hit_effects':
        if gore_path not in compact or clean_path not in compact:
            raise ValueError('Missing direct combat colour mask: ' + resource.parent.name)
    g, gi, gchoices = canonical(gore_path, variants, compact)
    c, ci, cchoices = (g, gi, gchoices) if clean_path == gore_path else canonical(clean_path, variants, compact)
    if g.shape != c.shape:raise ValueError('Clean/gore dimensions differ')
    rects = [list(map(int, match)) for match in RECT.findall(text)]
    tiles, poses = pose_pieces(g, gi, c, ci, rects)
    # Subsequent checks read one source variant at a time. They do not need the
    # large canonical sheets or any views/masks retaining their backing arrays.
    del g, gi, c, ci
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
            expected = read(choices[4])
            if compact is not None:
                expected = recolour(expected, colour_indices(choices[4], compact, expected), 4)
            if not np.array_equal(read(path), expected):
                raise ValueError('Purple rival differs from palette identity 4')
            del expected
    layer_variants = {key: {'gore': not key.endswith('_clean'), 'colour': 4 if resource.parent.name == 'knight' and key.startswith('purple') else -1}
                      for key in paths}
    # Each pixel belongs to exactly one piece, so composition cannot build up
    # extra alpha at antialiased boundaries. This is checked for every source.
    checked = 0
    # Page pixels stay immutable. Slice/copy only the small piece being checked,
    # instead of doing a Pillow crop and array conversion for every pose/colour.
    page_pixels = [np.array(page) for page in pages]
    for mode, choices in [('gore', gchoices), ('clean', cchoices)]:
        indices = None
        if compact is not None:
            expected = read(choices[0])
            indices = colour_indices(choices[0], compact, expected) if choices[0] in compact else None
        if compact is not None and import_accel.library():
            for index,rect in enumerate(rects):
                checked+=import_accel.verify_pose(expected,indices,page_pixels,
                    poses[index]['shared']+poses[index][mode],rect,RGBA_WORDS,len(choices))
            continue
        bounds = None
        for identity, path in enumerate(choices):
            if compact is None:expected = read(path)
            if bounds is None or compact is None:
                bounds = [comparison_bounds(expected[y:y+height, x:x+width], poses[index]['shared'] + poses[index][mode])
                          for index, (x, y, width, height, _, _) in enumerate(rects)]
            for index, (x, y, width, height, _, _) in enumerate(rects):
                left, top, right, bottom = bounds[index]
                actual = np.zeros((bottom-top, right-left, 4), dtype=np.uint8)
                for piece in poses[index]['shared'] + poses[index][mode]:
                    px, py, pw, ph = piece['region']
                    pixels = page_pixels[piece['page']][py:py+ph, px:px+pw].copy()
                    mask = pixels[:, :, 3] != 0
                    if piece['slot'] >= 0:
                        np.copyto(pixel_words(pixels), RGBA_WORDS[identity, piece['slot']], where=mask)
                    ox, oy = piece['offset']
                    ox -= left
                    oy -= top
                    dest = actual[oy:oy+ph, ox:ox+pw]
                    if np.any(mask & (dest[:, :, 3] != 0)):raise ValueError('Overlapping layer pixels')
                    np.copyto(pixel_words(dest), pixel_words(pixels), where=mask)
                target = expected[y+top:y+bottom, x+left:x+right]
                if indices is not None:
                    target = recolour(target.copy(), indices[y+top:y+bottom, x+left:x+right], identity)
                if not np.array_equal(actual, target):
                    raise ValueError(f'Layer mismatch: {resource.parent.name}/{mode}/{identity}/{index}')
                checked += 1
    layout_file=ROOT/'work/compact-atlas-layouts'/(resource.parent.name+'.json')
    if compact is not None and layout_file.exists():
        layout=json.loads(layout_file.read_text())
        if layout.get('version')!=1 or layout['packed']!=rects or len(layout['original'])!=len(rects):
            raise ValueError('Compact atlas layout differs: '+resource.parent.name)
        # Restore the original logical canvas after validating compact pixels.
        # This keeps preview fitting, reflection anchors and drawing bounds
        # unchanged, while intermediate image storage is tightly packed.
        for pose,packed,original in zip(poses,rects,layout['original']):
            for pieces in pose.values():
                for piece in pieces:
                    piece['offset'][0]+=packed[4]-original[4]
                    piece['offset'][1]+=packed[5]-original[5]
        rects=layout['original']
        replacements=iter(rects)
        text=RECT.sub(lambda _: '"region": Rect2(%d,%d,%d,%d), "offset": Vector2(%d,%d)' % tuple(next(replacements)),text)
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
    compact = None
    if os.environ.get('MOONSTONE_COMPACT_LAYERS') == '1':
        manifest = json.loads((ROOT / 'work/combat-colour-masks/manifest.json').read_text())
        if manifest['version'] != 1:raise ValueError('Unknown combat mask version')
        compact = manifest['paths']
    resources = sorted(ART.glob('*/animations.tres'))
    source_paths = {p.relative_to(ROOT).as_posix(): digest(p) for p in resources}
    for path in [ART / 'knight_selection/art.tres', ROOT / 'game/content/classic_art.tres']:
        source_paths[path.relative_to(ROOT).as_posix()] = digest(path)
    if compact is not None:
        for row in compact.values():source_paths[row['mask']] = row['mask_sha256']
        for path in (ROOT/'work/compact-atlas-layouts').glob('*.json'):
            source_paths[path.relative_to(ROOT).as_posix()]=digest(path)
    for choices in variants.values():
        for path in choices:
            file = ROOT / 'game' / path.removeprefix('res://')
            source_paths[file.relative_to(ROOT).as_posix()] = digest(file)
    rows = []
    progress = ImportProgress()
    def collect(results):
        for row in results:
            rows.append(row)
            progress.update(len(rows), len(resources), 'Sprite family')
            print(row['family'], row['poses'], 'poses;', len(row['page_sizes']), 'pages;', row['pixel_comparisons'], 'exact comparisons', flush=True)
            for path in row['source_files']:
                file = ROOT / 'game' / path.removeprefix('res://')
                source_paths.setdefault(file.relative_to(ROOT).as_posix(), digest(file))
    workers=max(1,min(4,int(os.environ.get('MOONSTONE_IMPORT_JOBS','1'))))
    tasks=[(resource,variants,compact) for resource in resources]
    if workers==1:collect(map(family_task,tasks))
    else:
        # The coordinator has not loaded any atlas pixels. Fork workers inherit
        # only small read-only tables; families write disjoint output directories.
        with ProcessPoolExecutor(max_workers=workers,mp_context=multiprocessing.get_context('spawn' if os.name=='nt' else 'fork')) as pool:
            collect(pool.map(family_task,tasks))
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
    if compact is not None:
        report['colour_source'] = 'Original indexed register masks; expected pose colours evaluated directly without intermediate variant atlases.'
    report['generated_files'] = {p.relative_to(ROOT).as_posix(): digest(p) for p in [generated, *OUT.rglob('*.tres'), *OUT.rglob('page-*.png')]}
    (OUT / 'provenance.json').write_text(json.dumps(report, indent=2) + '\n')
    print('PASS:', len(rows), 'families;', report['pixel_comparisons'], 'pixel-exact pose/colour/gore comparisons; original inputs unchanged.')


if __name__ == '__main__':
    main()
