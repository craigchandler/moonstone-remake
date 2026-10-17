#!/usr/bin/env python3
"""Offline: recover beast-arena floor edges and independent entry expectations."""
from pathlib import Path
import hashlib, json, struct, sys

ROOT = Path(__file__).resolve().parents[1]
sys.dont_write_bytecode = True
sys.path.insert(0, str(ROOT / 'work/upstream/moonstone-ace/tools'))
from hunkfile import parse_hunk_file
from artconv import lzss_decode

raw = (ROOT / 'reference/extracted/A/mog').read_bytes()
assert hashlib.sha1(raw).hexdigest() == 'bb38bc0b39f146b30bac959bea717202cf13b965'
h = parse_hunk_file(raw).hunks
# Retail offsets differ from the reassembled reference's label addresses.
counter = 19514
assert struct.unpack_from('>H', h[0].data, counter)[0] == 0
assert h[0].data[19400:19418] == bytes.fromhex('0679000100004c3a0279000300004c3a67ee')
references = [o for g in h[0].reloc32 if g.target_hunk == 0 for o in g.offsets
              if struct.unpack_from('>I', h[0].data, o)[0] == counter]
assert sorted(references) == [19404, 19412, 19422, 19438, 19454]
sites = {}
for row in json.loads((ROOT / 'game/content/generated/original_lairs.json').read_text()):
    if row['encounter'] != 'beast_lair':
        continue
    blob = (ROOT / 'reference/extracted/C' / row['source_backdrop']).read_bytes()
    assert struct.unpack_from('>I', blob)[0] == len(blob) - 4
    data = lzss_decode(blob[4:])
    count = struct.unpack_from('>H', data)[0]
    # LAB_0A6F uses DBF: include the extra record read after count records.
    depths = [struct.unpack_from('>h', data, 6 + 8 * i)[0] for i in range(count + 1)]
    edge = max([30] + depths)
    sites[row['id']] = dict(source=row['source_backdrop'], sha256=hashlib.sha256(blob).hexdigest(),
                           obstacle_count=count, scanned_depths=depths, low_edge=edge)
assert {k: v['low_edge'] for k, v in sites.items()} == {'grassland_east': 123, 'grassland_south': 124}

cases = []
for edge in range(30, 201):
    # Independent unsigned-word calculation, before the native foot-anchor offset.
    span = (-(edge - 200)) & 65535
    mid = span >> 1
    lanes = {1: (mid + (mid >> 1) + edge - 47) & 65535,
             2: ((span >> 2) + edge - 47) & 65535,
             3: (mid + edge - 47) & 65535}
    for previous in range(4):
        following = (previous + 1) & 3
        if not following: following = 1
        cases.append(dict(low_edge=edge, counter=previous, expected_counter=following,
                          expected_depth=lanes[following] + 52))
fixture = dict(retail_sha1=hashlib.sha1(raw).hexdigest(), counter_hunk=0, counter_offset=counter,
               initial_counter=0, reference_commit='f0d699a2b92d42d5380429ea9f2d94f7534324ef',
               native_foot_offset=52, default_edge=99, sites=sites, cases=cases)
(ROOT / 'game/tests/fixtures/beast_entries.json').write_text(json.dumps(fixture, separators=(',', ':')) + '\n')
resource = '''[gd_resource type="Resource" load_steps=2 format=3]
[ext_resource type="Script" path="res://scripts/gameplay/classic_entry_placement.gd" id="1"]
[resource]
script = ExtResource("1")
behavior_id = &"classic:beast_entry"
api_version = 1
content_version = 1
initial_counter = 0
default_low_edge = 99
foot_offset = 52
site_edges = ''' + json.dumps({k: v['low_edge'] for k, v in sites.items()}) + '\n'
(ROOT / 'game/content/generated/classic_beast_entry.tres').write_text(resource)
print(f'PASS: {len(cases)} independent entry cases and both retail beast backdrop edges; numeric resources only')
