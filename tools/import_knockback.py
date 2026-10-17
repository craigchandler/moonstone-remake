#!/usr/bin/env python3
"""Recover verified retail hop numbers as native rules; never run original code."""
import json,struct
import import_creature_pack as m

def reference(hunk,offset,target,value):
    chunk=m.HUNKS[hunk]
    entries={p:g.target_hunk for g in chunk.reloc32 for p in g.offsets}
    if entries.get(offset)!=target or struct.unpack_from('>I',chunk.data,offset)[0]!=value:
        raise ValueError(('Unverified retail reference',hunk,offset,target,value))

def main():
    # LAB_0203 installs the normal hop table and global table cell. Later port
    # label offsets differ from this retail file by four bytes.
    reference(0,22452,4,28542);reference(0,22456,4,28564)
    reference(0,23026,4,28568);reference(0,23036,4,28568)
    reference(0,23108,4,28564);reference(0,23114,4,28568)
    reference(4,6584,0,23022)
    for p in [6592,6614]:reference(4,p,0,23032)
    if m.HUNKS[0].data[23022:23026]!=bytes.fromhex('33fcffff'):
        raise ValueError('Hop counter no longer resets to -1')
    for p in [6588,6610]:
        if m.DATA[p:p+2]!=bytes.fromhex('8802'):raise ValueError('Changed hop callback repetition')
    table=list(struct.unpack_from('>5h',m.DATA,28542));other=list(struct.unpack_from('>5h',m.DATA,28552));steps=table[:4]
    text='[gd_resource type="Resource" load_steps=2 format=3]\n[ext_resource type="Script" path="res://scripts/content/knockback_rules.gd" id="1"]\n[resource]\nscript = ExtResource("1")\nhop_steps = PackedInt32Array('+', '.join(map(str,steps))+')\nstep_ticks = 6\nfront_offset = 25\nleft_limit = 10\nright_limit = 320\n'
    (m.ROOT/'game/content/generated/knockback.tres').write_text(text)
    report=dict(mog_sha1=m.MOG_SHA1,retail_table=dict(hunk=4,offset=28542,words=table),
      guardian_attack_table_not_used=dict(hunk=4,offset=28552,words=other),
      hop=dict(root=6578,reset_routine=[0,23022],step_routine=[0,23032],callback_sources=[6590,6612],repeats=[2,2],steps=steps,native_step_ticks=6,events=[dict(tick=i*6,dx=dx) for i,dx in enumerate(steps)],unclipped_total=sum(steps),height_delta=0,depth_delta=0),
      boundary=dict(front_offset=25,left_limit=10,right_limit=320,rule='Check current front before each step; blocked steps are consumed. Source overshoot is retained.'),
      directions=dict(troll_sweep='attacker facing',balok_swipe='attacker facing',guardian_lunge='attacker facing',guardian_release='holder facing',dragon_part='right; rendered facing left'),
      limits=['Native six-tick scheduling still needs a matched running-original comparison.','The original global direction/counter becomes per-actor native state so concurrent/co-op recoveries cannot change one another.','Only the shared knight hop is covered; remaining creature arcs, flung/fragment physics and original job ordering remain separate.','Normal movement retains native22..298 bounds; an overshot hop returns gradually rather than snapping into them.'])
    (m.ROOT/'docs/knockback-paths.json').write_text(json.dumps(report,indent=2)+'\n')
    print('Verified retail hop:',steps,'=',sum(steps),'pixels; no added vertical/depth motion')

if __name__=='__main__':main()
