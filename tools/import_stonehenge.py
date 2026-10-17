#!/usr/bin/env python3
"""Convert the two retail Hen jobs into finite native drawing tracks, offline.

Only the reviewed hunk42 controls are accepted. The looping druid track becomes
three drawings; no original script, CPU or audio bank is used by the game.
"""
import copy
import hashlib
import json
import struct
from PIL import Image
import import_creature_pack as m

ROOT=m.ROOT
OUT=ROOT/'game/assets/classic/stonehenge'
D=m.HUNKS[42].data
RELOC={o:g.target_hunk for g in m.HUNKS[42].reloc32 for o in g.offsets}

def track(root, looping=False):
    poses=[]; cues=[]; cells=[]; hold=1; repeat=None; deferred=None; p=root
    for _ in range(200):
        op,arg=D[p:p+2]
        if op==0:
            cells.append({'frame':arg,'x':160+struct.unpack_from('>h',D,p+4)[0],
                          'y':100+struct.unpack_from('>b',D,p+2)[0]})
            p+=6; continue
        if op==0x88: hold=arg; p+=2; continue
        if op==0x94: repeat=(len(poses),len(cues),arg); p+=2; continue
        if op==0xa4:
            assert arg==157
            cues.append({'pose':len(poses),'sequence':157,'optional':False,'source':p})
            p+=2; continue
        if op==0xb0:
            assert RELOC[p+2]==0 and struct.unpack_from('>I',D,p+2)[0]==43392
            assert m.HUNKS[0].data[43392:43408]==bytes.fromhex('4eb90000a1aeb07c00326e0a303c009d')
            cues.append({'pose':len(poses),'sequence':157,'optional':True,'source':p})
            p+=6; continue
        if op==0x84:
            assert looping and arg==0 and RELOC[p+2]==42
            deferred=struct.unpack_from('>I',D,p+2)[0]
            assert deferred==root
            p+=6;continue
        assert op==255 and cells, (p,op)
        poses.append({'ticks':hold*6,'layers':cells});cells=[];hold=1
        if arg==254:
            first,ec,n=repeat; segment=copy.deepcopy(poses[first:]); events=copy.deepcopy(cues[ec:])
            for k in range(1,n):
                poses.extend(copy.deepcopy(segment))
                cues.extend(dict(e,pose=e['pose']+len(segment)*k) for e in events)
            repeat=None
        if deferred is not None:
            assert looping;break
        if arg==255:
            assert not looping;break
        p+=2
    else:raise ValueError('Unbounded Hen path')
    for cue in cues: cue['tick']=sum(pose['ticks'] for pose in poses[:cue['pose']])
    return poses,cues

def text_list(hunk,root):
    data=m.HUNKS[hunk].data
    reloc={o:g.target_hunk for g in m.HUNKS[hunk].reloc32 for o in g.offsets}
    rows=[];p=root
    for _ in range(10):
        s,x,y,style,n=struct.unpack_from('>IHHHI',data,p)
        assert reloc[p]==hunk and x==0 and style==1
        rows.append({'text':data[s:data.index(0,s)].decode('ascii'),'y':y})
        if not n:return rows
        assert reloc[p+10]==hunk;p=n
    raise ValueError('Unbounded text list')

def main():
    OUT.mkdir(parents=True,exist_ok=True)
    sources={}
    def verify(name):
        folder=ROOT/'game/assets/classic/recovered'/name
        meta=json.loads((folder/'sidecar.json').read_text())
        sha=hashlib.sha1((ROOT/'reference/extracted'/name).read_bytes()).hexdigest()
        assert sha==meta['source_sha1'];sources[name]=sha
        return folder,meta
    folder,meta=verify('C/hen1.p')
    colours=meta['palette_rgb12'].copy()
    # LAB_04CA, kind0, four words starting at palette byte16; omit shade1.
    colours[8:12]=[0x05d,0x028,0x016,0x003]
    palette=[((c>>s)&15)*17 for c in colours for s in (8,4,0)]+[0]*672
    im=Image.open(folder/'image.png');im.putpalette(palette);im.convert('RGB').save(OUT/'background.png')
    folder,meta=verify('C/hen1.c')
    main,cues=track(516);druids,empty=track(792,True)
    assert not empty and len(main)==34 and sum(x['ticks'] for x in main)==528
    assert len(druids)==3 and sum(x['ticks'] for x in druids)==18
    frames=sorted({l['frame'] for p in main+druids for l in p['layers']})
    for frame in frames:
        im=Image.open(folder/f'frames/{frame:03d}.png');im.putpalette(palette);im.info['transparency']=0
        im.convert('RGBA').save(OUT/f'{frame:03d}.png')
    node=struct.unpack_from('>hhh',m.HUNKS[2].data,142)
    assert node==(27,88,155)
    # Verify blessing operands in the retail program, rather than source offsets.
    code=m.HUNKS[0].data
    blessing=bytes.fromhex('0c28000500496706062800010049')
    assert code.count(blessing)==1
    b=code.index(blessing)
    assert code[b+18:b+30]==bytes.fromhex('316800540050117c00000082')
    trace={'version':1,'mog_sha1':m.MOG_SHA1,'sources':sources,'node':{'hunk':2,'offset':142,'id':27,'x':88,'y':155},
        'tracks':{'knight':{'hunk':42,'root':516,'poses':34,'ticks':528},'druids':{'hunk':42,'root':792,'poses':3,'cycle_ticks':18}},
        'cues':cues,'opening_sequences':[158,159,160],'blessing_operand_offset':code.index(blessing),
        'greeting':text_list(4,420),'prelude':text_list(42,0),
        'adaptations':['Consume one selected magic item; do not reproduce the original sound-channel-dependent second decrement.',
            'Native 50Hz clock maps each source drawing pass to six ticks; original job ordering, fades and sound mix remain unverified.',
            'Skip completes an accepted offering once. Saved phase/tick resumes without another debit or blessing.',
            'Life-drain curse cell is cleared; other unimplemented curse mechanics are not invented.',
            '04BA/sequence99 belongs to earlier dice scripts in hunk42, not either Hen track.']}
    (ROOT/'docs/stonehenge-paths.json').write_text(json.dumps(trace,indent=2)+'\n')
    declarations='[ext_resource type="Script" path="res://scripts/content/stonehenge_art.gd" id="1"]\n'
    declarations+='[ext_resource type="Texture2D" path="res://assets/classic/stonehenge/background.png" id="bg"]\n'
    for frame in frames:declarations+=f'[ext_resource type="Texture2D" path="res://assets/classic/stonehenge/{frame:03d}.png" id="f{frame}"]\n'
    out=f'[gd_resource type="Resource" load_steps={len(frames)+3} format=3]\n'+declarations
    out+='[resource]\nscript = ExtResource("1")\nbackground = ExtResource("bg")\n'
    out+='frames = {'+', '.join(f'{f}: ExtResource("f{f}")' for f in frames)+'}\n'
    for key,value in [('knight',main),('druids',druids),('cues',cues),('greeting',trace['greeting']),('prelude',trace['prelude'])]:out+=key+' = '+m.gd(value).replace('False','false').replace('True','true')+'\n'
    (OUT/'art.tres').write_text(out)
    print('Stonehenge: verified2tracks/37drawings,528tick ritual,18tick druids,10cues, original node88,155')

if __name__=='__main__':main()
