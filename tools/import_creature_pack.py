#!/usr/bin/env python3
"""Bake additional retail creatures and the exact 24-lair table into native data.

This is a bounded offline draw extractor, not a runtime interpreter. Engine calls,
record writes, motion and secondary jobs are deliberately not executed. Native
mechanics own those effects. Full composite executions remain separate work.
"""
from pathlib import Path
import hashlib
import json
import struct
from PIL import Image
from import_knight_animations import ROOT, MOG_SHA1, parse_hunk_file, gd, read_contact_points
import sys
sys.path.insert(0,str(ROOT/'work/upstream/moonstone-ace/tools'))
from artconv import lzss_decode

BINARY = (ROOT/'reference/extracted/A/mog').read_bytes()
if hashlib.sha1(BINARY).hexdigest() != MOG_SHA1:
    raise ValueError('Untraced retail binary')
HUNKS = parse_hunk_file(BINARY).hunks
DATA = HUNKS[4].data
ROOT_OFFSETS = {'0828': 11334, '0829': 11354, '082A': 11478, '082B': 11674, '082C': 11688, '082D': 11702, '082E': 11722, '082F': 11736, '0830': 11750, '0831': 11764, '0832': 11778, '0833': 11792, '0834': 11806, '0835': 11820, '0836': 11834, '0837': 11980, '083C': 12740, '083D': 12756, '083E': 12776, '083F': 12796, '0840': 12810, '0845': 12908, '0847': 13310, '084F': 14984, '0852': 15044, '0853': 15058, '0854': 15066, '0855': 15074, '0857': 15090, '0859': 15328, '0862': 16384, '086A': 16988, '086C': 17122, '086D': 17130, '086E': 17138, '086F': 17146, '0872': 17754, '0873': 18124, '0874': 18182, '0875': 18238, '0876': 18294, '087E': 18708, '087F': 18968, '0882': 19104, '0883': 19222, '0897': 22948, '0898': 23038, '089A': 23148, '089B': 23186, '089C': 23208, '089D': 23242, '089E': 23264, '08A3': 24454, '08B0': 25722, '08B1': 25768, '08B2': 25814, '08B3': 25860, '08B4': 25906, '08B5': 26172, '08B6': 26800, '08BD': 27684}
REFS = {struct.unpack_from('>I', h.data, o)[0] for h in HUNKS if h.data
        for g in h.reloc32 if g.target_hunk == 4 for o in g.offsets}
# Additional retail roots, checked individually against the relocated operands.
ROOT_OFFSETS.update({'0850':15004,'0851':15012,'0858':15166,'085A':15408,
 '085B':15536,'085C':15556,'085D':15842,'085E':15998,'085F':16128,
 '0860':16184,'0863':16500,'0864':16520,'0865':16540,'0866':16676,
 '0867':16716,'0868':16876,'0869':16956,'086B':17072,
 '0877':18344,'0878':18390,'0879':18442,'087A':18496,'087B':18546,
 '087C':18602,'087D':18658,'0880':19022,'0881':19036,'0884':19412,
 '0886':19886,'0887':20048})
ROOT_OFFSETS.update({'0844':12874,'0846':13076,'0848':13518,'0849':13694,
 '084A':13922,'084B':14006,'084C':14056,'084D':14082,'084E':14090,'0870':17154})
SIZES = {0x80:2,0x84:6,0x88:2,0x8c:8,0x94:2,0x98:6,0xa0:8,
         0xa4:2,0xa8:8,0xac:6,0xb0:6,0xb4:6,0xb8:6,0xbc:2,
         0xc0:2,0xc4:8,0xc8:8,0xcc:2,0xd0:2,0xfd:1,0xfe:1,0xff:2}


def root(label):
    # Explicit retail offsets; upstream offsets are not a universal conversion.
    offset = ROOT_OFFSETS[label]
    if offset not in REFS: raise ValueError(('Unreferenced root',label,offset))
    return offset


