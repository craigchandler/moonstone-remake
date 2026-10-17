#!/usr/bin/env python3
"""Bake finite surviving-hit and landing paths; original data is offline only."""
import copy,json
import import_death_frames as d

SPECS={
 'trogg_hammer':{'hurt_a':11834,'hurt_b':11980,'hurt_c':12098},
 'ratman':{'hurt_a':16384,'hurt_b':16988,'hurt_heavy':16184},
 'knight_finishes':{'hop':6578}}

def configuration():
    death_profiles,death_report=d.configurations()
    profiles={'trogg_hammer':copy.deepcopy(d.m.PROFILES['trogg_hammer']),
              'ratman':d.merged_profile('complete_ratman','ratman',death_profiles,death_report),
              'knight_finishes':copy.deepcopy(d.f.profiles['knight_finishes'])}
    report={}
    for family,profile in profiles.items():
        profile.update(source_families=profile['families'].copy(),context='knight' if family=='knight_finishes' else family,hit_paths_version=1)
        profile.setdefault('pose_overrides',{});profile.setdefault('cue_overrides',{})
        report[family]={}
        for name,root in SPECS[family].items():
            poses,events,path=d.resolve(root,profile,dead=False,frame_set=1 if family=='knight_finishes' else 2)
            profile['clips'][name]=[root];profile['pose_overrides'][name]=poses;profile['cue_overrides'][name]=events
            report[family][name]=path
    return profiles,report

def main():
    profiles,report=configuration()
    for family,profile in profiles.items():d.m.bake(family,profile)
    clocks={family:{name:p['ticks'] for name,p in paths.items()} for family,paths in report.items()}
    resource='[gd_resource type="Resource" load_steps=2 format=3]\n[ext_resource type="Script" path="res://scripts/content/hit_recovery.gd" id="1"]\n[resource]\nscript = ExtResource("1")\nclocks = '+d.m.gd(clocks)+'\n'
    (d.m.ROOT/'game/content/generated/hit_recovery.tres').write_text(resource)
    doc=dict(mog_sha1=d.m.MOG_SHA1,paths=report,clocks=clocks,limits='Retail draw/hold/return paths with living-owner branches. Native six-tick timing and movement still require running-original comparison; no invented hop trajectory is added.')
    (d.m.ROOT/'docs/hit-recovery-paths.json').write_text(json.dumps(doc,indent=2)+'\n')
    print(json.dumps(clocks,indent=2))

if __name__=='__main__':main()
