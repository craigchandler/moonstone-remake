#!/usr/bin/env python3
"""Bake the verified original overworld slowdown/region grids into native data."""
from pathlib import Path
from collections import Counter
import hashlib,json,struct
from import_knight_animations import MOG_SHA1,parse_hunk_file
ROOT=Path(__file__).resolve().parents[1]
def main():
    raw=(ROOT/'reference/extracted/A/mog').read_bytes()
    assert hashlib.sha1(raw).hexdigest()==MOG_SHA1
    hunks=parse_hunk_file(raw).hunks
    reloc={o for g in hunks[36].reloc32 if g.target_hunk==4 for o in g.offsets}
    for pointer,target in [(2008,29554),(4922,30554)]:
        assert pointer in reloc and hunks[36].data[pointer-2:pointer]==bytes.fromhex('41f9')
        assert struct.unpack_from('>I',hunks[36].data,pointer)[0]==target
    terrain=hunks[4].data[29554:30554];regions=hunks[4].data[30554:31594]
    assert len(terrain)==1000 and set(terrain)=={0,1,2,3}
    assert Counter(terrain)=={0:382,1:308,2:165,3:145}
    assert len(regions)==1040 and set(regions)=={0,4,8,12}
    out=ROOT/'game/content/generated';out.mkdir(exist_ok=True)
    resource='''[gd_resource type="Resource" script_class="MoonstoneMapTravelRules" load_steps=2 format=3]
[ext_resource type="Script" path="res://scripts/content/map_travel_rules.gd" id="1"]
[resource]
script = ExtResource("1")
'''
    for name,data in [('terrain',terrain),('regions',regions)]:resource+=name+' = PackedByteArray('+', '.join(map(str,data))+')\n'
    (out/'classic_map_travel.tres').write_text(resource)
    (out/'map_travel_provenance.json').write_text(json.dumps({'mog_sha1':MOG_SHA1,'terrain':{'hunk':4,'offset':29554,'bytes':1000,'sha256':hashlib.sha256(terrain).hexdigest(),'histogram':dict(Counter(terrain))},'regions':{'hunk':4,'offset':30554,'bytes':1040,'sha256':hashlib.sha256(regions).hexdigest()},'lookup':'40 columns,8x8 cells, knight feet at x+4/y+10; each axis clamped','counter':'16-bit; increment on nonzero mask even if idle; blocked when counter & mask !=0','runtime':'Native data only; no original executable/CPU/script runtime'},indent=2)+'\n')
    print('Imported verified original40x25 terrain and40x26 region grids')
if __name__=='__main__':main()