def poses_at(start, clean=False):
    if start not in REFS: raise ValueError(('Unreferenced pose',start))
    p, layers, poses, hold, mirror, frameset = start, [], [], 1, False, 2
    loop_start, loop_count, deferred = 0, 0, False
    visited = set()
    while p < start+4096 and len(poses)<160:
        if p in visited: break
        visited.add(p)
        op,arg = DATA[p:p+2]
        if op < 128:
            if op not in (0,4,8,12,16): raise ValueError(('Unknown cel slot',start,p,op))
            if frameset == 2 and not (clean and DATA[p+3]&0x80):
                layers.append(dict(slot=op//4,frame=arg,x=struct.unpack_from('>h',DATA,p+4)[0],
                                   y=struct.unpack_from('>b',DATA,p+2)[0]-52,flags=DATA[p+3]))
            p+=6
            continue
        if op not in SIZES: raise ValueError(('Unhandled retail control',start,p,hex(op)))
        if op==0x88: hold=max(1,arg)
        elif op==0x94: loop_start,loop_count=len(poses),min(8,max(1,arg))
        elif op==0x80: mirror=not mirror if arg==255 else arg==3
        elif op==0xc0: frameset=arg
        elif op==0x84:
            # Native named clips own returns; stop at a deferred transfer's tick.
            if arg==3: break
            deferred=True
        elif op in (0xfd,0xfe): break
        elif op==0xff:
            if layers:
                poses.append(dict(layers=layers,hold=hold,mirror=mirror))
            elif poses:
                poses.append(dict(layers=poses[-1]['layers'],hold=hold,mirror=mirror))
            layers,hold=[],1
            if (arg==0xfe or (arg==0xff and start==14090)) and loop_count:
                poses.extend(poses[loop_start:]*(loop_count-1));loop_count=0
            if arg==255 or deferred: break
        # Retail CC00 is a two-byte control; C4 is an eight-byte field test.
        # Conditional death/gore paths are imported separately, not evaluated.
        p+=SIZES[op]
    if not poses: raise ValueError(('No visible native poses',start))
    return poses


def death_root(label):
    p=root(label)
    for _ in range(40):
        op=DATA[p]
        if op==0xb4: return struct.unpack_from('>I',DATA,p+2)[0]
        p+=6 if op<128 else SIZES[op]
    raise ValueError(('No verified death branch',label))


PROFILES = {
 'dragon_victim':dict(families=['B/KN1.ob','B/KN2.ob','B/KN3.ob','B/KN4.ob','C/KN5.ob'],scene=0x14,region=12,
  clips={'idle':[7540],'walk':[7540],'hurt_a':[7540], 'burn':[7580],
         'defeat':[7580]}, attacks=[]),
 'trogg_hammer':dict(families=['B/TROGGAxe1.CEL','B/TROGGAxe2.CEL'],scene=0x18,region=12,
  clips={'idle':['0828'],'walk':['082B','082C','082D'],'walk_away':['082E','082F','0830','0831'],
         'walk_toward':['0832','0833','0834','0835'],'hammer_swing':['0829'],'hammer_chop':['082A'],
         'hurt_a':['0836'],'hurt_b':['0837'],'defeat':[death_root('0836')]},attacks=['hammer_swing','hammer_chop']),
 'war_beast':dict(families=['C/be1.c','C/be2.c'],scene=0,region=0,
  clips={'idle':['0840'],'walk':['083C','083D','083E','083F'],
         'beast_charge':['083C','083D','083E','083F'],'hurt_a':['0845'],'hurt_b':['0847'],
         'impact':['0844'],'impact_same':['084A'],'impact_opposite':['084B'],
         'execution_same':['0849'],'execution_opposite':['084E'],
         'ejected':['084A','084C'], 'settled':['084C'],
         'defeat':[death_root('0847')], 'defeat_a':[death_root('0845')],
         'defeat_b':[death_root('0847')]},attacks=['beast_charge']),
 'ratman':dict(families=['B/RATMEN1.CEL','B/RATMEN2.CEL'],scene=0x24,region=4,
  clips={'idle':['084F'],'walk':['086C','086D','086E','086F'],
         'rat_strike':['0859'],'rat_bite':['0857'],'rat_leap':['0852','0853','0854','0855'],
         'rat_air':['0852','0853','0854','0855'], 'rat_land':['084F'],
         'rat_perch':['0863','0864'],'tree_anchor':['0870'],
         'rat_hold':['085B'],'rat_throw_finish':['085C'],'rat_escape':['085D'],
         'rat_squeeze':['0865'],'rat_squeeze_loop':['0866'],'rat_squeeze_hit':['0867'],
         'rat_release':['0868'],'rat_squeeze_finish':['0869'],
         'rat_strike_reply':['085A'],'rat_bite_reply':['0858'],
         'victim_strike':['085E'],'victim_bite':['085F'],
         'hurt_a':['0862'],'hurt_b':['086A'],'defeat':[death_root('0862')],
         'defeat_counter':['0860'],'defeat_air':['086B']},attacks=['rat_strike','rat_bite','rat_leap','rat_perch']),
 'mudman':dict(families=['C/Mudmen1.CEL','C/Mudmen2.CEL'],scene=4,region=8,
  clips={'idle':['089A'],'walk':['089B','089C','089D'],'appear':['0897'],
         'mud_reach':['089E'],'mud_grab':['0898'],'hurt_a':['08A3'],'defeat':[death_root('08A3')]},attacks=['mud_reach','mud_grab']),
 'dragon':dict(families=['C/DRAGON1.CEL','C/DRAGON2.CEL',None,None,'C/DRAGON5.CEL'],scene=0x14,region=12,
  clips={'idle':['0882'],'walk':['0873','0874','0875','0876'],
         'dragon_claw':['0872'],'dragon_bite':['0883'],'dragon_breath':['087E'],
         'dragon_flight':['0873','0874','0875','0876','0877','0878','0878','0878'],
         'dragon_lower':['0879','087A','087B','087C','087D','087D','087D','087D'],
         'dragon_foot':['0881'], 'feet_idle':['0880'], 'feet_down':['0887'],
         'ground_fire':['0886'],'execution_bite':['0884'],'hurt_a':['087F'],
         'defeat':[death_root('087F')]},attacks=['dragon_claw','dragon_bite','dragon_breath','dragon_foot','ground_fire']),
 'guardian':dict(families=['C/Demon2.CEL',None,'C/Demon3.CEL','C/Demon4.CEL','C/Demon1.CEL'],scene=8,region=12,
  clips={'idle':['08B0'],'walk':['08B1','08B2','08B3'],'guardian_lunge':['08B4'],
         'guardian_strike':['08B5'],'guardian_grab':['08B6'],'hurt_a':['08BD'],
         'defeat':[death_root('08BD')]},attacks=['guardian_lunge','guardian_strike','guardian_grab'])
}

