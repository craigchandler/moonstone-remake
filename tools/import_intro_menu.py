#!/usr/bin/env python3
"""Bounded offline opening conversion; Godot gets native pictures, font and PCM.

Only the verified retail D2..E5 draw/hold paths are flattened here. Runtime has
no original script decoder, program, synth/module player or disk dependency.
"""
from pathlib import Path
from PIL import Image, ImageOps
import hashlib,json,struct,subprocess,wave
from import_knight_animations import ROOT,parse_hunk_file,gd

UP=ROOT/'work/upstream/moonstone-ace';OUT=ROOT/'game/assets/classic/intro_menu';WORK=ROOT/'work/intro-menu'
SHA='8956a1edbecee7bdd9b8b3636975cbeb033d21b5'
raw=(ROOT/'reference/extracted/A/program').read_bytes();assert hashlib.sha1(raw).hexdigest()==SHA
facts=json.loads((UP/'tools/facts/program.json').read_text());assert facts['binary']['sha1']==SHA
H=parse_hunk_file(raw).hunks;D=H[2].data;REL={o:g.target_hunk for g in H[2].reloc32 for o in g.offsets}
ROOTS={n:facts['labels']['LAB_00'+n][1] for n in ['D2','D3','D4','D6','D7','D8','D9','DA','DB','DC','DD','DE','DF','E0','E1','E3','E4','E5']}

