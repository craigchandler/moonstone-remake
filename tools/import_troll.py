#!/usr/bin/env python3
"""Bake the retail troll's verified finite draws, with no runtime interpreter."""
import hashlib
import json
import struct
from PIL import Image
from import_knight_animations import ROOT, MOG_SHA1, parse_hunk_file, read_poses, read_contact_points, gd

ROOTS = {"idle": [24610], "walk": [24630,24650,24670,24690],
         "troll_sweep": [24710], "troll_smash": [24792], "hurt_a": [25038], "defeat": [25122]}
PHASES = {"troll_sweep": {"windup":[0], "active":[1,2], "recovery":[0]},
          "troll_smash": {"windup":[0,1,2,3], "active":[4], "recovery":[5]}}
CELL_W, CELL_H, AX, AY, COLUMNS = 512, 288, 192, 224, 4


def main():
    binary=(ROOT/'reference/extracted/A/mog').read_bytes()
    if hashlib.sha1(binary).hexdigest()!=MOG_SHA1: raise ValueError('Untraced retail MOG')
    hunks=parse_hunk_file(binary).hunks
    # Troll attacks/reaction are referenced by the original stalker overlay, hunk 40.
    refs={struct.unpack_from('>I',h.data,o)[0] for h in hunks for g in h.reloc32
          if g.target_hunk==4 for o in g.offsets}
    poses,clips=[],{}
    for name, offsets in ROOTS.items():
        first=len(poses)
        for offset in offsets:
            if offset not in refs: raise ValueError(f'Unreferenced root {offset}')
            poses.extend(read_poses(hunks[4],offset))
        clips[name]={'frames':list(range(first,len(poses))), 'weights':[p['hold'] for p in poses[first:]], 'step_ticks':8 if name=='walk' else 1}
        if name in PHASES: clips[name]['phases']={phase:[first+i for i in indices] for phase,indices in PHASES[name].items()}
    # No separate directional walk artwork exists in this short original walk table.
    clips['walk_away']=clips['walk'].copy();clips['walk_toward']=clips['walk'].copy()
    families=['TROLL1.CEL','TROLL2.CEL']
    source=ROOT/'game/assets/classic/recovered/B'
    out=ROOT/'game/assets/classic/giant_troll';out.mkdir(parents=True,exist_ok=True)
    colours=[0x55A,0x347,0x123,0x001,0xF00,0x800] # original scene kind 0x40, registers 9..14
    for clean in [False,True]:
        atlas=Image.new('RGBA',(COLUMNS*CELL_W,((len(poses)+COLUMNS-1)//COLUMNS)*CELL_H))
        for index,pose in enumerate(poses):
            if pose['mirror']: raise ValueError('Untraced internal troll mirroring')
            for layer in pose['layers']:
                if clean and layer['flags'] & 0x80: continue
                im=Image.open(source/families[layer['slot']]/'frames'/f'{layer["frame"]:03d}.png')
                palette=im.getpalette()
                for entry,colour in enumerate(colours,9): palette[entry*3:entry*3+3]=[((colour>>s)&15)*17 for s in [8,4,0]]
                im.putpalette(palette)
                if clean:
                    alpha=bytearray([255]*256);alpha[0]=alpha[15]=0;im.info['transparency']=bytes(alpha)
                im=im.convert('RGBA');x,y=AX+layer['x'],AY+layer['y']
                if x<0 or y<0 or x+im.width>CELL_W or y+im.height>CELL_H: raise ValueError(('atlas bounds',index,layer))
                atlas.alpha_composite(im,(index%COLUMNS*CELL_W+x,index//COLUMNS*CELL_H+y))
        atlas.save(out/('clean.png' if clean else 'gore.png'))
    text='''[gd_resource type="Resource" script_class="MoonstoneAnimationSet" load_steps=4 format=3]
[ext_resource type="Script" path="res://scripts/content/animation_set.gd" id="1"]
[ext_resource type="Texture2D" path="res://assets/classic/giant_troll/gore.png" id="2"]
[ext_resource type="Texture2D" path="res://assets/classic/giant_troll/clean.png" id="3"]
[resource]
script = ExtResource("1")
default_variant = "purple"
atlases = {"purple": ExtResource("2"), "blue": ExtResource("2"), "purple_clean": ExtResource("3"), "blue_clean": ExtResource("3")}
poses = [
'''
    text+=',\n'.join('{"region": Rect2(%d, %d, %d, %d), "offset": Vector2(%d, %d)}'%(i%COLUMNS*CELL_W,i//COLUMNS*CELL_H,CELL_W,CELL_H,-AX,-AY) for i in range(len(poses)))
    (out/'animations.tres').write_text(text+'\n]\nclips = '+gd(clips)+'\n')
    contacts=[read_contact_points('Troll1.cel',48),read_contact_points('Troll2.cel',14)]
    attacks={}
    for name in PHASES:
        frames=[]
        for i in clips[name]['phases']['active']:
            pose=poses[i];points=[]
            for layer in pose['layers']:
                if layer['flags']&2: points.extend([[layer['x']+x,layer['y']+y] for x,y in contacts[layer['slot']][layer['frame']]])
            if not points: raise ValueError(('missing attack contacts',name,i))
            frames.append({'points':points,'weight':pose['hold']})
        attacks[name]=frames
    (ROOT/'game/content/generated/troll_collision.tres').write_text('''[gd_resource type="Resource" script_class="MoonstoneCombatGeometry" load_steps=2 format=3]
[ext_resource type="Script" path="res://scripts/content/combat_geometry.gd" id="1"]
[resource]
script = ExtResource("1")
attacks = '''+gd(attacks)+'\n')
    (out/'provenance.json').write_text(json.dumps({'mog_sha1':MOG_SHA1,'roots':ROOTS,'poses':poses,'clips':clips,'contacts':attacks,
        'palette_9_14':colours, 'timing':'Native phases, movement and cooldown provisional; original holds preserved. Sweep recovery reuses its original idle pose.'},indent=2)+'\n')
    print(f'Imported giant troll: {len(poses)} poses, {len(clips)} clips')


if __name__=='__main__': main()
