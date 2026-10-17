#!/usr/bin/env python3
"""Repair native sequence metadata only; keep every original atlas pixel intact."""
from pathlib import Path
import hashlib,json,sys
sys.dont_write_bytecode=True
from import_knight_animations import gd

R=Path(__file__).resolve().parents[1]
hammer=R/'game/assets/classic/trogg_hammer';axe=R/'game/assets/classic/trogg_axe'
raw=(R/'reference/extracted/A/mog').read_bytes()
assert hashlib.sha1(raw).hexdigest()=='bb38bc0b39f146b30bac959bea717202cf13b965'
for folder in [hammer,axe]:
    p=folder/'provenance.json';m=json.loads(p.read_text())
    if folder==hammer:
        clip=m['clips']['hammer_chop'];assert clip['frames']==list(range(17,24))
        flagged=[i for i in clip['frames'] if any(l['flags']&2 for l in m['poses'][i]['layers'])]
        assert flagged==[17,20,21,22]
        original=m['contacts']['hammer_chop']
        if len(original)==4:original=dict(zip(flagged,original))
        else:
            assert len(original)==6;original=dict(zip(range(17,23),original))
        timeline=[original.get(i,{'points':[],'weight':m['poses'][i]['hold']}) for i in range(17,23)]
        assert not timeline[1]['points'] and not timeline[2]['points']
        clip['phases']={'windup':[],'active':list(range(17,23)),'recovery':[23]}
        m['contacts']['hammer_chop']=timeline
        geo=R/'game/content/generated/trogg_hammer_collision.tres'
        text=geo.read_text();geo.write_text(text.split('attacks = ',1)[0]+'attacks = '+gd(m['contacts'])+'\n')
    else:
        m['clips']['attack_return']={'frames':[23],'weights':[1],'step_ticks':1}
    m['trogg_timing_version']=1;p.write_text(json.dumps(m,indent=2)+'\n')
    resource=folder/'animations.tres';text=resource.read_text()
    resource.write_text(text.split('clips = ',1)[0]+'clips = '+gd(m['clips'])+'\n')
print('PASS: all seven Hammer chop drawings and original contact gaps; Axe last-drawing return; atlas pixels untouched')
