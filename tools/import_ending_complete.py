#!/usr/bin/env python3
"""Flatten the finite retail ending to native images/palette rows and PCM.

Development only. Original instructions and helpers never enter the runtime.
The existing 940-tick opening is copied byte-for-byte into the new timeline.
"""
import hashlib
import json
import struct
import subprocess
from PIL import Image, ImageOps
from import_intro_menu import ROOT, H, D, REL, facts, SHA, UP, gd

OUT = ROOT/'game/assets/classic/ending_complete'
WORK = ROOT/'work/ending-complete'
NAMES = ['D5', 'E7', 'E8', 'E9', 'EA', 'EB', 'EC', 'EE']
ROOTS = {n: facts['labels']['LAB_00'+n][1] for n in NAMES}


def track(name):
    """Bounded offline draw/hold/secondary-loop paths; reject other operations."""
    p = ROOTS[name]
    poses = []
    loop = loop2 = None
    deferred = None
    for _ in range(1000):
        layers, calls = [], []
        for _ in range(200):
            op, arg = D[p:p+2]
            if op < 128:
                assert op in [0, 4, 8, 20]
                layers.append(dict(slot=op//4, frame=arg, x=struct.unpack_from('>h', D, p+4)[0],
                                   y=struct.unpack_from('>b', D, p+2)[0], flags=D[p+3]))
                p += 6
            elif op in [0x88, 0x94]:
                assert arg > 0
                if op == 0x88: loop = [p+2, arg]
                else: loop2 = [p+2, arg]
                p += 2
            elif op == 0x84:
                assert arg == 0 and REL[p+2] == 2
                deferred = struct.unpack_from('>I', D, p+2)[0]
                assert deferred == ROOTS[name]
                p += 6
            elif op == 0xb4:
                target = struct.unpack_from('>I', D, p+2)[0]
                assert arg == 0 and (REL[p+2], target) in [(0, 3780), (31, 1928), (31, 1918)]
                calls.append([REL[p+2], target]); p += 6
            else:
                assert op == 255 and arg in [0, 254, 255], (name, p, op, arg)
                poses.append(dict(layers=layers, calls=calls))
                if loop and loop[1] > 1:
                    loop[1] -= 1; p = loop[0]
                else:
                    loop = None
                    if deferred is not None:
                        return dict(poses=poses, loop=True, end=p+2)
                    if arg in [254, 255] and loop2 and loop2[1] > 1:
                        loop2[1] -= 1; p = loop2[0]
                    elif arg == 255:
                        return dict(poses=poses, loop=False, end=p+2)
                    else:
                        if arg == 254: loop2 = None
                        p += 2
                break
        else: raise ValueError('No drawing boundary: '+name)
    raise ValueError('Unbounded ending path: '+name)


