#!/usr/bin/env python3
"""Bake the original opponent helmet and correctly named scroll cels offline."""
import hashlib,json,struct
from pathlib import Path
from PIL import Image
from import_knight_animations import ROOT,MOG_SHA1,parse_hunk_file

def main():
 data=(ROOT/'reference/extracted/A/mog').read_bytes();assert hashlib.sha1(data).hexdigest()==MOG_SHA1
 h=parse_hunk_file(data).hunks
 palette=list(struct.unpack_from('>32H',h[4].data,39160))
 folder=ROOT/'game/assets/classic/recovered/B/ki.cel';meta=json.loads((folder/'sidecar.json').read_text())
 assert hashlib.sha1((ROOT/'reference/extracted/B/ki.cel').read_bytes()).hexdigest()==meta['source_sha1']
 out=ROOT/'game/assets/classic/targeted_scrolls';out.mkdir(exist_ok=True)
 report={'mog_sha1':MOG_SHA1,'cel_sha1':meta['source_sha1'],'frames':{'black_life':18,'scroll_of_the_hawk':12,'scroll_of_acquisition':13},'note':'Reference button row23=Hawk,24=Acquisition; use slots12/14. Native saved item IDs and existing reward tables are preserved.'}
 for name,index in report['frames'].items():
  colors=palette.copy()
  if name=='black_life':colors[28:32]=[0x27,0x03,0x27,0x03]
  rgb=[((c>>s)&15)*17 for c in colors for s in [8,4,0]]+[0]*672
  image=Image.open(folder/'frames'/f'{index:03d}.png');image.putpalette(rgb);image.info['transparency']=0;image.convert('RGBA').save(out/(name+'.png'))
 (out/'provenance.json').write_text(json.dumps(report,indent=2)+'\n')
 print('Imported original opponent helmet and Hawk/Acquisition pictures')
if __name__=='__main__':main()
