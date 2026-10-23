#!/usr/bin/env python3
"""Offline retail wizard/dice drawing tracks, town text and PCM. No runtime VM."""
from pathlib import Path
import json,struct,copy,hashlib,sys,subprocess,wave
from PIL import Image
from import_support import audio_helper
import import_creature_pack as m
r=m.ROOT;out=r/'game/assets/classic/town_locations';out.mkdir(exist_ok=True);w=r/'work/town-locations';w.mkdir(exist_ok=True)
sources={};frames={};pictures={};data={}
def verify(name):
 f=r/'game/assets/classic/recovered'/name;meta=json.loads((f/'sidecar.json').read_text());sha=hashlib.sha1((r/'reference/extracted'/name).read_bytes()).hexdigest();assert sha==meta['source_sha1'];sources[name]=sha;return f,meta
def palette(colors):return [((c>>s)&15)*17 for c in colors for s in [8,4,0]]+[0]*672
def picture(key,name,ramp=False):
 f,meta=verify(name);c=meta['palette_rgb12'].copy()
 if ramp:c[6:11]=[0x5d,0x3b,0x28,0x16,3]
 im=Image.open(f/'image.png');im.putpalette(palette(c));im.convert('RGB').save(out/(key+'.png'));pictures[key]=key+'.png';return c
c_tower=picture('tower','C/WI2.P',True);c_gift=picture('gift','C/WI1.P');c_dice=picture('tavern','C/tav.piv',True)
def track(h,root,passes,loop=False):
 d=m.HUNKS[h].data;poses=[];layers=[];p=root;hold=1;repeat=None;cues=[]
 for _ in range(200):
  op,arg=d[p:p+2]
  if op==0:layers.append({'frame':arg,'x':160+struct.unpack_from('>h',d,p+4)[0],'y':100+struct.unpack_from('>b',d,p+2)[0]});p+=6;continue
  if op==0x88:hold=arg;p+=2;continue
  if op==0x94:repeat=(len(poses),arg);p+=2;continue
  if op==0x84:
   assert arg==0 and struct.unpack_from('>I',d,p+2)[0]==root;p+=6;continue
  if op==0xb0:
   assert h==42 and struct.unpack_from('>I',d,p+2)[0]==42906
   cues.append({'tick':sum(x['ticks'] for x in poses),'sequence':153,'optional':True});p+=6;continue
  assert op==255 and layers,(h,p,hex(op))
  poses.append({'ticks':passes*hold,'layers':layers});hold=1;layers=[]
  if arg==254:
   first,count=repeat;poses+=copy.deepcopy(poses[first:])*(count-1);repeat=None
  if arg==255:break
  assert arg in [0,254];p+=2
 else:raise ValueError('Unbounded retail track')
 return poses,cues
for key,h,root,passes in [('tower',4,36842,5),('gift_a',4,36664,6),('gift_b',4,36812,6),('dice_idle',42,278,6),('dice_roll',42,294,3)]:
 poses,cues=track(h,root,passes);data[key]=poses;data[key+'_cues']=cues
 family='wizard' if h==4 else 'dice'
 f,meta=verify('C/Wi1.C' if h==4 else 'C/dice.cel')
 for frame in {l['frame'] for p in poses for l in p['layers']}:
  key2=family+'_'+str(frame)
  if key2 in frames:continue
  im=Image.open(f/'frames'/f'{frame:03d}.png');im.putpalette(palette(c_gift if family=='wizard' and frame<15 else c_tower if family=='wizard' else c_dice));im.info['transparency']=0;im.convert('RGBA').save(out/(key2+'.png'));frames[key2]=key2+'.png'
# A cursed human is skipped as a current knight; the original other-token
# drawing uses kind0+43, with no invented active-toad cel.
f,meta=verify('B/mi.c');map_meta=json.loads((r/'game/assets/classic/recovered/B/test/sidecar.json').read_text())
im=Image.open(f/'frames/043.png');im.putpalette(palette(map_meta['records'][8]['palette_rgb12']));im.info['transparency']=0;im.convert('RGBA').save(out/'frog.png');pictures['frog']='frog.png'
# Retail text pointers differ from published source version. Derive strings from
# relocated references; every root and bounded list is checked against retail SHA.
d=m.DATA
refs=sorted({struct.unpack_from('>I',h.data,o)[0] for h in m.HUNKS if h.data for g in h.reloc32 if g.target_hunk==4 for o in g.offsets})
def lines(root):
 n=d[root];assert 1<=n<=12;rows=[];p=root+1
 for _ in range(n):
  end=d.index(0,p);assert end-p<90;rows.append(d[p:end].decode('ascii'));p=end+1
 return rows
