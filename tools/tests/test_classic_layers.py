"""Optional image-tool regressions; source-only server checks need no imaging libs."""
from pathlib import Path
import importlib.util
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
IMAGING = all(importlib.util.find_spec(name) is not None for name in ('numpy', 'PIL'))


@unittest.skipUnless(IMAGING, 'Optional original-data import dependencies are absent')
class DirectLayerTests(unittest.TestCase):
    def test_compact_poses_keep_anchors_gore_and_source_register_identity(self):
        from PIL import Image
        from import_support import compact_pose_atlases
        rendered=[]
        def render(key):
            rendered.append(key)
            pair=[Image.new('RGBA',(20,20)) for _ in range(2)]
            if key!='empty':
                pair[0].putpixel((7,3),(0,0,170,255))
                pair[1].putpixel((9,8),(0,0,170,255))
            return pair
        keys=['class-register','fixed-register','class-register','empty']
        atlases,regions=compact_pose_atlases(keys,render,(-10,-15),width=32)
        self.assertEqual(rendered,['class-register','fixed-register','empty'])
        self.assertEqual(regions[0],regions[2])
        self.assertNotEqual(regions[0][:2],regions[1][:2])
        for key,region in zip(keys,regions):
            x,y,w,h,ox,oy=region
            for mode,atlas in enumerate(atlases):
                restored=Image.new('RGBA',(20,20))
                restored.paste(atlas.crop((x,y,x+w,y+h)),(ox+10,oy+15))
                self.assertEqual(restored.tobytes(),render(key)[mode].tobytes())
        self.assertLess(atlases[0].width*atlases[0].height,20*20*len(keys))

    def test_comparison_bounds_include_extra_pieces_and_missing_source_pixels(self):
        import numpy as np
        from import_classic_layers import comparison_bounds
        pixels=np.zeros((20,30,4),dtype=np.uint8)
        pixels[2,1]=[1,2,3,255]
        pieces=[{'offset':[25,17],'region':[0,0,3,2]}]
        self.assertEqual(comparison_bounds(pixels,pieces),(1,2,28,19))
        self.assertEqual(comparison_bounds(pixels,[]),(1,2,2,3))
        self.assertEqual(comparison_bounds(np.zeros_like(pixels),pieces),(25,17,28,19))
        self.assertEqual(comparison_bounds(np.zeros_like(pixels),[]),(0,0,0,0))

    def test_legacy_atlas_crop_preserves_all_variant_anchors_and_clips(self):
        from PIL import Image
        from import_support import compact_source_atlas
        from import_classic_layers import RECT
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);folder=root/'game/assets/classic/knight';folder.mkdir(parents=True)
            refs=[];original=[]
            for i in range(4):
                im=Image.new('RGBA',(20,10));im.putpixel((2+i,3),(12,34,56,255));im.putpixel((17-i,6),(98,76,54,255))
                im.save(folder/f'{i}.png');original.append(im)
                refs.append(f'[ext_resource type="Texture2D" path="res://assets/classic/knight/{i}.png" id="{i}"]')
            clip='clips = {"idle": {"frames": [0,1,0], "weights": [1,2,1]}}\n'
            resource=folder/'animations.tres'
            resource.write_text('\n'.join(refs)+'\nposes = [{"region": Rect2(0,0,10,10), "offset": Vector2(-5,-8)}, {"region": Rect2(10,0,10,10), "offset": Vector2(-4,-9)}]\n'+clip)
            compact_source_atlas(root,'knight')
            text=resource.read_text();self.assertTrue(text.endswith(clip))
            rects=[tuple(map(int,r)) for r in RECT.findall(text)]
            for i in range(4):
                with Image.open(folder/f'{i}.png') as im:
                    for index,(x,y,w,h,ox,oy) in enumerate(rects):
                        restored=Image.new('RGBA',(10,10));restored.paste(im.crop((x,y,x+w,y+h)),(ox+[5,4][index],oy+[8,9][index]))
                        self.assertEqual(restored.tobytes(),original[i].crop((index*10,0,index*10+10,10)).tobytes())

    def test_direct_masks_match_independently_baked_colours_and_gore(self):
        import numpy as np
        from PIL import Image
        import import_classic_layers as layers
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            art = root / 'game/assets/classic'
            folder = art / 'fighter'
            folder.mkdir(parents=True)
            variants, compact = {}, {}
            for clean in (False, True):
                name = 'blue_clean' if clean else 'blue'
                base = np.zeros((4, 8, 4), dtype=np.uint8)
                base[1, 1] = [0, 0, 170, 255]  # Class register 6.
                base[1, 2] = [0, 0, 170, 255]  # Equal RGB, fixed register.
                base[2, 5] = [99, 88, 77, 255]  # Register 7 needs blue correction too.
                if not clean:base[2, 6] = [204, 0, 0, 255]
                indices = np.zeros((4, 8), dtype=np.uint8)
                indices[1, 1], indices[2, 5] = 1, 2
                path = 'res://assets/classic/fighter/' + name + '.png'
                source = folder / (name + '.png')
                Image.fromarray(base).save(source)
                mask = folder / (name + '-mask.png')
                Image.fromarray(indices).save(mask)
                compact[path] = {'mask':str(mask.relative_to(root)),
                                 'mask_sha256':layers.digest(mask),
                                 'source_sha256':layers.digest(source)}
                choices = []
                for identity in range(5):
                    expected = base.copy()
                    # Independent per-pixel oracle, including identical fixed RGB.
                    for y in range(4):
                        for x in range(8):
                            shade = int(indices[y, x])
                            if shade:expected[y, x, :3] = layers.RGB[identity, shade-1]
                    target = folder / f'{name}-{identity}.png'
                    Image.fromarray(expected).save(target)
                    choices.append('res://assets/classic/fighter/' + target.name)
                variants[path] = choices
            resource = folder / 'animations.tres'
            resource.write_text('''[gd_resource type="Resource" format=3]
[ext_resource type="Texture2D" path="res://assets/classic/fighter/blue.png" id="g"]
[ext_resource type="Texture2D" path="res://assets/classic/fighter/blue_clean.png" id="c"]
[resource]
atlases = {"blue": ExtResource("g"), "blue_clean": ExtResource("c")}
poses = [{"region": Rect2(0, 0, 4, 4), "offset": Vector2(-2, -4)}, {"region": Rect2(4, 0, 4, 4), "offset": Vector2(-2, -4)}]
''')
            with patch.object(layers, 'ROOT', root), patch.object(layers, 'OUT', art/'layered'):
                legacy = layers.family(resource, variants)
                original = {p.name:p.read_bytes() for p in (art/'layered/fighter').iterdir()}
                direct = layers.family(resource, {}, compact)
                self.assertEqual(direct['pixel_comparisons'], 20)
                self.assertEqual(legacy['pixel_comparisons'], direct['pixel_comparisons'])
                self.assertEqual(original, {p.name:p.read_bytes() for p in (art/'layered/fighter').iterdir()})
                with self.assertRaisesRegex(ValueError, 'Missing direct'):
                    layers.family(resource, {}, {})
                first = next(iter(compact))
                mask = root / compact[first]['mask']
                mask.write_bytes(mask.read_bytes() + b'changed')
                with self.assertRaisesRegex(ValueError, 'mask changed'):
                    layers.family(resource, {}, compact)