def main():
    assert subprocess.check_output(['git', '-C', str(UP), 'rev-parse', 'HEAD'], text=True).strip() == 'f0d699a2b92d42d5380429ea9f2d94f7534324ef'
    OUT.mkdir(parents=True, exist_ok=True); WORK.mkdir(parents=True, exist_ok=True)
    sources = {}
    def verify(name):
        folder = ROOT/'game/assets/classic/recovered/A'/name
        meta = json.loads((folder/'sidecar.json').read_text())
        sha = hashlib.sha1((ROOT/'reference/extracted/A'/name).read_bytes()).hexdigest()
        assert sha == meta['source_sha1']; sources[name] = sha
        return folder, meta
    def picture(name, knight=False):
        folder, meta = verify(name)
        pal = meta['palette_rgb12'].copy()
        pal += [0]*(32-len(pal))
        return Image.open(folder/'image.png').copy(), pal, knight
    sprites = {}
    for slot, name in [(0,'dg1.cel'), (1,'li1.cel'), (2,'co1.cel'), (5,'Klift1.CEL')]:
        folder, meta = verify(name)
        sprites[slot] = [Image.open(folder/f'frames/{n:03d}.png').copy() for n in range(meta['frame_count'])]
    folder, _ = verify('bold.f')
    glyphs = [Image.open(folder/f'frames/{n:03d}.png').copy() for n in range(76)]
    charmap = D[11744:11744+96]
    paths = {n:track(n) for n in NAMES}
    assert [len(paths[n]['poses']) for n in ['E7','E8','E9','EA','EC','EE']] == [40,63,3,1,14,93]
    # Guard scene body ranges against the checksum-matched symbol facts as well
    # as the whole retail hash checked by import_intro_menu.
    scene_hashes = {}
    for label, end in [('0037','0039'), ('0039','003B')]:
        h, start = facts['labels']['LAB_'+label]; h2, stop = facts['labels']['LAB_'+end]
        assert h == h2 == 0
        scene_hashes[label] = hashlib.sha256(H[h].data[start:stop]).hexdigest()
    old = json.loads((ROOT/'docs/ending-opening-paths.json').read_text())
    opening = ROOT/'game/assets/classic/ending_opening'
    atlas = Image.open(opening/'indices.png')
    frames = [atlas.crop(((n%8)*320,(n//8)*200,(n%8+1)*320,(n//8+1)*200)) for n in range(old['frames'])]
    keys = {im.tobytes():n for n,im in enumerate(frames)}
    runs = [dict(run) for run in old['runs']]
    tick = old['total_ticks']
    palette_specs = []
    sections = [dict(id='0036-opening',start=0,end=tick)]
    masks = {}
    def blit(im, cel, x, y, mirror=False):
        if mirror: cel = ImageOps.mirror(cel)
        key = (cel.size, cel.tobytes())
        if key not in masks: masks[key] = Image.frombytes('L',cel.size,cel.tobytes()).point(lambda v:255 if v else 0)
        im.paste(cel,(x,y),masks[key])
    def compose(bg, poses):
        im = bg.copy()
        for pose, mirror, depth in sorted(poses,key=lambda row:row[2]):
            for layer in pose['layers']:
                cel = sprites[layer['slot']][layer['frame']]
                x = 120-layer['x']-cel.width if mirror else 160+layer['x']
                blit(im,cel,x,100+depth+layer['y'],mirror)
        return im
    def emit(im, pal, ticks, scene, knight=False, fade_in=0, fade_out=0):
        nonlocal tick
        key = im.tobytes()
        if im.mode != 'RGB': key = Image.frombytes('L',im.size,key).convert('RGB').tobytes()
        if key not in keys: keys[key] = len(frames); frames.append(Image.frombytes('RGB',im.size,key))
        frame = keys[key]
        if runs[-1]['frame']==frame and runs[-1]['scene']==scene:runs[-1]['ticks'] += ticks
        else:runs.append(dict(frame=frame,scene=scene,start=tick,ticks=ticks))
        palette_specs.append(dict(start=tick,ticks=ticks,pal=pal,knight=knight,fade_in=fade_in,fade_out=fade_out))
        tick += ticks
    def section(name, fn):
        start = tick; fn(); sections.append(dict(id=name,start=start,end=tick))
    def job(name,mirror=False,depth=0):return dict(name=name,at=0,mirror=mirror,depth=depth)
    def advance(jobs):
        poses=[]
        for j in jobs:
            path=paths[j['name']]
            if j['at'] >= len(path['poses']):
                if not path['loop']:continue
                j['at']=0
            poses.append((path['poses'][j['at']],j['mirror'],j['depth']));j['at']+=1
        return poses
    bg5,pal5,_ = picture('bg5.piv',True)
    bg5a,pal5a,_ = picture('bg5a.PIV',True)
    jobs=[job('E9'),job('EA')]
    def procession():
        for idx in range(5):
            jobs.append(job('E7',idx%2==1,15 if idx%2 else 5))
            for _ in range(16):emit(compose(bg5,advance(jobs)),pal5,6,'0037-procession',True)
        for _ in range(41):emit(compose(bg5,advance(jobs)),pal5,6,'0037-procession',True)
    section('0037-procession',procession)
    def scene(name,bg,pal,driver,background=None):
        jobs=[job(background)] if background else []
        jobs.append(job(driver))
        def draw():
            for _ in paths[driver]['poses']:
                poses=advance(jobs)
                flashed=any(p['calls']==[[0,3780]] for p,_,_ in poses)
                if flashed:
                    h,at=facts['labels']['LAB_0042'];flash=list(struct.unpack_from('>32H',H[h].data,at))
                    prev=Image.frombytes('RGB',(320,200),frames[runs[-1]['frame']].tobytes())
                    emit(prev,flash,8,name)
                emit(compose(bg,poses),pal,1 if flashed else 8,name,True)
        section(name,draw)
    scene('0037-rise',bg5,pal5,'E8','E9')
    scene('0039-light',bg5a,pal5a,'D5')
    scene('0039-flight',bg5,pal5,'EB','E9')
    scene('0039-arrival',bg5a,pal5a,'EC')
    bg7,pal7,_=picture('bg7.PIV');bg8,pal8,_=picture('bg8.PIV')
    stile=(ROOT/'reference/extracted/A/co.stile').read_bytes();assert len(stile)==960
    sources['co.stile']=hashlib.sha1(stile).hexdigest();codes=struct.unpack('>480H',stile);assert max(codes)<80
    panorama=Image.new('P',(320,1200));panorama.putpalette(bg7.getpalette())
    for n,code in enumerate(codes):
        x,y=code%10*32,code//10*25
        panorama.paste(bg7.crop((x,y,x+32,y+25)),(n%10*32,n//10*25))
    panorama.save(OUT/'panorama.png')
    scroll=[]
    def final_scene():
        progress=1000;step=9;loading=True
        emit(panorama.crop((0,progress,320,progress+200)),pal7,15,'003B-scroll')
        for index,pose in enumerate(paths['EE']['poses']):
            if loading:progress=max(0,progress-step)
            for h,call in pose['calls']:
                assert h==31
                if call==1928:step-=1
                else:loading=False
            assert step>0
            scroll.append(dict(tick=tick,pass_index=index,progress=progress,step=step,loading=loading))
            emit(compose(panorama.crop((0,progress,320,progress+200)),[(pose,False,0)]),pal7,6,'003B-scroll')
        emit(compose(panorama.crop((0,progress,320,progress+200)),[(paths['EE']['poses'][-1],False,0)]),pal7,36,'003B-fade',fade_out=2)
    section('003B-scroll',final_scene)
    def text(im,value,y):
        letters=[glyphs[charmap[ord(c)-32]] for c in value];x=(320-sum(g.width-2 for g in letters))//2
        for cel in letters:blit(im,cel,x,y);x+=cel.width-2
    lines=[];p=facts['labels']['LAB_00B0'][1]
    for _ in range(8):
        assert REL[p]==2
        at,x,y,flags,nxt=struct.unpack_from('>IhhhI',D,p);assert x==0 and flags==1
        lines.append(dict(text=D[at:D.index(0,at)].decode(),y=y));p=nxt
        if not p:break
    else:raise ValueError('Closing text cycle')
    def closing():
        emit(bg8,pal8,32,'003B-closing-fade',fade_in=2)
        emit(bg8,pal8,100,'003B-closing')
        im=bg8.copy()
        for line in lines:text(im,line['text'],line['y'])
        emit(im,pal8,500,'003B-closing-text')
        emit(im,pal8,90,'003B-closing-out',fade_out=6)
    section('003B-closing',closing)
    msg,msgpal,_=picture('message.piv');msgpal[1:6]=[0x800,0x600,0x400,0,0x200]
    text(msg,'The End',95)
    def end_card():
        emit(msg,msgpal,32,'the-end',fade_in=2)
        emit(msg,msgpal,25,'the-end')
        emit(msg,msgpal,36,'menu-fade',fade_out=2)
    section('the-end',end_card)
    columns=16;assert len(frames)<=640 and tick<8192
    atlas=Image.new('RGB',(columns*320,200*((len(frames)+columns-1)//columns)))
    for n,im in enumerate(frames):atlas.paste(im,(n%columns*320,n//columns*200))
    atlas.save(OUT/'indices.png')
    knight_colours=[[0x05d,0x028,0x016,0x003],[0xfa0,0xb40,0x930,0x710],[0x0c5,0x082,0x061,0x040],[0xe00,0x900,0x600,0x300]]
    palettes={}
    for kind,bit in enumerate([16,32,64,8]):
        for phase in [1,2,4]:
            code=128|bit|phase
            oldpal=Image.open(opening/f'palette-{code}.png');rows=list(oldpal.getdata())
            for spec in palette_specs:
                target=spec['pal'].copy()
                if spec['knight']:target[8:12]=knight_colours[kind]
                for t in range(spec['ticks']):
                    if spec['fade_in']:strength=min(15,(t+1)//spec['fade_in'])
                    elif spec['fade_out']:strength=max(0,15-(t+1)//spec['fade_out'])
                    else:strength=15
                    rows.extend(tuple(max(0,((c>>s)&15)-(15-strength))*17 for s in (8,4,0)) for c in target)
            im=Image.new('RGB',(32,tick));im.putdata(rows);im.save(OUT/f'palette-{code}.png');palettes[code]=f'palette-{code}.png'
    exe=WORK/'bake-music'
    subprocess.run(['g++','-O2','-std=c++17','-I'+str(UP/'include'),str(ROOT/'tools/bake_ending_music.cpp'),*[str(UP/f'src/engine/{n}.cpp') for n in ['rnc','modplay','paula']],'-o',str(exe)],check=True)
    subprocess.run([str(exe),str(ROOT/'reference/extracted/A/vmusic.cmp'),str(OUT/'music.wav'),str(tick-old['music_tick']+50)],check=True)
    resource='[ext_resource type="Script" path="res://scripts/content/ending_art.gd" id="script"]\n'
    for id,type,name in [('atlas','Texture2D','indices.png'),('music','AudioStream','music.wav')]+[(f'p{k}','Texture2D',v) for k,v in palettes.items()]:
        resource+=f'[ext_resource type="{type}" path="res://assets/classic/ending_complete/{name}" id="{id}"]\n'
    resource=f'[gd_resource type="Resource" load_steps={len(palettes)+4} format=3]\n'+resource+'[resource]\nscript = ExtResource("script")\natlas = ExtResource("atlas")\nmusic = ExtResource("music")\n'
    for key,value in dict(total_ticks=tick,music_tick=36,moon_tick=460,frames=len(frames),columns=columns,runs=runs,sections=sections).items():resource+=key+' = '+gd(value)+'\n'
    resource+='palettes = {'+', '.join(f'{k}: ExtResource("p{k}")' for k in palettes)+'}\n'
    (OUT/'art.tres').write_text(resource)
    trace=dict(version=1,program_sha1=SHA,source_sha1=sources,scene_sha256=scene_hashes,roots=ROOTS,passes={n:len(v['poses']) for n,v in paths.items()},total_ticks=tick,frames=len(frames),columns=columns,sections=sections,runs=runs,closing_text=lines,scroll=scroll,
               adaptations=['First940ticks preserve the prior native0036 images and all12palette tables.',
                 'Finite offline conversion only; no original program, interpreter, decoder or hardware model at runtime.',
                 'Source speed/gap, five alternating depth5/15 jobs,41bare passes, E8 secondary loop, D5 flashes and EE scroll callbacks retained.',
                 'Co.stile is a320x1200 tile panorama; EE slows its retreat from9 to1 pixels then stops it through source callbacks.',
                 'Source fades, closed captions and closing waits retained; historical disk/loading delays omitted.',
                 'After a blocking8tick D5 flash the new drawing gets one native tick; original immediate flip has no scheduled wait.',
                 'Pacing, sprite restoration/double buffering, palette interrupt phase and audio mix require running-original comparison.'])
    (ROOT/'docs/ending-complete-paths.json').write_text(json.dumps(trace,indent=2)+'\n')
    print('Ending complete:',len(frames),'frames;',tick,'ticks;',len(sections),'sections;',trace['passes'])


if __name__=='__main__':main()
