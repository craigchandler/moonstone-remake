#!/usr/bin/env python3
"""Offline, bounded retail ending0036 conversion. Runtime sees images/PCM only.

The verified finite E6/ED paths and five four-pass stage loops become a native
timeline. All source operands/relocations are checked. No general original VM
or executable is bundled. Palette rows bake the phase, knight, ramps and fades.
"""
import hashlib
import json
import struct
import subprocess
from import_support import require_reference, audio_helper
from pathlib import Path
from PIL import Image, ImageOps
from import_knight_animations import ROOT, parse_hunk_file, gd

UP=ROOT/'work/upstream/moonstone-ace'
OUT=ROOT/'game/assets/classic/ending_opening'
WORK=ROOT/'work/ending-opening'
PROGRAM_SHA1='8956a1edbecee7bdd9b8b3636975cbeb033d21b5'
ROOTS={'e6':8732,'ed':10718,'db':6958,'dc':6996,'dd':7034,'df':7554,'e1':7942}
raw=(ROOT/'reference/extracted/A/program').read_bytes()
assert hashlib.sha1(raw).hexdigest()==PROGRAM_SHA1
HUNKS=parse_hunk_file(raw).hunks
D=HUNKS[2].data
RELOC={o:g.target_hunk for g in HUNKS[2].reloc32 for o in g.offsets}

def track(name):
    p=ROOTS[name];passes=[];layers=[];repeat=1;deferred=None;calls=[]
    for _ in range(150):
        op,arg=D[p:p+2]
        if op<128:
            assert op==(12 if name=='e6' else 16)
            layers.append({'frame':arg,'y':100+struct.unpack_from('>b',D,p+2)[0],
                           'x':struct.unpack_from('>h',D,p+4)[0],'flags':D[p+3]})
            p+=6;continue
        if op==0x88:
            assert arg>0;repeat=arg;p+=2;continue
        if op==0x84:
            assert arg==0 and RELOC[p+2]==2 and struct.unpack_from('>I',D,p+2)[0]==ROOTS[name]
            deferred=ROOTS[name];p+=6;continue
        if op==0xb4:
            target=struct.unpack_from('>I',D,p+2)[0]
            assert name=='e6' and arg==0 and RELOC[p+2]==0 and target in [2268,3814]
            calls.append(target);p+=6;continue
        assert op==255 and arg in [0,255] and layers,(name,p,op,arg)
        for k in range(repeat):passes.append({'layers':layers,'calls':calls if k==0 else []})
        layers=[];calls=[];repeat=1;p+=2
        if arg==255:
            assert bool(deferred)==(name not in ['e6','ed'])
            return passes
    raise ValueError('Unbounded ending path '+name)

def step(col,target):
    return sum((a+(a<b)-(a>b))<<s for s in (0,4,8) for a,b in [((col>>s)&15,(target>>s)&15)])

