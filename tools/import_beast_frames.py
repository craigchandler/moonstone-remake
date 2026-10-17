#!/usr/bin/env python3
"""Bake the finite retail beast hit/death and knight landing paths.

Offline only: verified branches/frame-set switches become ordinary atlas poses.
No original instructions, executable or interpreter are shipped in the game.
Motion-block trajectories remain native; this audit does not claim VM timing parity.
"""
import copy,json,struct
import import_creature_pack as m

ALLOWED_BRANCHES={13008:13076,13454:13518,13518:13076,6566:5920}
ALLOWED_JUMPS={14000:14056,14076:6546,6572:4196}
RELOC={p:g.target_hunk for g in m.HUNKS[4].reloc32 for p in g.offsets}

def path(start, dead, stop=None):
    p=start;poses=[];layers=[];hold=1;mirror=False;frame_set=2
    events=[];trace=[];seen=set()
    for _ in range(600):
        if p==stop or p==4196:break
        if p in seen:raise ValueError(('Unbounded path',start,p))
        seen.add(p);op,arg=m.DATA[p:p+2];trace.append(p)
        if op<128:
            if op not in [0,4,8,12]:raise ValueError(('Unexpected beast/victim slot',p,op))
            slot=op//4
            if frame_set==1 and slot not in [2,3]:raise ValueError(('Unloaded knight family',p,slot))
            if frame_set==2 and slot not in [0,1]:raise ValueError(('Unloaded beast family',p,slot))
            layers.append(dict(slot=slot,frame=arg,x=struct.unpack_from('>h',m.DATA,p+4)[0],y=struct.unpack_from('>b',m.DATA,p+2)[0]-52,flags=m.DATA[p+3]))
            p+=6;continue
        if op==0xb4:
            target=struct.unpack_from('>I',m.DATA,p+2)[0]
            if ALLOWED_BRANCHES.get(p)!=target or RELOC.get(p+2)!=4:raise ValueError(('Unverified death branch',p))
            if dead:p=target;hold=1;continue
        elif op==0x84:
            target=struct.unpack_from('>I',m.DATA,p+2)[0]
            if arg!=3 or ALLOWED_JUMPS.get(p)!=target or RELOC.get(p+2)!=4:raise ValueError(('Unverified direct return',p))
            p=target;continue
        elif op==0xc0:frame_set=arg
        elif op==0x80:mirror=not mirror if arg==255 else arg==3
        elif op==0x88:
            # The final80-step background corpse hold has no further motion.
            # Keep its actual cel; persistent native remains replace its disposal wait.
            hold=1 if p==6012 else arg
        elif op==0xa4:events.append(dict(pose=len(poses),source=p,options=[[arg]],context='knight' if frame_set==1 else 'war_beast'))
        elif op==0xb0:
            events.append(dict(pose=len(poses),source=p,routine=[RELOC.get(p+2),struct.unpack_from('>I',m.DATA,p+2)[0]],context='knight' if frame_set==1 else 'war_beast'))
        elif op==0xbc:break # disposal control is not an extra duplicate drawing
        elif op==0xff:
            if layers:poses.append(dict(layers=layers,hold=hold,mirror=mirror))
            layers=[];hold=1
            if arg==255:break
        elif op not in [0x8c,0xac,0xcc,0xa0]:raise ValueError(('Unexpected path control',p,hex(op)))
        p+=m.SIZES[op]
    else:raise ValueError(('Unterminated beast path',start))
    if not poses:raise ValueError(('Empty path',start))
    return poses,events,trace

def configuration():
    profile=copy.deepcopy(m.PROFILES['war_beast'])
    profile['families']+=['B/KN3.ob','B/KN4.ob']
    specs={'defeat':(13310,True,None),'defeat_b':(13310,True,None),'defeat_a':(12908,True,None),
           'impact_same':(13922,False,None),'impact_opposite':(14006,False,None),
           'ejected':(13922,True,None),'fallen_front':(14006,True,None),'settled':(14056,True,None),'knight_recovery':(6546,False,6566)}
    profile['pose_overrides']={};profile['cue_overrides']={};report={}
    for name,(root,dead,stop) in specs.items():
        poses,events,trace=path(root,dead,stop)
        profile['clips'][name]=[root]
        profile['pose_overrides'][name]=poses;profile['cue_overrides'][name]=events
        report[name]=dict(root=root,dead=dead,controls=trace,poses=len(poses),weights=[p['hold'] for p in poses],native_ticks=sum(p['hold'] for p in poses)*6,
            cells=[[dict(slot=l['slot'],frame=l['frame']) for l in p['layers']] for p in poses])
    profile['frame_paths_version']=1
    return profile,report

def bake():
    profile,report=configuration();m.bake('war_beast',profile)
    dest=m.ROOT/'game/assets/classic/war_beast/frame-paths.json'
    dest.write_text(json.dumps(dict(mog_sha1=m.MOG_SHA1,paths=report,limits='Finite draw/hold paths, both HP branches and frame-list switches. Native six-tick mapping and physical motion still require original comparison. Final static corpse wait is represented by persistent remains.'),indent=2)+'\n')
    for key,value in report.items():print(key,value['poses'],'poses',value['native_ticks'],'native ticks')
if __name__=='__main__':bake()
