#!/usr/bin/env python3
"""Keep fixed tree foliage separate from moving Ratman composites, offline."""
import copy,json,struct
import import_creature_pack as m
import import_death_frames as death
import import_hit_recovery as recovery

TREE=['rat_perch','rat_squeeze','rat_squeeze_loop','rat_squeeze_hit','rat_release','rat_squeeze_finish','rat_squeeze_after']
def main():
    # Build on the latest living-hit and complete-death profile. A fresh base
    # profile would silently lose the previously restored overhead reaction.
    profiles,_=recovery.configuration()
    profile=profiles['ratman']
    removed={}
    for name in TREE:
        poses=copy.deepcopy(profile.get('pose_overrides',{}).get(name,[]))
        if not poses:
            for root in profile['clips'][name]:poses.extend(m.poses_at(m.root(root) if isinstance(root,str) else root))
        # 0868 frees its job before the final duplicate background drawing.
        if name=='rat_release':
            assert m.DATA[16934:16936]==bytes.fromhex('bc00')
            poses=poses[:2]
        count=0
        for pose in poses:
            before=len(pose['layers'])
            pose['layers']=[l for l in pose['layers'] if not(l['slot']==0 and l['frame']==63)]
            count+=before-len(pose['layers'])
        profile.setdefault('pose_overrides',{})[name]=poses;removed[name]=count
    m.bake('ratman',profile)
    path=m.ROOT/'game/assets/classic/ratman/provenance.json'
    p=json.loads(path.read_text());p['rat_tree_version']=1
    p['static_leaf_layers_removed']=removed
    path.write_text(json.dumps(p,indent=2)+'\n')
    code=m.HUNKS[0].data
    expected=bytes.fromhex('4eb900001f92080100046700006a080100026700006223fc0000414c00000c0e227900000ce820790000030a4eb900005ae0916900506e000060')
    assert code[25148:25148+len(expected)]==expected
    assert m.DATA[16876:16880]==bytes.fromhex('a45ba45c')
    report={'version':1,'mog_sha1':m.MOG_SHA1,'counter_operand':{'hunk':0,'offset':25148,'bytes':expected.hex()},
      'source_clips':{name:p['roots'][name] for name in TREE},'static_leaf_layers_removed':removed,
      'native_clocks':{'squeeze_intro':30,'squeeze_loop':12,'squeeze_counter':30,'killed_holder_release':18},
      'perch_selection':'Original casterTargetNear: abs(horizontal distance)<60 selects0864; otherwise0863. No alternating idle animation.',
      'rules':['Fire+Down is sampled at native clip boundaries; a surviving sword counter retains the hidden knight and tree reservation.',
               'A killed squeezing holder uses original0868 release at elevated coordinates; the living victim resumes its own ground position.',
               'No fabricated600tick squeeze timeout; idle squeeze drains1HP per12tick loop after the intro.',
               'The original fixed three-leaf object is drawn once; dynamic copies of cel0:63 are omitted from moving composites.'],
      'limits':['Six-tick source pass mapping, original multi-job ordering and true sound/motion parity require running-original comparison.',
                'This pass leaves the existing back-ride escape mechanics and other finishing interactions unchanged.',
                'Intro/menu playback, kneeling-knight follow-up, Mudman last-tick order and the rest of the ending remain separate work.']}
    (m.ROOT/'docs/ratman-tree-paths.json').write_text(json.dumps(report,indent=2)+'\n')
    print('Ratman tree: fixed foliage separated, distance-selected perch,30/12/30/18tick hold paths audited')

if __name__=='__main__':main()