def main():
    require_reference(UP, 'f0d699a2b92d42d5380429ea9f2d94f7534324ef')
    OUT.mkdir(parents=True,exist_ok=True);WORK.mkdir(parents=True,exist_ok=True)
    source={};recovered=ROOT/'game/assets/classic/recovered/A'
    def verify(name):
        folder=recovered/name;meta=json.loads((folder/'sidecar.json').read_text())
        sha=hashlib.sha1((ROOT/'reference/extracted/A'/name).read_bytes()).hexdigest()
        assert sha==meta['source_sha1'];source[name]=sha
        return folder,meta
    b1,b1m=verify('bg2a.PIV');b2,b2m=verify('bg3.PIV')
    ha,ham=verify('ha1.cel');da,dam=verify('da1.cel');ov,ovm=verify('ov1.cel')
    sprites={key:[Image.open(folder/f'frames/{n:03d}.png').copy() for n in range(meta['frame_count'])]
             for key,folder,meta in [('ha',ha,ham),('da',da,dam),('ov',ov,ovm)]}
    paths={name:track(name) for name in ROOTS}
    assert len(paths['e6'])==34 and len(paths['ed'])==40
    assert all(len(paths[n])==4 for n in ['db','dc','dd','df','e1'])
    # Retail scene0036 sets gap2 for E6, then gap4 and speed8 for ED.
    code=HUNKS[0].data
    assert code[2360:2376]==bytes.fromhex('33fc00010000024633fc000200000ec2')
    assert bytes.fromhex('23fc000000040000009a') in code[2360:2746]
    assert code[3814:3884]==bytes.fromhex('70144eb900000658613c70024eb900000658613270144eb900000658612870054eb900000658611e700a4eb900000658611470054eb900000658610a70324eb9000006584e75')
    # Indexed images preserve all 32 colour registers for native palette lookup.
    frames=[];frame_keys={}
    def blit(dst,key,frame,x,y,mirror=False):
        im=sprites[key][frame]
        if mirror:im=ImageOps.mirror(im)
        mask=Image.frombytes('L',im.size,im.tobytes()).point(lambda v:255 if v else 0)
        dst.paste(im,(x,y),mask)
    def compose(bg,layers,key,overlay=False):
        im=bg.copy()
        for layer in layers:
            mirror=layer.get('mirror',False)
            x=(120-layer['x']-sprites[key][layer['frame']].width) if mirror else 160+layer['x']
            blit(im,key,layer['frame'],x,layer['y'],mirror)
        if overlay:
            for frame,x,y in [(0,0,56),(3,51,134)]:blit(im,'ov',frame,x,y)
        pixels=im.tobytes()
        if pixels not in frame_keys:
            frame_keys[pixels]=len(frames)
            # The shader reads raw register indices from R; never colour-manage.
            frames.append(Image.frombytes('L',im.size,pixels).convert('RGB'))
        return frame_keys[pixels]
    bg1=Image.open(b1/'image.png');bg2=Image.open(b2/'image.png')
    timeline=[];flash_ticks=[];ramp_tick=-1
    def emit(frame,ticks,scene):
        timeline.extend([{'frame':frame,'scene':scene} for _ in range(ticks)])
    # Source fade-out wait36. The native handoff begins black; the just-read quest
    # text is handled by QuestView during this lead-in, outside the indexed film.
    black=Image.new('P',(320,200));black.putpalette(bg1.getpalette())
    emit(compose(black,[],'ha'),36,'handoff')
    music_tick=len(timeline)
    previous=None
    for pose in paths['e6']:
        blocked=False
        for call in pose['calls']:
            if call==2268:ramp_tick=len(timeline)
            else:
                assert previous is not None
                # Flash series is blocking: previous screen remains visible;
                # the pass after124 elapsed ticks owes no extra8-tick wait.
                for wait in [20,2,20,5,10,5]:
                    emit(previous,wait,'transformation')
                    flash_ticks.extend(range(len(timeline),len(timeline)+2))
                    emit(previous,2,'transformation')
                emit(previous,50,'transformation');blocked=True
        frame=compose(bg1,pose['layers'],'ha',True)
        if not blocked:emit(frame,8,'transformation')
        previous=frame
    fade_tick=len(timeline)
    emit(previous,36,'fade')
    moon_tick=len(timeline)
    # Stage jobs are spawned A then B; equal depth retains source order.
    for index,pose in enumerate(paths['ed']):
        layers=[]
        for mirror in [False,True]:
            for name in ['dc','dd','db','df','e1']:
                layers.extend(dict(l,mirror=mirror) for l in paths[name][index%4]['layers'])
        layers.extend(pose['layers'])
        emit(compose(bg2,layers,'da'),12,'ascent')
    total=len(timeline)
    # Static lookup table, no original scripts or call addresses at runtime.
    runs=[]
    for tick,frame in enumerate(timeline):
        if not runs or any(runs[-1][k]!=frame[k] for k in ['frame','scene']):runs.append(dict(frame,start=tick,ticks=1))
        else:runs[-1]['ticks']+=1
    columns=8;atlas=Image.new('RGB',(320*columns,200*((len(frames)+columns-1)//columns)))
    for n,im in enumerate(frames):atlas.paste(im,(n%columns*320,n//columns*200))
    atlas.save(OUT/'indices.png')
    phase_ramps={1:[0x111,0x333,0x555],2:[0xc50,0x920,0x700],4:[0xd60,0xf80,0xfa0]}
    phase_base={1:[0,0x222,0x444],2:[0xf80,0xc50,0x920],4:[0xb40,0xd60,0xf80]}
    knights=[[0x05d,0x028,0x016,0x003],[0xfa0,0xb40,0x930,0x710],[0x0c5,0x082,0x061,0x040],[0xe00,0x900,0x600,0x300]]
    flash=[0,0xfff,0xfff,0,0,0,0,0,0xfff,0xfff,0,0,0,0,0,0,0,0xfff,0,0,0xfff,0,0xfff,0,0,0xfff,0xfff,0,0,0,0,0]
    palettes={}
    for kind in range(4):
        for phase in [1,2,4]:
            key=128|[16,32,64,8][kind]|phase
            first=b1m['palette_rgb12'].copy();first[8:12]=knights[kind]
            for i,v in zip([12,15,23],phase_base[phase]):first[i]=v
            second=b2m['palette_rgb12'].copy();second[8:12]=knights[kind]
            live=[0]*32;back=[first[i] for i in [12,15,23]];targets=phase_ramps[phase].copy()
            rows=[]
            for tick in range(total):
                if tick==moon_tick:live=[0]*32
                if music_tick<=tick<fade_tick:
                    if (tick-music_tick)%2==1 and tick<music_tick+32:live=[step(c,t) for c,t in zip(live,first)]
                    if tick>=ramp_tick and (tick-ramp_tick)%5==4:
                        for n,i in enumerate([12,15,23]):
                            live[i]=step(live[i],targets[n])
                            if live[i]==targets[n]:targets[n],back[n]=back[n],targets[n]
                elif fade_tick<=tick<moon_tick and (tick-fade_tick)%2==1:live=[step(c,0) for c in live]
                elif tick>=moon_tick and (tick-moon_tick)%2==1 and tick<moon_tick+32:live=[step(c,t) for c,t in zip(live,second)]
                row=flash if tick in flash_ticks else live
                rows.extend(tuple(((c>>s)&15)*17 for s in (8,4,0)) for c in row)
            picture=Image.new('RGB',(32,total));picture.putdata(rows);picture.save(OUT/f'palette-{key}.png')
            palettes[key]=f'palette-{key}.png'
    music=ROOT/'reference/extracted/A/vmusic.cmp';source['vmusic.cmp']=hashlib.sha1(music.read_bytes()).hexdigest()
    binary=WORK/'bake-music'
    binary=audio_helper(ROOT,UP,WORK,'bake-module',[ROOT/'tools/bake_ending_music.cpp',*[UP/f'src/engine/{n}.cpp' for n in ['rnc','modplay','paula']]])
    subprocess.run([str(binary),str(music),str(OUT/'music.wav'),str(total-music_tick+50)],check=True)
    trace={'version':1,'program_sha1':PROGRAM_SHA1,'source_sha1':source,'roots':ROOTS,'passes':{k:len(v) for k,v in paths.items()},
           'total_ticks':total,'music_tick':music_tick,'ramp_tick':ramp_tick,'fade_tick':fade_tick,'moon_tick':moon_tick,
           'flash_ticks':flash_ticks,'frames':len(frames),'runs':runs,'knight_phase_codes':sorted(palettes),
           'adaptations':['50Hz native finite playback;8ticks/E6 pass and12ticks/ED pass from speed+gap operands.',
            'First36tick fade begins on the native quest panel; original ending loading-caption/disk delay omitted.',
            'Blocking flash series holds the previous screen for124ticks; elapsed time consumes that pass wait.',
            'Scene0036 only. Later0037/0039/003B remain pending; completion uses a labelled native result.',
            'Original double-buffer restoration/job interleaving, palette interrupt phase and analog sound mix require running-original comparison.',
            'Retail FLT4 module decoded/sanitised/rendered offline to48kHz16bit stereo PCM; no normalisation/filter,40sample DMA delay.']}
    (ROOT/'docs/ending-opening-paths.json').write_text(json.dumps(trace,indent=2)+'\n')
    ext='[ext_resource type="Script" path="res://scripts/content/ending_art.gd" id="1"]\n'
    ext+='[ext_resource type="Texture2D" path="res://assets/classic/ending_opening/indices.png" id="atlas"]\n'
    ext+='[ext_resource type="AudioStream" path="res://assets/classic/ending_opening/music.wav" id="music"]\n'
    for key,name in palettes.items():ext+=f'[ext_resource type="Texture2D" path="res://assets/classic/ending_opening/{name}" id="p{key}"]\n'
    text=f'[gd_resource type="Resource" load_steps={len(palettes)+4} format=3]\n'+ext+'[resource]\nscript = ExtResource("1")\natlas = ExtResource("atlas")\nmusic = ExtResource("music")\n'
    for key,value in [('total_ticks',total),('music_tick',music_tick),('moon_tick',moon_tick),('frames',len(frames)),('runs',runs)]:text+=key+' = '+gd(value)+'\n'
    text+='palettes = {'+', '.join(f'{key}: ExtResource("p{key}")' for key in palettes)+'}\n'
    (OUT/'art.tres').write_text(text)
    print(f'Ending0036: {len(frames)} indexed composites,12winner/phase palettes,{total} ticks,2 scenes,6flashes and native music')

if __name__=='__main__':main()
