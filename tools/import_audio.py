#!/usr/bin/env python3
"""One-time original audio -> native PCM and pose-linked sound cues.

Only this offline tool uses the pinned reference synth/Paula model. Godot ships
WAVs and declarative cues, without the model, executables, disks or sound banks.
All data and timings retain provenance; listening parity remains a separate task.
"""
import hashlib
import json
import struct
import subprocess
import wave
from pathlib import Path
import import_creature_pack as m
from import_knight_animations import gd
import gen_synth_tables as g
import sys
sys.path.insert(0,str(m.ROOT/"work/upstream/moonstone-ace/tools/monsterkit"))
import sounds

ROOT=m.ROOT
UP=ROOT/'work/upstream/moonstone-ace'
OUT=ROOT/'game/assets/classic/audio'
WORK=ROOT/'work/audio'
PIN='f0d699a2b92d42d5380429ea9f2d94f7534324ef'
BANKS={'knight':'B/kn.a','black_knight':'B/kn.a','trogg_spear':'B/tr.a',
       'trogg_axe':'B/tr.a','trogg_hammer':'B/tr.a','giant_troll':'B/to.a',
       'balok':'C/ba.a','war_beast':'C/be.a','ratman':'B/Ra.a',
       'mudman':'C/mu.a','dragon':'C/dr.a','guardian':'C/Gu.a','ritual':'B/he.a'}
# Retail hunk+offset operands, guarded by the whole original MOG hash above.
# Each outer list is an alternative; each inner list plays together. Repeated
# alternatives preserve the original picker weights. Native presentation cycles
# alternatives without consuming authoritative game randomness.
CALLS={(0,29232):[[30],[30],[31],[32]],
 (0,29258):[[a,b] for a in [24,24,25,26] for b in range(20,24)],
 (0,29306):[[91],[92]],(0,29330):[[106],[107]],
 (0,29378):[[101],[102]],(0,29402):[[103],[103],[104],[105]],
 (0,29428):[[i] for i in range(4,9)],
 (0,29470):[[i] for i in range(35,43)],
 (0,29478):[[i] for i in range(56,62)],
 (0,28058):[[48,18]],(0,28038):[[29]],(0,28048):[[27]],
 (40,1052):[[80]],(40,1064):[[87,148],[88,149],[89,150],[151,152]],
 (40,1182):[[83],[84],[85],[85]],(40,1212):[[90]],
 (40,1666):[[a,b] for a in [136,137,138,139,140,141,142,137]
                    for b in [136,137,138,139,140,141,142,137]],
 (40,2698):[['guardian_death']],
 (40,2740):[[64,65],[66,67],[68,69],[68,69]]}

def timelines():
    result={}; unresolved=[]
    reloc={o:r.target_hunk for r in m.HUNKS[4].reloc32 for o in r.offsets}
    for prov in sorted((ROOT/'game/assets/classic').glob('*/provenance.json')):
        data=json.loads(prov.read_text());family=prov.parent.name
        if not data.get('roots'):continue
        result[family]={}
        for clip,roots in data['roots'].items():
            if clip in data.get('cue_overrides',{}):
                entries=[]
                for raw in data['cue_overrides'][clip]:
                    entry=dict(raw)
                    if 'routine' in entry:
                        options=CALLS.get(tuple(entry.pop('routine')))
                        if options is None:
                            unresolved.append(dict(family=family,clip=clip,offset=entry['source'],reason='Non-audio routine in resolved pose path'))
                            continue
                        entry['options']=options
                    entries.append(entry)
                if entries:result[family][clip]=entries
                continue
            pose=0;entries=[]
            for start in roots if isinstance(roots,list) else [roots]:
                if not isinstance(start,int):continue
                p=start;visited=set();loop_at=None;loop_count=0
                while p not in visited and p<start+4096:
                    visited.add(p);op,arg=m.DATA[p:p+2]
                    if op<128:p+=6;continue
                    if op not in m.SIZES:raise ValueError((family,clip,p,hex(op)))
                    options=None
                    if op==0xa4:options=[[arg]]
                    elif op==0xb0:
                        call=(reloc.get(p+2),struct.unpack_from('>I',m.DATA,p+2)[0])
                        options=CALLS.get(call)
                        if options is None:unresolved.append(dict(family=family,clip=clip,offset=p,call=call))
                    if options:entries.append(dict(pose=pose,options=options,source=p))
                    if op==0x94:loop_at=(pose,len(entries));loop_count=min(8,max(1,arg))
                    if op==0xff:
                        pose+=1
                        if (arg==0xfe or (arg==0xff and start==14090)) and loop_count and loop_at:
                            first,n=loop_at;count=pose-first
                            repeated=entries[n:]
                            for cycle in range(1,loop_count):
                                entries.extend(dict(e,pose=e['pose']+count*cycle) for e in repeated)
                            pose+=count*(loop_count-1);loop_count=0
                        if arg==255:break
                    if op in (0xfd,0xfe) or op==0x84:break
                    p+=m.SIZES[op]
                # Last callbacks occasionally follow the final draw. Bind them
                # to the last visible pose, never spill into the next script.
            for e in entries:e['pose']=min(e['pose'],max(0,pose-1))
            if entries:result[family][clip]=entries
    return result,unresolved