SCENES={0:[0x776,0x443,0x731,0x520,0x300,0x09a,0xc00],4:[0x332,0xccb,0xb81,0x851,0x630,0xf52,0x900],
        0x18:[0x025,0x004,0x001,0x830,0x400,0xf80,0xc00],
        0x24:[0x653,0x942,0x720,0x500,0xa96,0x875,0xc00],
        0x14:[0xc00,0x976,0x700,0x500,0x754,0xc30,0xa00]}


def image_for(family, frame, profile, clean):
    path=ROOT/'game/assets/classic/recovered'/family
    meta=json.loads((path/'sidecar.json').read_text())
    if hashlib.sha1((ROOT/'reference/extracted'/meta['source']).read_bytes()).hexdigest()!=meta['source_sha1']:
        raise ValueError(('Changed original family',family))
    im=Image.open(path/'frames'/f'{frame:03d}.png');pal=im.getpalette()
    if profile.get('palette_mode')=='troll':
        for i,c in enumerate([0x55a,0x347,0x123,0x001,0xf00,0x800],9):pal[i*3:i*3+3]=[((c>>s)&15)*17 for s in (8,4,0)]
        im.putpalette(pal)
        if clean:
            alpha=bytearray([255]*256);alpha[0]=alpha[15]=0;im.info['transparency']=bytes(alpha)
        return im.convert('RGBA')
    changes={i:c for i,c in enumerate(SCENES.get(profile['scene'],[]),9)}
    if profile['scene']==8:
        changes.update(enumerate(struct.unpack_from('>23H',DATA,28762),9))
    else:
        off={0:28574,4:28600,8:28652,12:28626}[profile['region']]
        changes.update(enumerate(struct.unpack_from('>13H',DATA,off),16))
        if profile['region'] in (8,12): changes.update(enumerate([0xffd,0x998,0x776,0x443],1))
    changes.update(enumerate([0x00a,0x007,0x004],6))
    if profile['scene']==0x14: changes.update(enumerate([0xfc0,0xf80,0xc50],29))
    else: changes[15]=0xc00
    for i,c in changes.items():pal[i*3:i*3+3]=[((c>>s)&15)*17 for s in (8,4,0)]
    im.putpalette(pal)
    if clean:
        alpha=bytearray([255]*256);alpha[0]=0
        # Register15 is ordinary dark red in the Dragon scene, not a universal
        # blood mask. Removing it punches holes through the living Dragon.
        if profile['scene']!=0x14:alpha[15]=0
        im.info['transparency']=bytes(alpha)
    return im.convert('RGBA')


