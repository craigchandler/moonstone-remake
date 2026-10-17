#!/usr/bin/env python3
"""Bake the retail Troll's separate hit blood into ordinary native artwork."""
import hashlib
import json
import struct
from PIL import Image
import import_creature_pack as source


def main():
    # LAB_0F34's operand in the owned retail stalker overlay, not a translated
    # label offset from a later reassembly. All five effect slots load blo.cel.
    overlay = source.HUNKS[40]
    refs = {p: g.target_hunk for g in overlay.reloc32 for p in g.offsets}
    if refs.get(4792) != 4 or struct.unpack_from('>I', overlay.data, 4792)[0] != 28044:
        raise ValueError('Unverified retail hit-effect root')
    poses = source.poses_at(28044)
    if len(poses) != 5 or any(p['hold'] != 1 or p['mirror'] for p in poses):
        raise ValueError('Changed retail blood drawings')
    family = source.ROOT / 'game/assets/classic/recovered/B/blo.cel'
    metadata = json.loads((family / 'sidecar.json').read_text())
    original = source.ROOT / 'reference/extracted' / metadata['source']
    if hashlib.sha1(original.read_bytes()).hexdigest() != metadata['source_sha1']:
        raise ValueError('Changed recovered blood family')
    bounds = []
    images = {}
    for pose in poses:
        for layer in pose['layers']:
            if layer['slot'] != 4 or layer['flags'] != 0xa0:
                raise ValueError('Untraced hit blood layer')
            image = Image.open(family / 'frames' / f'{layer["frame"]:03d}.png')
            palette = image.getpalette()
            palette[45:48] = [204, 0, 0]  # Original scene blood register15 = $C00.
            image.putpalette(palette)
            images[layer['frame']] = image.convert('RGBA')
            # This effect is anchored at the contact pixel, not an actor's foot.
            # Undo the general creature importer's52-pixel foot conversion.
            layer['y'] += 52
            bounds.append((layer['x'], layer['y'], layer['x'] + image.width, layer['y'] + image.height))
    left, top = min(b[0] for b in bounds), min(b[1] for b in bounds)
    width, height = max(b[2] for b in bounds) - left, max(b[3] for b in bounds) - top
    atlas = Image.new('RGBA', (width * len(poses), height))
    for index, pose in enumerate(poses):
        for layer in pose['layers']:
            atlas.alpha_composite(images[layer['frame']], (index * width + layer['x'] - left, layer['y'] - top))
    out = source.ROOT / 'game/assets/classic/hit_effects'
    out.mkdir(exist_ok=True)
    atlas.save(out / 'blood.png')
    cells = ',\n'.join('{"region": Rect2(%d, 0, %d, %d), "offset": Vector2(%d, %d)}' %
                         (i * width, width, height, left, top) for i in range(len(poses)))
    (out / 'animations.tres').write_text('''[gd_resource type="Resource" load_steps=3 format=3]
[ext_resource type="Script" path="res://scripts/content/animation_set.gd" id="1"]
[ext_resource type="Texture2D" path="res://assets/classic/hit_effects/blood.png" id="2"]
[resource]
script = ExtResource("1")
default_variant = "gore"
atlases = {"gore": ExtResource("2")}
poses = [
''' + cells + '\n]\nclips = {"burst": {"frames": [0, 1, 2, 3, 4], "weights": [1, 1, 1, 1, 1], "step_ticks": 6}}\n')
    (out / 'provenance.json').write_text(json.dumps({
        'mog_sha1': source.MOG_SHA1, 'root': 28044, 'retail_reference': [40, 4792],
        'source_family': metadata['source'], 'source_sha1': metadata['source_sha1'],
        'poses': poses, 'anchor': 'contact pixel', 'gore_only': True,
        'timing': 'Five source drawings; six native ticks per drawing remains provisional.'
    }, indent=2) + '\n')
    print('Imported five original blood-burst drawings at the contact anchor')


if __name__ == '__main__':
    main()
