#!/usr/bin/env python3
"""Bake original location outlines and four knight colors, offline."""
from pathlib import Path
from PIL import Image
import json,sys,hashlib,struct
from import_knight_animations import parse_hunk_file,MOG_SHA1
R=Path(__file__).resolve().parents[1]
def main():
 mog=(R/'reference/extracted/A/mog').read_bytes();assert hashlib.sha1(mog).hexdigest()==MOG_SHA1
 h=parse_hunk_file(mog).hunks
 assert h[0].data[6232:6244]==bytes.fromhex('0c28000300496c0606280001') # castle life cap and increment
 assert h[36].data[844:868]==bytes.fromhex('0800000467284a7900001ae267046100071461000d864a40') # fire gate and arrival call
 nodes=[struct.unpack_from('>hHH',h[2].data,100+6*i) for i in range(10)]
 assert nodes==[(21,18,11),(22,286,11),(23,0,187),(24,303,192),(25,82,28),(26,277,143),(28,152,97),(27,88,155),(30,217,11),(-1,65535,65535)]
 recovered=R/'game/assets/classic/recovered/B';meta=json.loads((recovered/'test/sidecar.json').read_text());cel=json.loads((recovered/'mi.c/sidecar.json').read_text())
 assert hashlib.sha1((R/'reference/extracted/B/mi.c').read_bytes()).hexdigest()==cel['source_sha1']
 pal=meta['records'][8]['palette_rgb12'];colors=[((c>>s)&15)*17 for c in pal for s in (8,4,0)];colors+=[0]*(768-len(colors))
 out=R/'game/assets/classic/world';resource=out/'art.tres';text=resource.read_text();extra={};sizes={}
 for i in list(range(10))+list(range(21,29))+[30,31,33]:
  im=Image.open(recovered/'mi.c/frames'/f'{i:03d}.png');sizes[str(i)]=list(im.size)
  # Original31 starts at F1F and is ramped toward0FF, not literal magenta.
  # Change the indexed register; other knight and lair pixels retain their colors.
  active_colors=colors.copy()
  if i>=5:active_colors[31*3:32*3]=[0,255,255]
  im.putpalette(active_colors);im.info['transparency']=0;im=im.convert('RGBA')
  im.save(out/f'map_{i}.png');extra[str(i)]=f'res://assets/classic/world/map_{i}.png'
 # Idempotent: strip only declarations emitted by this importer.
 import re
 text=re.sub(r'^\[ext_resource[^\n]+id="map_[0-9]+"\]\n','',text,flags=re.M);text=re.sub(r'^map_icons = .*\n','',text,flags=re.M)
 decl=''.join(f'[ext_resource type="Texture2D" path="{path}" id="map_{key}"]\n' for key,path in extra.items())
 text=text.replace('[resource]',decl+'[resource]');text=re.sub(r'load_steps=\d+',f'load_steps={text.count("[ext_resource")+1}',text,count=1)
 text+='map_icons = {'+', '.join(f'"{key}": ExtResource("map_{key}")' for key in extra)+'}\n';resource.write_text(text)
 report={'version':1,'mog_sha1':MOG_SHA1,'map_nodes':{'hunk':2,'offset':100,'rows':nodes},'sprite_sizes':sizes,'map_cel_sha1':cel['source_sha1'],'rules':['Original sprite-sized inclusive overlap, knight8x10, lair9x5. Coordinates are top left.','Normal mapFrame fire bit4 invokes arrivalMenu: one row dispatch; multiple numbered rows. Forced lair and Dragon attacks remain separate.','Only current knight home is an available node. Castle life cap3 then temple/status9 then spent turn. Wizard shows Math sequence then temple/status9 and spent turn.'],'limits':['Native outline pulsing cadence provisional; source uses palette register31 ramp.','Wizard animated gift/curses remain pending; tower opens a labelled character-sheet preview.']}
 (R/'docs/map-locations.json').write_text(json.dumps(report,indent=2)+'\n');print('Imported original map nodes, outline sprites and knight markers')
if __name__=='__main__':main()
