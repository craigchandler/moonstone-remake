#!/usr/bin/env python3
"""Repair overlapping phase metadata without altering recovered pixels or contacts."""
from pathlib import Path
import hashlib,json,sys
sys.dont_write_bytecode=True
from import_knight_animations import gd
R=Path(__file__).resolve().parents[1]
assert hashlib.sha1((R/'reference/extracted/A/mog').read_bytes()).hexdigest()=='bb38bc0b39f146b30bac959bea717202cf13b965'
PATCHES={
 'giant_troll':{'troll_sweep':{'windup':[5],'active':[6,7],'recovery':[]}},
 'ratman':{'rat_bite':{'windup':[9],'active':[10,11,12],'recovery':[]}},
 'dragon':{'dragon_bite':{'windup':[],'active':[19,20,21,22],'recovery':[]}},
 'guardian':{'guardian_lunge':{'windup':[4],'active':[5,6,7],'recovery':[8]}}
}
for kind,patches in PATCHES.items():
 folder=R/'game/assets/classic'/kind;p=folder/'provenance.json';m=json.loads(p.read_text())
 for move,phases in patches.items():
  assert [i for phase in ['windup','active','recovery'] for i in phases[phase]]==m['clips'][move]['frames']
  m['clips'][move]['phases']=phases
  if kind=='guardian':
   frames=m['contacts'][move]
   if len(frames)==4:assert not frames[-1]['points'];m['contacts'][move]=frames[:-1]
   assert len(m['contacts'][move])==3
   g=R/'game/content/generated/guardian_collision.tres';text=g.read_text();g.write_text(text.split('attacks = ',1)[0]+'attacks = '+gd(m['contacts'])+'\n')
 m['monster_timing_version']=1;p.write_text(json.dumps(m,indent=2)+'\n')
 resource=folder/'animations.tres';text=resource.read_text();resource.write_text(text.split('clips = ',1)[0]+'clips = '+gd(m['clips'])+'\n')
print('PASS: four non-overlapping original phase sequences; all pixels and nonempty weapon contacts unchanged')
