#!/usr/bin/env python3
"""Supplementary original finish poses, baked once into native atlases.

Verified retail roots only. Calls, movement and branches stay in native rules.
The eight repetitions of Balok's shake are a rule clock, not a draw-VM loop.
"""
import json
import import_creature_pack as m

m.SCENES.update({0x20:[0x104,0x102,0,0x600,0x300,0x693,0xc00],
                 0x30:[0xf96,0xc63,0x930,0x842,0x521,0xf63,0xc00]})
profiles = {
 'spear_finishes':dict(families=['B/TROGGSpear1.CEL','B/TROGGSpear2.CEL'],scene=0x20,region=0,
  clips={'idle':[10386],'walk':[10386],'hurt_a':[10386],'impale':[10472]},attacks=[]),
 'balok_finishes':dict(families=['C/Balok1.CEL','C/Balok3.CEL','C/Balok2.CEL'],scene=0x30,region=12,
  clips={'idle':[20062],'walk':[20062],'hurt_a':[20484],'lift':[20970],'shake':[21146],
         'eat_a':[21258],'eat_b':[21970],'defeat':[20542]},attacks=[]),
 'knight_finishes':dict(families=['B/KN1.ob','B/KN2.ob','B/KN3.ob','B/KN4.ob','C/KN5.ob'],scene=0,region=0,
  clips={'idle':[5788],'walk':[5788],'hurt_a':[5788],'hurt_b':[5644],
         'hop':[6578],'flung':[6920]},attacks=[]),
 'mud_finishes':dict(families=['C/Mudmen1.CEL','C/Mudmen2.CEL'],scene=4,region=8,
  clips={'idle':[23148],'walk':[23148],'hurt_a':[24454],'appear':[22948],'withdraw':[23114],
         'carry':[23560],'release':[23634],'swallow':[23918],'quick_drag':[24178]},attacks=[]),
 'hammer_finishes':dict(families=['B/TROGGAxe1.CEL','B/TROGGAxe2.CEL'],scene=0x18,region=12,
  clips={'idle':[11334],'walk':[11334],'hurt_a':[11834],'hurt_b':[11980],
         'defeat_a':[12450],'defeat_b':[12544]},attacks=[]),
 'guardian_finishes':dict(families=['C/Demon2.CEL',None,'C/Demon3.CEL','C/Demon4.CEL','C/Demon1.CEL'],scene=8,region=12,
  clips={'idle':[25722],'walk':[25722],'hurt_a':[27684],'intro':[25182],'body':[25600],
         'grab_close':[27546],'grab_far':[27470],'release_close':[27102],
         'release_far':[27312],'defeat':[27836]},attacks=[])
}

if __name__ == '__main__':
    clocks={}
    for name,profile in profiles.items():
        m.bake(name,profile)
        clocks[name]={clip:sum(p['hold'] for root in roots for p in m.poses_at(root))*6
                      for clip,roots in profile['clips'].items()}
    (m.ROOT/'game/content/generated/finish-clocks.json').write_text(json.dumps(clocks,indent=2)+'\n')