facts=json.loads((r/'work/upstream/moonstone-ace/tools/facts/mog.json').read_text())['labels']
# All text roots in this block moved exactly twelve bytes in this retail build.
for name,label in [('intro','091E'),('item_speech','092E'),('gold_speech','0930'),('stat_speech','0932'),('omen_speech','0933'),('toad_speech','0934'),('curse','092D')]:
 root=facts['LAB_'+label][1]+12;assert root in refs;data[name]=lines(root)
for key,label,count,step,extra in [('gold_replies','0905',3,4,0),('item_replies','0907',4,4,0),('stat_replies','090A',9,8,4)]:
 data[key]=[lines(struct.unpack_from('>I',d,facts['LAB_'+label][1]+12+step*i+extra)[0]) for i in range(count)]
# Original text-record chains for the donation/result screens.
from import_stonehenge import text_list
for name,label in [('none','094D'),('refused','094E')]:
 try:data[name]=text_list(4,facts['LAB_'+label][1]+12)
 except (AssertionError,KeyError):pass
rows=[]
for i in range(11):
 a,b,c,z,mult,one=struct.unpack_from('>6B',m.HUNKS[42].data,1028+6*i);assert z==0 and one==1 and 0<=a<=b<=c<=5;rows.append([a,b,c,mult])
data['dice_rows']=rows;data['prices']=[20,32,52,40,52,36,52,52,40,24,12,20]
data['wizard_roots']={'tower':36842,'gift_a':36664,'gift_b':36812};data['dice_roll_ticks']=sum(p['ticks'] for p in data['dice_roll'])
# Bake only new native streams, preserving the previous138 audio resources.
import import_audio as a
a.g.origin.read_binary=lambda name:m.BINARY;a.sounds._cache.clear();_,inst,waves=a.g.build()
exe=audio_helper(r,a.UP,w,'bake-audio',[r/'tools/bake_audio.cpp',a.UP/'src/engine/synth.cpp',a.UP/'src/engine/paula.cpp'],a.g)
memory=bytearray(0x90000)
for addr,name in [(0x10000,'B/kn.a'),(0x20000,'C/wz.a'),(0x40000,'B/re.a'),(0x60000,'C/wz.a'),(0x80000,'B/Ra.a')]:
 b=(r/'reference/extracted'/name).read_bytes();sources[name]=hashlib.sha1(b).hexdigest();memory[addr:addr+len(b)-32]=b[32:]
memory[0x1000:0x1000+len(waves)]=waves;mem=w/'town_samples.bin';mem.write_bytes(memory);streams={};audio=[]
for seq in [*range(116,120),*range(121,132),153,156]:
 key='town_%03d'%seq;wav=out/(key+'.wav');subprocess.run([str(exe),str(mem),str(wav),'20','1',str(seq)],check=True,stdout=subprocess.DEVNULL)
 with wave.open(str(wav)) as f:seconds=f.getnframes()/f.getframerate()
 streams[key]=key+'.wav';audio.append({'key':key,'sequence':seq,'seconds':seconds,'sha256':hashlib.sha256(wav.read_bytes()).hexdigest()})
ext='[ext_resource type="Script" path="res://scripts/content/town_art.gd" id="script"]\n'
for group,values,typ in [('p',pictures,'Texture2D'),('f',frames,'Texture2D'),('s',streams,'AudioStream')]:
 for k,v in values.items():ext+=f'[ext_resource type="{typ}" path="res://assets/classic/town_locations/{v}" id="{group}_{k}"]\n'
s=f'[gd_resource type="Resource" load_steps={2+len(pictures)+len(frames)+len(streams)} format=3]\n'+ext+'[resource]\nscript = ExtResource("script")\n'
for field,values,prefix in [('pictures',pictures,'p'),('frames',frames,'f'),('streams',streams,'s')]:s+=field+' = {'+', '.join(m.gd(k)+f': ExtResource("{prefix}_{k}")' for k in values)+'}\n'
s+='data = '+m.gd(data).replace('True','true').replace('False','false')+'\nsustained = Array[String]('+m.gd([x['key'] for x in audio if x['seconds']>=19.99])+')\n';(out/'art.tres').write_text(s)
(out/'provenance.json').write_text(json.dumps({'mog_sha1':m.MOG_SHA1,'sources':sources,'frog_map_cel':43,'data':data,'audio':audio,'limits':'Offline bounded original draws and native PCM only. Draw pass cadence, fades and mix remain provisional until original playback comparison.'},indent=2)+'\n')
print('Imported wizard/dice original tracks, texts,11payout rows and',len(audio),'new PCM streams')
