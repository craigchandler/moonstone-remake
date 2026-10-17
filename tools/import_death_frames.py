#!/usr/bin/env python3
"""Resolve finite retail death paths offline into native artwork and rule clocks.

This is a bounded asset conversion, never a game-time bytecode interpreter.
Owner-dead branches, demo branches, frame-list changes and final list repetitions
are explicit inputs. Motion and non-audio callbacks remain native mechanics.
"""
import copy,json,struct
import import_creature_pack as m
import import_finishes as f

KNIGHT=['B/KN1.ob','B/KN2.ob','B/KN3.ob','B/KN4.ob','C/KN5.ob']
RELOC={p:g.target_hunk for g in m.HUNKS[4].reloc32 for p in g.offsets}
IDLE={4196,7646,10358,11334,14984,20062,23148,24610,25722}

def resolve(root,profile,dead=True,clean=False,frame_set=2):
    if root not in m.REFS:raise ValueError(('Unreferenced retail root',root))
    poses=[];events=[];trace=[];notes=[];layers=[];hold=1;mirror=False
    p=root;loop=None;deferred=None;death_mark=None
    families=profile['families'];original=profile['source_families']
    def target(pos):
        if RELOC.get(pos)!=4:raise ValueError(('Unverified retail transfer',p,pos))
        return struct.unpack_from('>I',m.DATA,pos)[0]
    for _ in range(15000):
        if p in IDLE and p!=root:break
        op,arg=m.DATA[p:p+2];trace.append(p)
        if op<128:
            if op not in (0,4,8,12,16):raise ValueError(('Invalid layer',p,op))
            family=(KNIGHT if frame_set==1 else original)[op//4]
            if family is None:raise ValueError(('Unloaded family',root,p))
            if family not in families:families.append(family)
            if not(clean and m.DATA[p+3]&128):
                layers.append(dict(slot=families.index(family),frame=arg,x=struct.unpack_from('>h',m.DATA,p+4)[0],y=struct.unpack_from('>b',m.DATA,p+2)[0]-52,flags=m.DATA[p+3]))
            p+=6;continue
        if op not in m.SIZES:raise ValueError(('Unhandled retail control',root,p,hex(op)))
        if op==0xb4 and dead:
            p=target(p+2);hold=1;loop=None;continue
        elif op==0x98 and clean:
            p=target(p+2);continue
        elif op==0x84:
            dest=target(p+2)
            if arg==3:p=dest;continue
            deferred=dest
        elif op==0xc0:
            if arg not in (1,2):raise ValueError(('Unknown frameset',p,arg))
            frame_set=arg
        elif op==0x80:mirror=not mirror if arg==255 else arg==3
        elif op==0x88:
            hold=max(1,arg)
            # A static final background-corpse wait is represented by persistent
            # native remains. No visible cel is removed by this substitution.
            if p==6012:hold=1
        elif op==0x94:loop=(len(poses),len(events),max(1,arg))
        elif op in (0xa4,0xb0):
            event=dict(pose=len(poses),source=p,context='knight' if frame_set==1 else profile['context'])
            if op==0xa4:event['options']=[[arg]]
            else:
                event['routine']=[RELOC.get(p+2),struct.unpack_from('>I',m.DATA,p+2)[0]]
                if event['routine']==[0,896] and death_mark is None:death_mark=sum(x['hold'] for x in poses)*6
            events.append(event)
        elif op in (0xb8,0xac):
            notes.append(dict(source=p,control=hex(op),bytes=m.DATA[p:p+6].hex()))
            if op==0xb8:raise ValueError(('Independent visible job requires explicit native ownership',root,p))
        elif op in (0xc4,0xc8,0x90):raise ValueError(('Conditional path needs explicit decision',root,p))
        elif op==0xbc:break
        elif op==0xff:
            if layers:poses.append(dict(layers=layers,hold=hold,mirror=mirror))
            layers=[];hold=1
            if deferred is not None:p=deferred;deferred=None;continue
            if arg in (254,255) and loop:
                first,evfirst,count=loop;segment=copy.deepcopy(poses[first:]);cues=copy.deepcopy(events[evfirst:]);width=len(segment)
                for n in range(1,count):
                    poses.extend(copy.deepcopy(segment))
                    events.extend(dict(e,pose=e['pose']+n*width) for e in cues)
                notes.append(dict(source=p,repeat=count,poses=width,terminator=arg));loop=None
            if arg==255:break
        elif op in (0xfd,0xfe):break
        elif op not in (0x8c,0xa0,0xa8,0xcc,0xd0,0xb4,0x98):raise ValueError(('Unknown path control',root,p))
        p+=m.SIZES[op]
    else:raise ValueError(('Unbounded path',root))
    if not poses:raise ValueError(('No visible path',root))
    for event in events:event['pose']=min(event['pose'],len(poses)-1)
    return poses,events,dict(root=root,dead=dead,poses=len(poses),ticks=sum(x['hold'] for x in poses)*6,death_mark=death_mark,
        controls=[p for p in trace if m.DATA[p]>=128],notes=notes,
        cells=[[dict(family=families[l['slot']],frame=l['frame']) for l in pose['layers']] for pose in poses])

def configurations():
    profiles={};specs={}
    def add(kind,families,scene,region,clips,context=None,dead=True):
        profiles[kind]=dict(families=list(families),source_families=list(families),scene=scene,region=region,context=context or kind.removeprefix('death_'),clips={},attacks=[],pose_overrides={},cue_overrides={},frame_paths_version=2)
        specs[kind]=(clips,dead)
    add('death_trogg_spear',['B/TROGGSpear1.CEL','B/TROGGSpear2.CEL'],0x20,0,{'defeat':9054,'defeat_split':9200,'defeat_guts':9320})
    add('death_trogg_axe',['B/TROGGAxe1.CEL','B/TROGGAxe2.CEL'],0x20,0,{'defeat':8146,'defeat_split':8284,'defeat_guts':8400})
    add('death_trogg_hammer',m.PROFILES['trogg_hammer']['families'],0x18,12,{'defeat':11834,'defeat_a':11834,'defeat_b':11980,'defeat_guts':12098})
    # Death uses Balok3 in slot1, unlike its ordinary attack frame table.
    add('death_balok',f.profiles['balok_finishes']['families'],0x30,12,{'defeat':20484})
    m.SCENES[0x40]=[0x55a,0x347,0x123,0x001,0xf00,0x800,0xc00]
    add('death_giant_troll',['B/TROLL1.CEL','B/TROLL2.CEL'],0x40,12,{'defeat':25038})
    profiles['death_giant_troll']['palette_mode']='troll'
    add('death_ratman',m.PROFILES['ratman']['families'],0x24,4,{'defeat':16384,'defeat_swing':16988,'defeat_heavy':16184,'defeat_counter':16184,'defeat_air':17072})
    for kind,root in [('mudman',24454),('dragon',18968),('guardian',27684)]:
        p=m.PROFILES[kind];add('death_'+kind,p['families'],p['scene'],p['region'],{'defeat':root})
    add('death_knight',KNIGHT,0,0,{'defeat':5788,'defeat_b':5644,'defeat_gory':6040,'hop':6578,'flung':6920},context='knight')
    add('death_rat_victim',m.PROFILES['ratman']['families'],0x24,4,{'strike':15998,'bite':16128},context='ratman')
    # Full composites: no source frame-list repeats may be silently capped at8.
    for kind,names in [('spear_finishes',['impale']),('balok_finishes',['lift','shake','eat_a','eat_b']),('mud_finishes',['swallow','quick_drag']),('guardian_finishes',['grab_close','grab_far','release_close','release_far'])]:
        p=f.profiles[kind];ctx={'spear_finishes':'trogg_spear','mud_finishes':'mudman','balok_finishes':'balok','guardian_finishes':'guardian'}[kind]
        add('complete_'+kind,p['families'],p['scene'],p['region'],{n:p['clips'][n][0] for n in names},context=ctx)
    add('complete_dragon',m.PROFILES['dragon']['families'],0x14,12,{'execution_bite':19412},context='dragon')
    add('complete_burn',KNIGHT,0x14,12,{'burn':7580},context='dragon')
    add('complete_ratman',m.PROFILES['ratman']['families'],0x24,4,{'rat_throw_finish':15556,'rat_squeeze_finish':16956},context='ratman')
    report={}
    for kind,profile in profiles.items():
        report[kind]={};clips,dead=specs[kind]
        for name,root in clips.items():
            poses,events,path=resolve(root,profile,dead=dead,frame_set=1 if kind=='death_knight' or kind=='complete_burn' else 2)
            profile['clips'][name]=[root];profile['pose_overrides'][name]=poses;profile['cue_overrides'][name]=events;report[kind][name]=path
            if kind in ['death_trogg_spear','death_trogg_axe','death_trogg_hammer','death_knight']:
                clean_poses,_,_=resolve(root,profile,dead=dead,clean=True,frame_set=1 if kind=='death_knight' else 2)
                profile.setdefault('pose_overrides_clean',{})[name]=clean_poses
        first=next(iter(profile['clips']))
        for alias in ['idle','walk','hurt_a']:
            if alias not in profile['clips']:
                profile['clips'][alias]=profile['clips'][first];profile['pose_overrides'][alias]=profile['pose_overrides'][first];profile['cue_overrides'][alias]=[]
    # Independent native remains retain the actual final victim layers rather
    # than substituting an unrelated knight fragmentation animation.
    for family,source,name,cells in [
        ('complete_spear_finishes','impale','remains',[(0,19),(0,33)]),
        ('complete_balok_finishes','eat_a','remains_a',[(1,19),(1,17)]),
        ('complete_balok_finishes','eat_b','remains_b',[(1,59),(1,44),(1,45),(1,17)]),
        ('complete_ratman','rat_throw_finish','remains_throw',[(1,43),(1,42),(0,27),(1,45)]),
        ('complete_ratman','rat_squeeze_finish','remains_squeeze',[(1,62)]),
        ('complete_ratman','rat_squeeze_finish','rat_squeeze_after',[(0,55),(0,63),(0,54)])]:
        profile=profiles[family];pose=copy.deepcopy(profile['pose_overrides'][source][-1]);pose['hold']=1
        pose['layers']=[l for l in pose['layers'] if (l['slot'],l['frame']) in cells]
        if len(pose['layers'])!=len(cells):raise ValueError(('Unverified remains',family,source))
        profile['clips'][name]=profile['clips'][source];profile['pose_overrides'][name]=[pose];profile['cue_overrides'][name]=[]
        report[family][name]=dict(root=profile['clips'][source][0],poses=1,ticks=6,death_mark=None,derivation='Final victim layers only; native independent remains',cells=[cells],notes=[])
    return profiles,report

def merged_profile(complete,base,profiles,report):
    """Only explicit audited clips may replace a gameplay clip, never aliases."""
    profile=copy.deepcopy(f.profiles.get(base,m.PROFILES.get(base)))
    resolved=profiles[complete];actual=set(report[complete])
    profile['clips'].update({n:v for n,v in resolved['clips'].items() if n.startswith('remains') or n=='rat_squeeze_after'})
    profile.update(families=resolved['families'],frame_paths_version=3,
        pose_overrides={n:v for n,v in resolved['pose_overrides'].items() if n in actual},
        cue_overrides={n:v for n,v in resolved['cue_overrides'].items() if n in actual})
    if base=='dragon_victim':
        profile['pose_overrides']['defeat']=profile['pose_overrides']['burn'];profile['cue_overrides']['defeat']=profile['cue_overrides']['burn']
    return profile

def main():
    profiles,report=configurations()
    for kind,profile in profiles.items():m.bake(kind,profile)
    # Ordinary attack/contact data stays with the original profile.
    for complete,base in [('complete_spear_finishes','spear_finishes'),('complete_balok_finishes','balok_finishes'),('complete_mud_finishes','mud_finishes'),('complete_guardian_finishes','guardian_finishes'),('complete_dragon','dragon'),('complete_burn','dragon_victim'),('complete_ratman','ratman')]:
        profile=merged_profile(complete,base,profiles,report)
        m.bake(base,profile)
    doc=dict(mog_sha1=m.MOG_SHA1,paths=report,limits='Draw paths verified against retail bytes. Six-tick clock mapping, motion blocks, clean substitutions, collision and simultaneous/co-op scheduling still require running-original comparison. Static terminal waits replaced by persistent native remains. War beast paths are separately verified by import_beast_frames.py.')
    (m.ROOT/'docs/death-frame-audit.json').write_text(json.dumps(doc,indent=2)+'\n')
    clocks={kind:{name:{k:p[k] for k in ['poses','ticks','death_mark']} for name,p in clips.items()} for kind,clips in report.items()}
    import import_beast_frames as beast
    _,beast_paths=beast.configuration()
    clocks['war_beast']={n:dict(ticks=beast_paths[n]['native_ticks'],poses=beast_paths[n]['poses'],death_mark=None) for n in ['ejected','fallen_front']}
    (m.ROOT/'game/content/generated/death-clocks.json').write_text(json.dumps(clocks,indent=2)+'\n')
    resource='[gd_resource type="Resource" load_steps=2 format=3]\n[ext_resource type="Script" path="res://scripts/content/death_frames.gd" id="1"]\n[resource]\nscript = ExtResource("1")\nclocks = '+m.gd(clocks).replace(': None',': null')+'\n'
    (m.ROOT/'game/content/generated/death_frames.tres').write_text(resource)
    print(json.dumps(clocks,indent=2))

if __name__=='__main__':main()