def bake(kind, profile):
    out=ROOT/'game/assets/classic'/kind;out.mkdir(parents=True,exist_ok=True)
    poses,clips,roots=[],{},{}
    for name,labels in profile['clips'].items():
        offsets=[root(x) if isinstance(x,str) else x for x in labels];roots[name]=offsets
        first=len(poses)
        if name in profile.get('pose_overrides',{}):
            poses.extend(profile['pose_overrides'][name])
        else:
            for offset in offsets:poses.extend(poses_at(offset))
        if kind=='war_beast' and name=='impact':
            for pose in poses[first:]: pose['mirror']=False
        indices=list(range(first,len(poses)))
        clips[name]=dict(frames=indices,weights=[p['hold'] for p in poses[first:]],step_ticks=6 if name.startswith('walk') else 1)
        if name in profile['attacks']:
            active=[i for i in indices if any(l['flags']&2 for l in poses[i]['layers'])]
            if not active:active=indices
            if kind=='trogg_hammer' and name=='hammer_chop':
                # Keep the two non-contact drawings between the raised weapon
                # and the blow. Empty contact entries preserve that gap.
                active=list(range(active[0],active[-1]+1))
                clips[name]['phases']={'windup':[i for i in indices if i<active[0]],
                    'active':active,'recovery':[i for i in indices if i>active[-1]]}
            else:
                clips[name]['phases']={'windup':[i for i in indices if i<active[0]] or [indices[0]],
                    'active':active,'recovery':[i for i in indices if i>active[-1]] or [indices[-1]]}
    for n in ['walk_away','walk_toward']:
        if n not in clips:clips[n]=clips['walk'].copy()
    clips['hurt_b']=clips.get('hurt_b',clips['hurt_a'].copy())
    # All atlas bounds derive from actual layer sizes, including large bosses.
    bounds=[];cache={}
    for pose in poses:
        for l in pose['layers']:
            family=profile['families'][l['slot']]
            if family is None:raise ValueError((kind,'Unloaded slot',l))
            key=(family,l['frame'])
            if key not in cache:cache[key]=image_for(*key,profile,False)
            im=cache[key];x=-l['x']-im.width if pose['mirror'] else l['x']
            bounds.append((x,l['y'],x+im.width,l['y']+im.height))
    left=min(b[0] for b in bounds)-4;top=min(b[1] for b in bounds)-4
    w=max(b[2] for b in bounds)-left+4;hh=max(b[3] for b in bounds)-top+4;columns=8
    for clean in [False,True]:
        atlas=Image.new('RGBA',(w*columns,hh*((len(poses)+columns-1)//columns)))
        for i,p in enumerate(poses):
            if clean:
                for name,clean_poses in profile.get('pose_overrides_clean',{}).items():
                    frames=clips[name]['frames']
                    if i in frames:
                        p=clean_poses[min(len(clean_poses)-1,frames.index(i)*len(clean_poses)//len(frames))]
                        break
            for l in p['layers']:
                if clean and l['flags']&0x80:continue
                if clean and kind=='dragon' and i in clips['execution_bite']['frames'] and l['slot']==4:continue
                im=image_for(profile['families'][l['slot']],l['frame'],profile,clean)
                x=l['x']
                if p['mirror']:x=-x-im.width;im=im.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
                atlas.alpha_composite(im,(i%columns*w+x-left,i//columns*hh+l['y']-top))
        atlas.save(out/('clean.png' if clean else 'gore.png'))
    text='''[gd_resource type="Resource" script_class="MoonstoneAnimationSet" load_steps=4 format=3]
[ext_resource type="Script" path="res://scripts/content/animation_set.gd" id="1"]
'''+f'[ext_resource type="Texture2D" path="res://assets/classic/{kind}/gore.png" id="2"]\n'+f'[ext_resource type="Texture2D" path="res://assets/classic/{kind}/clean.png" id="3"]\n'+'''[resource]
script = ExtResource("1")
default_variant = "purple"
atlases = {"purple": ExtResource("2"), "blue": ExtResource("2"), "purple_clean": ExtResource("3"), "blue_clean": ExtResource("3")}
poses = [
'''
    text+=',\n'.join('{"region": Rect2(%d,%d,%d,%d), "offset": Vector2(%d,%d)}'%(i%columns*w,i//columns*hh,w,hh,left,top) for i in range(len(poses)))
    (out/'animations.tres').write_text(text+'\n]\nclips = '+gd(clips)+'\n')
    contacts={}
    hit_text=(ROOT/'reference/extracted/B/collide.hit').read_text().splitlines()
    for slot,family in enumerate(profile['families']):
        if family and any(line.lower()==Path(family).name.lower() for line in hit_text):
            pos=next(i for i,line in enumerate(hit_text) if line.lower()==Path(family).name.lower())+1
            count=0
            while hit_text[pos]!='99':
                n=int(hit_text[pos]);pos+=3 if n else 1;count+=1
            contacts[slot]=read_contact_points(Path(family).name,count)
    attacks={}
    for name in profile['attacks']:
        attacks[name]=[]
        for i in (clips[name]['frames'] if name == 'ground_fire' else clips[name]['phases']['active']):
            points=[]
            for l in poses[i]['layers']:
                if l['flags']&2 and l['slot'] in contacts and l['frame']<len(contacts[l['slot']]):
                    for x,y in contacts[l['slot']][l['frame']]:
                        px=l['x']+x
                        points.append([-px if poses[i]['mirror'] else px,l['y']+y])
            attacks[name].append(dict(points=points,weight=poses[i]['hold']))
        if not any(x['points'] for x in attacks[name]):
            # No invented original contacts: native move geometry explicitly falls back.
            del attacks[name]
    geo='''[gd_resource type="Resource" script_class="MoonstoneCombatGeometry" load_steps=2 format=3]
[ext_resource type="Script" path="res://scripts/content/combat_geometry.gd" id="1"]
[resource]
script = ExtResource("1")
attacks = '''+gd(attacks)+'\n'
    (ROOT/'game/content/generated'/f'{kind}_collision.tres').write_text(geo)
    (out/'provenance.json').write_text(json.dumps(dict(mog_sha1=MOG_SHA1,roots=roots,poses=poses,clips=clips,contacts=attacks,
        families=profile['families'],cue_overrides=profile.get('cue_overrides',{}),frame_paths_version=profile.get('frame_paths_version',0),hit_paths_version=profile.get('hit_paths_version',0),guardian_paths_version=profile.get('guardian_paths_version',0),limits='Original draw layers/holds only. Native timing, motion, AI and composite interactions require running-original comparison.'),indent=2)+'\n')
    print(kind,len(poses),'poses',len(clips),'clips',len(attacks),'contact moves')


def lairs():
    for label,offset in [('07BD',3626),('07BE',3722),('07BF',3818),('07C0',3866)]:
        if offset not in REFS:raise ValueError('Unreferenced original lair table')
    rows=[]
    kinds={0:'beast_lair',4:'mud_lair',24:'axe_lair',28:'hammer_lair',32:'spear_lair',36:'rat_lair',48:'balok_lair',64:'troll_lair'}
    regions={0:'Misty Moors',4:'Great Forest',8:'Wetlands',12:'Northern Wastes'}
    for i in range(24):
        kind,count=struct.unpack_from('>HH',DATA,3626+i*4)
        x,y=struct.unpack_from('>HH',DATA,3722+i*4);region=struct.unpack_from('>H',DATA,3818+i*2)[0]
        # Stable old site IDs preserve all 24 prior chests and cleared/XP flags.
        old_index=i+4 if i<20 else i-20
        ident=['grassland_west','grassland_east','grassland_north','grassland_south'][old_index] if old_index<4 else f'lair_{old_index+1:02d}'
        rows.append(dict(id=ident,source_index=i+1,name=f'{regions[region]} lair {i%6+1}',x=x,y=y,
                         encounter=kinds[kind],region=regions[region],region_code=region,count=count))
    native='''[gd_resource type="Resource" script_class="MoonstoneWorldDefinition" load_steps=3 format=3]
[ext_resource type="Script" path="res://scripts/content/world_definition.gd" id="1"]
[ext_resource type="Resource" path="res://content/generated/classic_map_travel.tres" id="2"]
[resource]
script = ExtResource("1")
content_id = &"journey.v8"
travel_rules = ExtResource("2")
start_position = Vector2i(18,11)
confirm_entry = true
lairs = [
'''
    art=ROOT/'game/assets/classic/recovered/B/test'
    terrain=ROOT/'game/assets/classic/lairs';terrain.mkdir(parents=True,exist_ok=True)
    for row in rows:
        props={k:v for k,v in row.items() if k not in ['x','y']}
        parts=[f'{json.dumps(k)}: {json.dumps(v)}' for k,v in props.items()]
        parts.append(f'"position": Vector2i({row["x"]},{row["y"]})')
        native+='{'+', '.join(parts)+'},\n'
        region=row['region_code'];base={0:7,4:4,8:6,12:5}[region];front={0:0,4:0,8:2,12:3}[region]
        canvas=Image.open(art/f'{base:02d}/image.png').copy()
        sheets={3:Image.open(art/f'{front:02d}/image.png'),4:Image.open(art/'01/image.png')}
        off=3866+(row['source_index']-1)*4
        filename_offset=struct.unpack_from('>I',DATA,off)[0]
        filename=DATA[filename_offset:].split(b'\0',1)[0].decode('ascii')
        blob=(ROOT/'reference/extracted/C'/filename).read_bytes()
        if struct.unpack_from('>I',blob)[0]!=len(blob)-4:raise ValueError('Backdrop length mismatch')
        decoded=lzss_decode(blob[4:]);obstacles=struct.unpack_from('>H',decoded)[0];start=2+obstacles*8
        ended=False
        for pos in range(start,min(start+2400,len(decoded)-5),6):
            code,x,y=struct.unpack_from('>Hhh',decoded,pos);kind,tile=code>>8,code&255
            if kind==255:ended=True;break
            if kind==254:continue
            if tile>=80:raise ValueError(('Unknown tile',filename,tile))
            sheet=sheets[3 if kind==3 else 4]
            tile_image=sheet.crop((tile%10*32,tile//10*25,tile%10*32+32,tile//10*25+25))
            mask=tile_image.point(lambda n:255 if n else 0,'1')
            canvas.paste(tile_image,(x,y),mask)
        if not ended:raise ValueError(('Unterminated backdrop',filename))
        canvas.convert('RGB').save(terrain/(row['id']+'.png'))
        row['source_backdrop']=filename
        row['backdrop_sha1']=hashlib.sha1(blob).hexdigest()
    (ROOT/'game/content/first_journey.tres').write_text(native+']\n')
    dest=ROOT/'game/content/generated/original_lairs.json';dest.write_text(json.dumps(rows,indent=2)+'\n')
    (ROOT/'outputs/original-lair-assignments.json').write_text(json.dumps(dict(mog_sha1=MOG_SHA1,tables=dict(handlers=3626,positions=3722,regions=3818),lairs=rows),indent=2)+'\n')
    print('Verified 24 original lair positions, creature kinds, counts and regions')


def dragon_backdrop():
    # The longplay's Dragon arena is the original sw4 arrangement. This is the
    # selected practice backdrop; regional/cycling arena selection is separate.
    filename='sw4.t'
    blob=(ROOT/'reference/extracted/C'/filename).read_bytes()
    if struct.unpack_from('>I',blob)[0]!=len(blob)-4:raise ValueError('Backdrop length mismatch')
    data=lzss_decode(blob[4:]);count=struct.unpack_from('>H',data)[0]
    art=ROOT/'game/assets/classic/recovered/B/test'
    canvas=Image.open(art/'06/image.png').copy()
    sheets={3:Image.open(art/'02/image.png'),4:Image.open(art/'01/image.png')}
    ended=False
    for pos in range(2+count*8,len(data)-5,6):
        code,x,y=struct.unpack_from('>Hhh',data,pos);kind,tile=code>>8,code&255
        if kind==255:ended=True;break
        if kind==254:continue
        if tile>=80:raise ValueError('Unknown backdrop tile')
        sheet=sheets[3 if kind==3 else 4]
        part=sheet.crop((tile%10*32,tile//10*25,tile%10*32+32,tile//10*25+25))
        canvas.paste(part,(x,y),part.point(lambda n:255 if n else 0,'1'))
    if not ended:raise ValueError('Unterminated Dragon backdrop')
    dest=ROOT/'game/assets/classic/dragon'
    canvas.convert('RGB').save(dest/'arena.png')
    (dest/'arena-provenance.json').write_text(json.dumps({'source':filename,'sha1':hashlib.sha1(blob).hexdigest(),'base':'B/test/06','tiles':['B/test/01','B/test/02'],'selection':'Practice/reference swamp scene; original regional/cycling choice is not implemented'},indent=2)+'\n')


if __name__=='__main__':
    selected=(['war_beast','ratman'] if '--tree-beast' in sys.argv else
              ['dragon','ratman','dragon_victim'] if '--combat-corrections' in sys.argv else PROFILES)
    for kind in selected:
        if kind=='war_beast':
            from import_beast_frames import bake as beast_bake
            beast_bake()
        else:bake(kind,PROFILES[kind])
    if '--tree-beast' not in sys.argv:dragon_backdrop()
    if '--combat-corrections' not in sys.argv and '--tree-beast' not in sys.argv:lairs()