def track(name):
 p=ROOTS[name];poses=[];layers=[];calls=[];repeat=1;jump=None
 for _ in range(1800):
  op,arg=D[p:p+2]
  if op<128:
   assert op in [0,4,8,12,16]
   layers.append(dict(slot=op//4,frame=arg,x=struct.unpack_from('>h',D,p+4)[0],y=struct.unpack_from('>b',D,p+2)[0],flags=D[p+3]));p+=6
  elif op==0x88:
   assert arg>0;repeat=arg;p+=2
  elif op==0x84:
   assert arg==0 and REL[p+2]==2;jump=struct.unpack_from('>I',D,p+2)[0];assert jump in ROOTS.values();p+=6
  elif op==0xb4:
   assert arg==0 and REL[p+2]==0;call=struct.unpack_from('>I',D,p+2)[0];assert call in [3780,3814];calls.append(call);p+=6
  elif op==255:
   assert arg in [0,255]
   for n in range(repeat):poses.append(dict(layers=layers,calls=calls if n==0 else []))
   p+=2;layers=[];calls=[];repeat=1
   if arg==255:return dict(poses=poses,next=jump,bytes=p-ROOTS[name])
  else:raise ValueError((name,p,op))
 raise ValueError('Unbounded opening path '+name)

class Job:
 def __init__(self,name,mirror=False):self.name=name;self.mirror=mirror;self.at=0;self.done=False
 def step(self,paths):
  path=paths[self.name]
  if self.at==len(path['poses']):
   if path['next'] is None:self.done=True;return None
   self.name=next(n for n,v in ROOTS.items() if v==path['next']);self.at=0;path=paths[self.name]
  pose=path['poses'][self.at];self.at+=1
  return dict(pose,mirror=self.mirror)

def main():
 assert subprocess.check_output(['git','-C',str(UP),'rev-parse','HEAD'],text=True).strip()=='f0d699a2b92d42d5380429ea9f2d94f7534324ef'
 OUT.mkdir(parents=True,exist_ok=True);WORK.mkdir(parents=True,exist_ok=True)
 sources={};recovered=ROOT/'game/assets/classic/recovered'
 def verify(name):
  folder=recovered/name;meta=json.loads((folder/'sidecar.json').read_text());s=hashlib.sha1((ROOT/'reference/extracted'/name).read_bytes()).hexdigest();assert s==meta['source_sha1'];sources[name]=s;return folder,meta
 def picture(name,tweak=False):
  folder,meta=verify('A/'+name);im=Image.open(folder/'image.png').copy();pal=meta['palette_rgb12'].copy()
  if tweak:pal[8:12]=[0x05d,0x028,0x016,0x003]
  return im,pal
 sprites=[]
 for name in ['au1.cel','li1.cel','ha1.cel','dw1.cel','da1.cel']:
  folder,meta=verify('A/'+name);sprites.append([Image.open(folder/f'frames/{n:03d}.png').copy() for n in range(meta['frame_count'])])
 folder,meta=verify('A/ov1.cel');overlays=[Image.open(folder/f'frames/{n:03d}.png').copy() for n in range(meta['frame_count'])]
 font,meta=verify('A/bold.f');glyph_frames=[Image.open(font/f'frames/{n:03d}.png').copy() for n in range(meta['frame_count'])]
 charmap=D[11744:11744+96];assert len(glyph_frames)==76
 paths={n:track(n) for n in ROOTS}
 flash_palettes={}
 for key,label in [('a','LAB_0042'),('b','LAB_0043')]:
  hn,at=facts['labels'][label];flash_palettes[key]=list(struct.unpack_from('>32H',H[hn].data,at));assert max(flash_palettes[key])<=0xfff
 masks={}
 def blit(dst,im,x,y,mirror=False):
  if mirror:im=ImageOps.mirror(im)
  key=(im.size,im.tobytes())
  if key not in masks:masks[key]=Image.frombytes('L',im.size,im.tobytes()).point(lambda v:255 if v else 0)
  dst.paste(im,(x,y),masks[key])
 def text(im,value,y):
  ims=[glyph_frames[charmap[ord(c)-32]] for c in value];x=(320-sum(i.width-2 for i in ims))//2
  for g in ims:blit(im,g,x,y);x+=g.width-2
 frames=[];keys={};runs=[];colours=[];sections=[];tick=0
 def emit(im,pal,ticks,scene,fade=False):
  nonlocal tick
  assert ticks>0 and im.size==(320,200)
  key=im.tobytes()
  if key not in keys:keys[key]=len(frames);frames.append(Image.frombytes('L',im.size,key).convert('RGB'))
  frame=keys[key]
  if runs and runs[-1]['frame']==frame and runs[-1]['scene']==scene:runs[-1]['ticks']+=ticks
  else:runs.append(dict(frame=frame,scene=scene,start=tick,ticks=ticks))
  for i in range(ticks):
   # Native fades, explicitly provisional until matched against original playback.
   strength=min(1,(i+1)/16,(ticks-i)/16) if fade else 1
   colours.extend(tuple(round(((c>>s)&15)*strength)*17 for s in (8,4,0)) for c in pal)
  tick+=ticks
 def compose(bg,poses,overlay=0):
  im=bg.copy()
  for pose in poses:
   for layer in pose['layers']:
    cel=sprites[layer['slot']][layer['frame']];x=120-layer['x']-cel.width if pose['mirror'] else 160+layer['x']
    blit(im,cel,x,100+layer['y'],pose['mirror'])
  if overlay:
   for n,x,y in [(0,0,56),(3,51,134)]+([] if overlay==2 else [(1,157,104),(2,297,82)]):blit(im,overlays[n],x,y)
  return im
 def section(scene):sections.append(dict(id=scene,start=tick))
 # Logo and six loader credit pages are deliberately paced instead of disk-bound.
 folder,meta=verify('A/mindscape');logo=Image.open(folder/'image.png');section('mindscape');emit(logo,meta['palette_rgb12'],100,'mindscape',True)
 sheet,moonpal=picture('bg1a.PIV')
 # These PIVs are tile sheets, not completed backgrounds. The retail960byte
 # map has48 rows of10 tiles, each32x25, spanning a320x1200 camera scene.
 stile=(ROOT/'reference/extracted/A/intro.stile').read_bytes();assert len(stile)==960
 sources['A/intro.stile']=hashlib.sha1(stile).hexdigest();codes=list(struct.unpack('>480H',stile));assert max(codes)<240
 sheets=[sheet,picture('bg1c.PIV')[0],picture('bg1b.PIV')[0]]
 panorama=Image.new('P',(320,1200));panorama.putpalette(sheet.getpalette())
 for index,code in enumerate(codes):
  bank,tile=divmod(code,80);x,y=(tile%10)*32,(tile//10)*25
  panorama.paste(sheets[bank].crop((x,y,x+32,y+25)),((index%10)*32,(index//10)*25))
 panorama.save(OUT/'panorama.png');moon=panorama.crop((0,0,320,200))
 moonpal[5]=0;moonpal[9:13]=[0xfed,0xdc9,0xb95,0x842]
 cards=[]
 for n in ['00FD','00FF','0102','0105','010A','0107']:
  h,p=facts['labels']['LAB_'+n];assert h==2;lines=[]
  for _ in range(4):
   assert REL[p]==2
   at,x,y,flags,p=struct.unpack_from('>IhhhI',D,p);assert flags==3 and x==0
   lines.append(dict(text=D[at:D.index(0,at)].decode(),y=y))
   if not p:break
  else:raise ValueError('Credit list cycle')
  im=moon.copy()
  for line in lines:text(im,line['text'],line['y'])
  scene='credit-'+n;section(scene);cards.append(dict(id=scene,start=tick,lines=lines));emit(im,moonpal,150,scene,True)
  if lines[0]['text']=='Design by':
   im=moon.copy();text(im,'Godot remake by',85);text(im,'Craig Chandler',105);section('credit-remake')
   cards.append(dict(id='credit-remake',start=tick,lines=[dict(text='Godot remake by',y=85),dict(text='Craig Chandler',y=105)]));emit(im,moonpal,200,'credit-remake',True)
 assert cards[-2]['lines'][0]['text']=='Design by' and cards[-1]['id']=='credit-remake'
 # Source05A5 is a creative camera scroll, not a disk wait. Preserve its
 # threshold/step curve over the actual stitched map, ending on the forest.
 section('moon-to-forest');progress=0;scroll=[];music_tick=None
 thresholds=[10,18,33,65,115,900,920,940,960,980,1200]
 steps=[1,2,3,4,5,6,5,4,3,2,1]
 wipepal=moonpal.copy();wipepal[9:13]=[0xa00,0x600,0x300,0xfc6]
 assert struct.unpack_from('>I',D,facts['labels']['LAB_00D0'][1])[0]==4
 while progress<1000:
  row=next(i for i,threshold in enumerate(thresholds) if threshold>=progress)
  step=steps[row];progress=min(1000,progress+step)
  if step==4 and music_tick is None:music_tick=tick
  scroll.append(dict(tick=tick,progress=progress,step=step))
  emit(panorama.crop((0,progress,320,progress+200)),wipepal,4,'moon-to-forest')
 assert music_tick is not None
 stage=panorama.crop((0,1000,320,1200))
 def series(bg,pal,script,count,passes,scene,overlay=0):
  jobs=[];section(scene)
  for _ in range(count):
   jobs.append(Job(script))
   for _ in range(passes):
    poses=[p for j in jobs if (p:=j.step(paths)) is not None];jobs=[j for j in jobs if not j.done]
    emit(compose(bg,poses,overlay),pal,12,scene)
 series(stage,wipepal,'D8',5,12,'001B-arrival')
 bg,pal=picture('bg2.PIV',True);series(bg,pal,'D7',5,8,'001C-procession',1)
 # Moon circle: persistent near/far jobs, then four alternating knight arrivals.
 bg,pal=picture('bg3.PIV',True);jobs=[Job(n,m) for m,names in [(False,['DC','DD','DA']),(True,['DC','DD','D9'])] for n in names]
 section('001A-circle')
 def step_scene(bg,pal,jobs,scene,speed,overlay=0):
  poses=[p for j in jobs if (p:=j.step(paths)) is not None]
  calls=[c for pose in poses for c in pose['calls']]
  if calls:
   assert len(calls)==1
   previous=Image.frombytes('P',(320,200),frames[runs[-1]['frame']].tobytes()[::3]);flash=flash_palettes['a' if calls[0]==3780 else 'b']
   if calls[0]==3780:emit(previous,flash,8,scene);wait=8
   else:
    wait=124
    for delay in [20,2,20,5,10,5]:emit(previous,pal,delay,scene);emit(previous,flash,2,scene)
    emit(previous,pal,50,scene)
  else:wait=0
  im=compose(bg,poses,overlay);emit(im,pal,max(1,speed-wait),scene)
  return any(j.done for j in jobs)
 for idx,n in enumerate(['DE','DE','E0','E0']):
  jobs.append(Job(n,idx%2==1))
  for _ in range(16):step_scene(bg,pal,jobs,'001A-circle',10)
 driver=Job('E3');jobs.append(driver)
 for _ in range(300):
  step_scene(bg,pal,jobs,'001A-circle',10)
  if driver.at==len(paths['E3']['poses']):break
 else:raise ValueError('No circle end')
 # Main story scenes use a single finite driver, with independent looping dress.
 for scene,name,bgname,speed,overlay,stage_names in [('002C-summoning','D2','bg4.PIV',10,0,[]),('002C-ritual','D4','bg5a.PIV',10,0,[]),('002D-transformation','D6','bg2a.PIV',10,2,[]),('002F-moon','E5','bg3.PIV',12,0,['DC','DD','DB','DF','E1']),('002E-vortex','D3','bg5a.PIV',10,0,[])]:
  # Source 002C second picture is bg5a; 002E uses the same loaded picture.
  bg,pal=picture(bgname,bgname!='bg4.PIV');section(scene)
  jobs=[Job(n,m) for m in [False,True] for n in stage_names]
  if scene=='002F-moon':jobs.append(Job('E4'))
  driver=Job(name);jobs.append(driver)
  for _ in range(500):
   step_scene(bg,pal,jobs,scene,speed,overlay)
   if driver.at==len(paths[name]['poses']):break
  else:raise ValueError('No scene end '+scene)
 # Brief original title/loading composition. Native load needs no fake disk wait.
 im=moon.copy();blit(im,glyph_frames[73],9,60);text(im,'created by',130);text(im,'Rob Anderson',150);section('title-handoff');emit(im,moonpal,100,'title-handoff',True)
 assert len(frames)<640 and tick<16000
 atlas=Image.new('RGB',(5120,200*((len(frames)+15)//16)))
 for n,im in enumerate(frames):atlas.paste(im,(n%16*320,n//16*200))
 atlas.save(OUT/'indices.png');palette=Image.new('RGB',(32,tick));palette.putdata(colours);palette.save(OUT/'palette.png')
 # Menu assets use the actual menu palette, separate from cinematic palettes.
 folder,meta=verify('B/ch.piv');menupal=meta['palette_rgb12'];bg=Image.open(folder/'image.png');bg.save(OUT/'menu.png')
 def rgba(im):
  im=im.copy();im.putpalette([((c>>s)&15)*17 for c in menupal for s in (8,4,0)]+[0]*720);im.info['transparency']=0;return im.convert('RGBA')
 rgba(glyph_frames[73]).save(OUT/'title.png')
 folder,meta=verify('B/sel.cel');rgba(Image.open(folder/'frames/000.png')).save(OUT/'arrow.png')
 glyphs={};fontatlas=Image.new('RGBA',(512,128));x=y=0
 for code in range(32,127):
  im=rgba(glyph_frames[charmap[code-32]])
  if x+im.width>512:x=0;y+=20
  assert y+im.height<=128
  fontatlas.alpha_composite(im,(x,y));glyphs[chr(code)]=[x,y,im.width,im.height];x+=im.width+1
 fontatlas.save(OUT/'font.png')
 # Reuse the offline-only decoder with a guarded input size/tag for music.cmp.
 music=ROOT/'reference/extracted/A/music.cmp';sources['A/music.cmp']=hashlib.sha1(music.read_bytes()).hexdigest()
 source=(ROOT/'tools/bake_ending_music.cpp').read_text().replace('packed.size()!=60994','packed.size()!='+str(music.stat().st_size))
 (WORK/'bake-opening.cpp').write_text(source);exe=WORK/'bake-opening'
 subprocess.run(['g++','-O2','-std=c++17','-I'+str(UP/'include'),str(WORK/'bake-opening.cpp'),*[str(UP/f'src/engine/{n}.cpp') for n in ['rnc','modplay','paula']],'-o',str(exe)],check=True)
 subprocess.run([str(exe),str(music),str(OUT/'music.wav'),str(tick-music_tick+50)],check=True)
 # Campaign/menu score: four resident-bank voices, looped at a repeated
 # musical control state. Exact analog mix and PCM seam still need listening.
 import import_audio as audio
 audio.g.origin.read_binary=lambda name:audio.m.BINARY;audio.sounds._cache.clear()
 blob,inst,waves=audio.g.build();(WORK/'synth_data.cpp').write_text(audio.g.render())
 memory=bytearray(0x90000);memory[0x1000:0x1000+len(waves)]=waves
 for address,name in [(0x10000,'B/kn.a'),(0x40000,'B/re.a')]:
  data=(ROOT/'reference/extracted'/name).read_bytes();sources[name]=hashlib.sha1(data).hexdigest();data=data[32:];memory[address:address+len(data)]=data
 assert all(set(audio.sounds.banks_of(n))<={'C9','wave'} for n in range(110,114))
 (WORK/'menu-samples.bin').write_bytes(memory);exe=WORK/'bake-menu'
 subprocess.run(['g++','-O2','-std=c++17','-I'+str(UP/'include'),str(ROOT/'tools/bake_menu_music.cpp'),str(UP/'src/engine/synth.cpp'),str(UP/'src/engine/paula.cpp'),str(WORK/'synth_data.cpp'),'-o',str(exe)],check=True)
 menu_audio=json.loads(subprocess.check_output([str(exe),str(WORK/'menu-samples.bin'),str(OUT/'menu_music.wav')],text=True))
 trace=dict(version=1,program_sha1=SHA,source_sha1=sources,background_map=dict(bytes=960,tiles=480,size=[320,1200],sheets=['bg1a.PIV','bg1c.PIV','bg1b.PIV'],scroll=scroll),menu_audio=menu_audio,roots=ROOTS,paths={n:dict(passes=len(p['poses']),next=p['next'],bytes=p['bytes']) for n,p in paths.items()},frames=len(frames),ticks=tick,music_tick=music_tick,runs=runs,sections=sections,credits=cards,adaptations=['Loader credit cards150ticks; remake card200ticks; logo/title100ticks. Native16tick fades. These are provisional presentation choices, not measured original loading waits.','Original480tile camera scene reconstructed; source05A5 step curve scrolls0..1000 at4ticks/pass. Historical disk-loading waits omitted.','Source scene order and finite poses/holds preserved. Native composite restoration/job scheduling and palette flashes require running-original comparison.','Blue knight cinematic palette, original bitmap lettering. No original runtime code shipped.'])
 (ROOT/'docs/intro-menu-paths.json').write_text(json.dumps(trace,indent=2)+'\n')
 ext='[ext_resource type="Script" path="res://scripts/content/intro_art.gd" id="script"]\n'
 for key,file,typ in [('atlas','indices.png','Texture2D'),('palette','palette.png','Texture2D'),('music','music.wav','AudioStream'),('menu_music','menu_music.wav','AudioStream'),('background','menu.png','Texture2D'),('title','title.png','Texture2D'),('arrow','arrow.png','Texture2D'),('font_atlas','font.png','Texture2D')]:ext+=f'[ext_resource type="{typ}" path="res://assets/classic/intro_menu/{file}" id="{key}"]\n'
 textres='[gd_resource type="Resource" load_steps=10 format=3]\n'+ext+'[resource]\nscript = ExtResource("script")\n'
 for key in ['atlas','palette','music','menu_music','background','title','arrow','font_atlas']:textres+=key+' = ExtResource("'+key+'")\n'
 for key,val in [('menu_loop_begin',menu_audio['loop_begin']),('menu_loop_end',menu_audio['loop_end']),('columns',16),('music_tick',music_tick),('total_ticks',tick),('frames',len(frames)),('runs',runs),('sections',sections),('credits',cards),('glyphs',glyphs)]:textres+=key+' = '+gd(val)+'\n'
 (OUT/'art.tres').write_text(textres)
 print('Opening:',len(frames),'native pictures,',tick,'ticks,',len(cards),'credit cards, menu/font/music')
if __name__=='__main__':main()
