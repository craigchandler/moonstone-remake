#!/usr/bin/env python3
"""Bake Guardian sequence art and numeric schedules from verified retail paths."""
import json
import import_death_frames as d
import import_knockback as k

ROOTS={'windup':26800,'miss_close':27050,'grab_close':27546,'release_close':27102,
       'miss_far':27254,'grab_far':27470,'release_far':27312,'crush':26172}

def main():
    # The native names are semantic: source E5 selects BC/close; E7 selects BB/far.
    for offset,value in [(2408,27050),(2448,27546),(2208,27102),(2494,27254),(2534,27470),(2304,27312)]:
        k.reference(40,offset,4,value)
    k.reference(4,26274,40,2990);k.reference(4,26704,40,3032)
    code=d.m.HUNKS[40].data
    for low,high,patterns in [(2414,2448,['b07c008c','b07c0078']),
                              (2500,2534,['b07c0096','b07c0082']),
                              (2990,3032,['0469000a0050']),
                              (3032,3160,['06410089','04410089','b27c0140'])]:
        for pattern in patterns:
            if code[low:high].count(bytes.fromhex(pattern))!=1:raise ValueError(('Changed Guardian rule operand',low,high,pattern))
    profiles,report=d.configurations()
    profile=d.merged_profile('complete_guardian_finishes','guardian_finishes',profiles,report)
    profile.update(source_families=profile['families'].copy(),context='guardian',guardian_paths_version=1)
    paths={}
    for name,root in ROOTS.items():
        poses,cues,path=d.resolve(root,profile,dead=False)
        profile['clips'][name]=[root];profile['pose_overrides'][name]=poses;profile['cue_overrides'][name]=cues
        paths[name]=path
    d.m.bake('guardian_finishes',profile)
    clocks={name:p['ticks'] for name,p in paths.items()}
    # Relocated calls in26172:12 native ticks before damage/freeze;90 before release.
    events={}
    for cue in profile['cue_overrides']['crush']:
        if cue.get('routine') in [[40,2990],[40,3032]]:
            events['damage_tick' if cue['routine']==[40,2990] else 'release_tick']=sum(p['hold'] for p in profile['pose_overrides']['crush'][:cue['pose']])*6
    if events!={'damage_tick':12,'release_tick':90}:raise ValueError(('Changed Guardian callback schedule',events))
    text='[gd_resource type="Resource" load_steps=2 format=3]\n[ext_resource type="Script" path="res://scripts/content/guardian_rules.gd" id="1"]\n[resource]\nscript = ExtResource("1")\nclocks = '+d.m.gd(clocks)+'\ncrush_damage_tick = 12\ncrush_release_tick = 90\ncrush_damage = 10\nclose_min = 120\nclose_max = 140\nfar_min = 130\nfar_max = 150\nrelease_offset = 137\n'
    (d.m.ROOT/'game/content/generated/guardian.tres').write_text(text)
    doc=dict(mog_sha1=d.m.MOG_SHA1,paths=paths,clocks=clocks,crush_events=events,
      flow='windup -> close window120..140 -> close grab or miss -> close release -> far window130..150 -> far grab or miss -> far release',
      crush='96 ticks; at12 damage10/freeze; at90 thaw, opposite facing and source137px placement, idle if alive or ordinary death if already dead',
      grabs='Distance gates pause without damage. Close/far release restarts hop at the paused knight position; no137px placement belongs to these paths.',
      limits=['Six-tick mapping and exact original multi-job ordering remain provisional until input-matched original comparison.','Native target ownership is explicit for cooperative play; the original global target/flag cells are not shared between actors.','Original cooldown and Guardian approach/motion parity remain separate from these sequence clocks.','The source timer write through hop-script+106 is recorded, not emulated as self-modifying data.'])
    (d.m.ROOT/'docs/guardian-paths.json').write_text(json.dumps(doc,indent=2)+'\n')
    print('Guardian clocks:',clocks,'callbacks:',events)

if __name__=='__main__':main()
