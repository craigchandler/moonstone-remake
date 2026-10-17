#!/usr/bin/env python3
"""Bake verified retail Balok poses and contacts into native resources."""
import hashlib,json,struct
from PIL import Image
from import_knight_animations import ROOT,MOG_SHA1,parse_hunk_file,read_poses,read_contact_points,gd
ROOTS={'idle':[20062],'crouch':[20326],'leap_prepare':[20152],'leap_air':[20178],
       'balok_swipe':[20218],'balok_maul':[20354],'hurt_a':[20484],'defeat':[20542]}
PHASES={'balok_swipe':{'windup':[0],'active':[1,2],'recovery':[3,4]},
        'balok_maul':{'windup':[0],'active':[1,2],'recovery':[3]}}
CELL_W,CELL_H,AX,AY,COLUMNS=448,224,160,160,4


def main():
    binary=(ROOT/'reference/extracted/A/mog').read_bytes()
    if hashlib.sha1(binary).hexdigest()!=MOG_SHA1:raise ValueError('Untraced retail MOG')
    hunks=parse_hunk_file(binary).hunks
    refs={struct.unpack_from('>I',h.data,o)[0] for h in hunks for g in h.reloc32 if g.target_hunk==4 for o in g.offsets}
    poses,clips=[],{}
    for name,roots in ROOTS.items():
        first=len(poses)
        for root in roots:
            if root not in refs:raise ValueError(f'Unreferenced root {root}')
            poses.extend(read_poses(hunks[4],root))
        clips[name]={'frames':list(range(first,len(poses))),'weights':[p['hold'] for p in poses[first:]],'step_ticks':6}
        if name in PHASES:clips[name]['phases']={p:[first+i for i in indices] for p,indices in PHASES[name].items()}
    frames=[clips[n]['frames'][0] for n in ['leap_prepare','leap_air','crouch']]
    leap={'frames':frames,'weights':[1,1,1],'step_ticks':1,'phases':{p:[frames[i]] for i,p in enumerate(['windup','active','recovery'])}}
    clips['balok_pounce']=leap;clips['balok_hop']=leap.copy()
    for name in ['walk','walk_away','walk_toward']:clips[name]=clips['idle'].copy()
    source=ROOT/'game/assets/classic/recovered/C';families=['Balok1.CEL','Balok2.CEL','Balok3.CEL']
    source_hashes={}
    for family in families:
        meta=json.loads((source/family/'sidecar.json').read_text())
        raw=ROOT/'reference/extracted'/meta['source'];sha=hashlib.sha1(raw.read_bytes()).hexdigest()
        if sha!=meta['source_sha1']:raise ValueError('Changed source '+family)
        source_hashes[meta['source']]=sha
    out=ROOT/'game/assets/classic/balok';out.mkdir(parents=True,exist_ok=True)
    colours=[0xF96,0xC63,0x930,0x842,0x521,0xF63,0xC00]
    for clean in [False,True]:
        atlas=Image.new('RGBA',(COLUMNS*CELL_W,((len(poses)+COLUMNS-1)//COLUMNS)*CELL_H))
        for i,pose in enumerate(poses):
            rendered=pose
            if rendered['mirror']:raise ValueError('Untraced internal Balok mirroring')
            for l in rendered['layers']:
                if clean and l['flags']&0x80:continue
                im=Image.open(source/families[l['slot']]/'frames'/f'{l["frame"]:03d}.png');pal=im.getpalette()
                for entry,c in enumerate(colours,9):pal[entry*3:entry*3+3]=[((c>>s)&15)*17 for s in [8,4,0]]
                im.putpalette(pal)
                if clean:
                    alpha=bytearray([255]*256);alpha[0]=alpha[15]=0;im.info['transparency']=bytes(alpha)
                im=im.convert('RGBA');x,y=AX+l['x'],AY+l['y']
                if x<0 or y<0 or x+im.width>CELL_W or y+im.height>CELL_H:raise ValueError(('atlas bounds',i,l))
                atlas.alpha_composite(im,(i%COLUMNS*CELL_W+x,i//COLUMNS*CELL_H+y))
        atlas.save(out/('clean.png' if clean else 'gore.png'))
    resource='''[gd_resource type="Resource" script_class="MoonstoneAnimationSet" load_steps=4 format=3]
[ext_resource type="Script" path="res://scripts/content/animation_set.gd" id="1"]
[ext_resource type="Texture2D" path="res://assets/classic/balok/gore.png" id="2"]
[ext_resource type="Texture2D" path="res://assets/classic/balok/clean.png" id="3"]
[resource]
script = ExtResource("1")
default_variant = "purple"
atlases = {"purple": ExtResource("2"), "blue": ExtResource("2"), "purple_clean": ExtResource("3"), "blue_clean": ExtResource("3")}
poses = [
'''
    resource+=',\n'.join('{"region": Rect2(%d, %d, %d, %d), "offset": Vector2(%d, %d)}'%(i%COLUMNS*CELL_W,i//COLUMNS*CELL_H,CELL_W,CELL_H,-AX,-AY) for i in range(len(poses)))
    (out/'animations.tres').write_text(resource+'\n]\nclips = '+gd(clips)+'\n')
    source_contacts=read_contact_points('Balok1.cel',31);attacks={}
    for name in PHASES:
        frames=[]
        for i in clips[name]['phases']['active']:
            p=poses[i];points=[]
            for l in p['layers']:
                if l['flags']&2:
                    if l['slot']!=0:raise ValueError('Unexpected Balok contact family')
                    points.extend([[l['x']+x,l['y']+y] for x,y in source_contacts[l['frame']]])
            if not points:raise ValueError(('missing contacts',name,i))
            frames.append({'points':points,'weight':p['hold']})
        attacks[name]=frames
    (ROOT/'game/content/generated/balok_collision.tres').write_text('''[gd_resource type="Resource" script_class="MoonstoneCombatGeometry" load_steps=2 format=3]
[ext_resource type="Script" path="res://scripts/content/combat_geometry.gd" id="1"]
[resource]
script = ExtResource("1")
attacks = '''+gd(attacks)+'\n')
    (out/'provenance.json').write_text(json.dumps({'mog_sha1':MOG_SHA1,'source_hashes':source_hashes,'roots':ROOTS,'poses':poses,'clips':clips,'contacts':attacks,'palette_9_15':colours,
        'limits':'Native timing/trajectory/landing collision are provisional. No recovered pounce contact table; landing uses native proximity. Clean variants omit the original gore layers and blood colour. Shadow jobs are replaced by native ground shadows.'},indent=2)+'\n')
    print(f'Imported Balok: {len(poses)} poses, {len(clips)} clips')

if __name__=='__main__':main()
