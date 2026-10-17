#!/usr/bin/env python3
"""Audit retail Valley reward and phase gates into native data, offline.

The pinned port's Quarter enum is46, but this disk's actual compare operands
are47. Bind to verified retail bytes, not inferred phase names or stale labels.
"""
import json,struct
import import_creature_pack as m
from import_stonehenge import text_list

def main():
    code=m.HUNKS[0].data
    def verify(offset,hexdata):assert code[offset:offset+len(bytes.fromhex(hexdata))]==bytes.fromhex(hexdata),(offset,hexdata)
    xp_bytes=bytes.fromhex('06680003004e20680060117c00000014')
    assert code.count(xp_bytes)==1
    xp_offset=code.index(xp_bytes)
    verify(5874,'028000000003207900000ce82068006001e80016')
    # Source instruction operands of BTST + following CMP, not source constants.
    quest=[];damage=[]
    for start,register,expected in [(5920,0,[(2,47),(3,47),(1,45),(0,49)]),(23358,2,[(0,47),(3,47),(1,45),(2,49)])]:
        data=[];p=start
        for bit,frame in expected:
            verify(p,'0801'+f'{bit:04x}'+'6708'+f'{0xb07c+register*0x200:04x}'+f'{frame:04x}')
            data.append((bit,frame));p+=14
        ordered=[dict(data)[i] for i in range(4)]
        if register==0:quest=ordered
        else:damage=ordered
    phase_code=bytes.fromhex('b07c002f660408c70000b07c002d660408c70002b07c0031660408c70001')
    assert code.count(phase_code)==1
    winner_code=bytes.fromhex('b0bc00000003660408c70003b0bc00000000660408c70004b0bc00000001660408c70005b0bc00000002660408c70006')
    assert code.count(winner_code)==1
    clock=[45,46,47,48,49,48,47,46]
    assert m.DATA.count(bytes(clock))==1
    # Moonstone cel row: slot22, initial x103/y111, per-bit frames2/1/0/0.
    verify(46400,'33fc001600001be833fc006700001bdc33fc006f00001bde')
    for offset,frame in [(46448,2),(46490,1),(46532,0),(46574,0)]:verify(offset,'33fc'+f'{frame:04x}'+'00001bda')
    data={'version':1,'mog_sha1':m.MOG_SHA1,'reward':{'code_hunk':0,'xp_offset':xp_offset,'xp':3,'consume_keys':True,'random_mask_offset':5874,'random_mask':3,'set_inventory_byte':22},
        'moon_frames':clock,'moon_frame_table_offset':m.DATA.index(bytes(clock)),
        'quest_frames':quest,'damage_frames':damage,'winner_flags':[16,32,64,8],
        'guardian_message':text_list(4,688),'victory_message':text_list(4,476),
        'stone_ids':['moonstone_full','moonstone_new','moonstone_half_a','moonstone_half_b'],
        'stone_names':['Full-moon Moonstone','New-moon Moonstone','Half-moon Moonstone I','Half-moon Moonstone II'],
        'inventory_frames':[2,1,0,0],'inventory_first_position':[103,111],
        'limits':['Retail phase compare47 and clock45/46/47/48/49/48/47/46 differ from pinned port enum46 and swapped46/47 cycle; verify actual bytes.',
            'Sword damage and quest gates use different bit mappings in the retail binary; retain both.',
            'Moonstone uses the source eight-round RNG with an independent saved native seed, not the full original campaign RNG order.',
            'Current campaign knight is blue/kind0; all four ending flag encodings are recovered for later knight selection.',
            'Original ending playback is a subsequent milestone. Native quest result is a saved handoff, not a reconstructed ending film.',
            'Multiple-stone layout is a native fallback; first stone keeps source position103,111.']}
    dest=m.ROOT/'docs/moonstone-quest.json';dest.write_text(json.dumps(data,indent=2)+'\n')
    out='[gd_resource type="Resource" load_steps=2 format=3]\n[ext_resource type="Script" path="res://scripts/content/moonstone_rules.gd" id="1"]\n[resource]\nscript = ExtResource("1")\n'
    for key in ['moon_frames','quest_frames','damage_frames','winner_flags','stone_ids','stone_names','guardian_message','victory_message']:out+=key+' = '+m.gd(data[key])+'\n'
    (m.ROOT/'game/content/generated/moonstone_quest.tres').write_text(out)
    print('Verified retail Valley3XP/key consumption/random stone, quest and sword gates, four ending codes and original inventory cels')

if __name__=='__main__':main()