def main():
    if subprocess.check_output(['git','rev-parse','HEAD'],cwd=UP,text=True).strip()!=PIN:
        raise ValueError('Audio import requires the reviewed pinned reference helper')
    OUT.mkdir(parents=True,exist_ok=True);WORK.mkdir(parents=True,exist_ok=True)
    g.origin.read_binary=lambda name:m.BINARY
    sounds._cache.clear()
    blob,inst,waves=g.build()
    tables=WORK/'synth_data.cpp';tables.write_text(g.render())
    exe=WORK/'bake-audio'
    subprocess.run(['c++','-std=c++17','-O2','-I'+str(UP/'include'),str(ROOT/'tools/bake_audio.cpp'),
                    str(UP/'src/engine/synth.cpp'),str(UP/'src/engine/paula.cpp'),str(tables),'-o',str(exe)],check=True)
    timeline,unresolved=timelines();streams={};provenance=[]
    sources={}
    def load(name):
        data=(ROOT/'reference/extracted'/name).read_bytes()
        sources[name]=hashlib.sha256(data).hexdigest()
        return data[32:]
    common={0x1000:waves,0x10000:load('B/kn.a'),0x40000:load('B/re.a'),
            0x60000:load('C/wz.a'),0x80000:load('B/Ra.a')}
    def render(key,seqs,kind):
        if key in streams:return key
        memory=bytearray(0x90000)
        banks=dict(common);banks[0x20000]=load(BANKS[kind])
        for address,data in banks.items():memory[address:address+len(data)]=data
        for seq in seqs:
            for i in sounds.instruments_of(seq):
                loop,lo,words,bank,offset,pitch=inst[i]
                base=[0x1000,0x10000,0x20000,0x40000,0x60000,0x80000][bank]
                if offset+words*2>len(banks[base]):raise ValueError(('Sample exceeds verified bank',kind,seq,i))
        mem=WORK/'samples.bin';mem.write_bytes(memory)
        wav=OUT/(key+'.wav')
        subprocess.run([str(exe),str(mem),str(wav),'20',str(2 if len(seqs)>1 else 1),*map(str,seqs)],check=True)
        with wave.open(str(wav)) as f:
            seconds=f.getnframes()/f.getframerate();channels=f.getnchannels()
        streams[key]=str(wav.relative_to(ROOT/'game'))
        provenance.append(dict(key=key,sequences=seqs,context=kind,seconds=seconds,channels=channels,
                               sha256=hashlib.sha256(wav.read_bytes()).hexdigest()))
        return key
    def native(seq,kind):
        if seq=='guardian_death':return render('guardian_death',[74,75,76,77],'guardian')
        banks=sounds.banks_of(seq)
        context=kind if 'C8' in banks else 'common'
        return render(f'{context}_{seq:03d}',[seq],kind)
    for family,clips in timeline.items():
        kind={'spear_finishes':'trogg_spear','hammer_finishes':'trogg_hammer','mud_finishes':'mudman',
              'balok_finishes':'balok','knight_finishes':'knight','guardian_finishes':'guardian',
              'dragon_victim':'dragon'}.get(family,family)
        for entries in clips.values():
            for entry in entries:
                entry['options']=[[native(s,entry.get('context',kind)) for s in option] for option in entry['options']]
    # Original loot click; protected ring and stat-upgrade sounds are tracked
    # separately until their exact transaction callback is implemented.
    cues={'loot_click':[native(156,'ritual')], 'parry':[native(17,'knight')],
          'ritual_open':[native(s,'ritual') for s in [158,159,160]],
          'ritual_chant':[native(157,'ritual')]}
    text='[gd_resource type="Resource" load_steps=%d format=3]\n'% (len(streams)+2)
    text+='[ext_resource type="Script" path="res://scripts/content/sound_pack.gd" id="1"]\n'
    for i,(key,path) in enumerate(streams.items(),2):
        text+=f'[ext_resource type="AudioStream" path="res://{path}" id="{i}"]\n'
    text+='[resource]\nscript = ExtResource("1")\npack_id = "classic.audio.v1"\nstreams = {'
    text+=', '.join(gd(key)+f': ExtResource("{i}")' for i,key in enumerate(streams,2))+'}\n'
    text+='timelines = '+gd(timeline)+'\ncues = '+gd(cues)+'\n'
    text+='sustained = Array[String]('+gd([a['key'] for a in provenance if a['seconds']>=19.99])+')\n'
    (OUT/'sounds.tres').write_text(text)
    report=dict(mog_sha1=m.MOG_SHA1,reference_pin=PIN,rate=48000,tick_rate=50,lowpass='off',
                model='Offline reference synth + Paula; no model shipped',sources=sources,
                sounds=provenance,timelines=timeline,unresolved_calls=unresolved,
                limits=['Source-placed pose cues; native phase clocks remain provisional.',
                        'Picker alternatives cycle locally; no authoritative RNG consumed.',
                        'No original four-channel SFX stealing or analog-filter claim.',
                        'Sustained/ambient tails are capped at 20s and stopped on owner animation changes; exact ambience restoration remains pending.',
                        'Non-sound callbacks retained in unresolved list for audit, not executed.'])
    (OUT/'provenance.json').write_text(json.dumps(report,indent=2)+'\n')
    print('Baked',len(streams),'native audio files;',sum(len(c) for c in timeline.values()),'animation timelines')

if __name__=='__main__':main()
