#!/usr/bin/env python3
"""Offline selection art and exact baked class-colour variants. Native assets only."""
from pathlib import Path
import hashlib,json,struct,re,os
import numpy as np
from PIL import Image
from import_support import ImportProgress, rgba_array, compact_source_atlas
from import_knight_animations import ROOT,parse_hunk_file,MOG_SHA1,gd
import import_hit_recovery as recovery
import import_death_frames as deaths
profiles,_=deaths.configurations()
merged_profiles,_=recovery.configuration()
profiles.update(merged_profiles)
out=ROOT/'game/assets/classic/knight_selection';out.mkdir(exist_ok=True)
raw=(ROOT/'reference/extracted/A/mog').read_bytes();assert hashlib.sha1(raw).hexdigest()==MOG_SHA1
h=parse_hunk_file(raw).hunks;d=h[4].data;rel={o:g.target_hunk for g in h[4].reloc32 for o in g.offsets}
palette=list(struct.unpack_from('>32H',d,1142));assert max(palette)<=0xfff
assert struct.unpack_from('>4H',d,1214)==(12,88,164,240)
at,x,y,flags,nxt=struct.unpack_from('>IhhhI',d,772);assert rel[772]==4 and x==0 and y==5 and flags==1 and nxt==0 and d[at:d.index(0,at)]==b'Select a Knight'
source_hashes={}
def recovered(name):
 f=ROOT/'game/assets/classic/recovered'/name;m=json.load(open(f/'sidecar.json'));sha=hashlib.sha1((ROOT/'reference/extracted'/name).read_bytes()).hexdigest();assert sha==m['source_sha1'];source_hashes[name]=sha;return f,m
def rgba(im,pal):
 im=im.copy();im.putpalette([((c>>s)&15)*17 for c in pal for s in [8,4,0]]+[0]*(768-3*len(pal)));im.info['transparency']=0;return im.convert('RGBA')
refs={};n=0
def save(im,name):im.save(out/name);return reference('res://assets/classic/knight_selection/'+name)
def reference(path):
 global n
 if path not in refs:n+=1;refs[path]='t'+str(n)
 return refs[path]
f,m=recovered('B/sel.cel');portraits=[save(rgba(Image.open(f/f'frames/{i:03d}.png'),palette),f'portrait-{i-2}.png') for i in range(2,6)];highlight=save(rgba(Image.open(f/'frames/001.png'),palette),'highlight.png')
font,m=recovered('A/bold.f');p=parse_hunk_file((ROOT/'reference/extracted/A/program').read_bytes()).hunks[2].data;charmap=p[11744:11840]
fontatlas=Image.new('RGBA',(512,128));glyphs={};gx=gy=0
for code in range(32,127):
 im=rgba(Image.open(font/f'frames/{charmap[code-32]:03d}.png'),palette)
 if gx+im.width>512:gx=0;gy+=20
 assert gy+im.height<=128
 fontatlas.alpha_composite(im,(gx,gy));glyphs[chr(code)]=[gx,gy,im.width,im.height];gx+=im.width+1
fontref=save(fontatlas,'font.png')
mapfolder,mm=recovered('B/mi.c');_,mapmeta=recovered('B/test');mp=mapmeta['records'][8]['palette_rgb12']
tokens=[save(rgba(Image.open(mapfolder/f'frames/{i:03d}.png'),mp),f'token-{i}.png') for i in range(4)]
active=[save(rgba(Image.open(mapfolder/f'frames/{i+5:03d}.png'),mp),f'active-{i}.png') for i in range(4)]
frogs=[save(rgba(Image.open(mapfolder/f'frames/{i+43:03d}.png'),mp),f'frog-{i}.png') for i in range(4)]
ui,meta=recovered('B/ki.cel');uipal=list(struct.unpack_from('>32H',d,39160))
ramps=[[0x05d,0x03b,0x028,0x016,0x003],[0xfa0,0xc60,0xb40,0x930,0x710],[0x0c5,0x0a3,0x082,0x061,0x040],[0xe00,0xb00,0x900,0x600,0x300]]
life=[]
for kind in range(4):
 pal=uipal.copy();pal[6:11]=ramps[kind]
 life.append(save(rgba(Image.open(ui/'frames/017.png'),pal),f'life-{kind}.png'))
# Work from existing native transparent sprites. Only exact baked class swatches
# are replaced; geometry/alpha and unrelated pixels remain identical. Full scene
# pictures use their separately reviewed five/four-shade screen ramps.
combat=[[0x00a,0x007,0x004],[0xf80,0xc50,0xa30],[0x8c6,0x593,0x251],[0xf22,0xb22,0x700],[0x206,0x103,0x001]]
def rgb(c):return tuple(((c>>s)&15)*17 for s in [8,4,0])
source_cells={}
verified_families={}
def class_mask(file,clean):
 """Recover the original6..8register mask with source layer occlusion.

 Equal RGB shades at other registers (notably Hammer Trogg register10) must
 stay fixed. Provenance carries the finite poses; this is not a runtime VM.
 """
 folder=file.parent;kind=folder.name
 meta=json.load(open(folder/'provenance.json'))
 assert meta['mog_sha1']==MOG_SHA1
 families=meta.get('families')
 if families is None:
  families={'knight':['B/KN1.ob','B/KN2.ob','B/KN3.ob','B/KN4.ob'],
   'giant_troll':['B/Troll1.cel','B/Troll2.cel'],
   'balok':['C/Balok1.CEL','C/Balok2.CEL','C/Balok3.CEL'],
   'trogg_spear':['B/TROGGSpear1.CEL','B/TROGGSpear2.CEL'],
   'trogg_axe':['B/TROGGAxe1.CEL','B/TROGGAxe2.CEL']}[kind]
 text=(folder/'animations.tres').read_text()
 rects=[list(map(int,m)) for m in re.findall(r'"region": Rect2\(\s*(-?\d+),\s*(-?\d+),\s*(\d+),\s*(\d+)\), "offset": Vector2\(\s*(-?\d+),\s*(-?\d+)\)',text)]
 assert len(rects)==len(meta['poses']),(kind,len(rects),len(meta['poses']))
 canvas=Image.new('L',Image.open(file).size)
 seen=set()
 for index,p in enumerate(meta['poses']):
  rectangle=tuple(rects[index][:4])
  if rectangle in seen:continue
  seen.add(rectangle)
  if clean:
   for clip,poses in profiles.get(kind,{}).get('pose_overrides_clean',{}).items():
    frames=meta['clips'][clip]['frames']
    if index in frames:p=poses[min(len(poses)-1,frames.index(index)*len(poses)//len(frames))];break
   if kind=='knight' and index in meta['clips']['defeat_gory']['frames']:
    frames=meta['clips']['defeat_gory']['frames'];fallback=meta['clips']['defeat']['frames']
    p=meta['poses'][fallback[min(3,frames.index(index)*4//len(frames))]]
   if kind in ['trogg_spear','trogg_axe']:
    for clip in ['defeat_split','defeat_guts']:
     frames=meta['clips'][clip]['frames']
     if index in frames:
      fallback=meta['clips']['defeat']['frames'];p=meta['poses'][fallback[min(len(fallback)-1,frames.index(index)*len(fallback)//len(frames))]];break
  rx,ry,width,height,left,top=rects[index]
  for layer in p['layers']:
   if clean and layer['flags']&0x80:continue
   if p.get('omit_projectile') and layer['slot']==3 and layer['frame']==10:continue
   if clean and kind=='dragon' and index in meta['clips']['execution_bite']['frames'] and layer['slot']==4:continue
   family=families[layer['slot']];assert family is not None
   if family not in verified_families:
    relative=Path(family);parent=ROOT/'game/assets/classic/recovered'/relative.parent
    matches=[p for p in parent.iterdir() if p.is_dir() and p.name.casefold()==relative.name.casefold()]
    assert len(matches)==1,(family,matches)
    canonical=matches[0].relative_to(ROOT/'game/assets/classic/recovered').as_posix()
    recovered(canonical);verified_families[family]=canonical
   family=verified_families[family]
   key=(family,layer['frame'],clean,kind in ['dragon','complete_dragon','death_dragon','dragon_victim','complete_burn'])
   if key not in source_cells:
    cel=Image.open(ROOT/'game/assets/classic/recovered'/family/'frames'/f'{layer["frame"]:03d}.png')
    assert cel.mode=='P'
    indices=Image.frombytes('L',cel.size,cel.tobytes())
    mask=indices.point(lambda v:255 if v and (not clean or key[3] or v!=15) else 0)
    source_cells[key]=(indices,mask)
   indices,mask=source_cells[key];x=layer['x']
   if p.get('mirror',False):x=-x-indices.width;indices=indices.transpose(Image.Transpose.FLIP_LEFT_RIGHT);mask=mask.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
   canvas.paste(indices,(rx+x-left,ry+layer['y']-top),mask)
 return np.array(canvas)
if os.environ.get('MOONSTONE_COMPACT_LAYERS')=='1':
 # The older base converters still produce large fixed-cell sheets. Crop their
 # transparent padding before recovering register masks, retaining frame anchors.
 for name in ['knight','trogg_spear','trogg_axe','giant_troll','balok','hit_effects']:
  compact_source_atlas(ROOT,name)
paths=set()
for resource in (ROOT/'game/assets/classic').glob('*/animations.tres'):
 # Contact blood has no fighter colour registers or per-knight variants.
 if resource.parent.name=='hit_effects':continue
 for path in re.findall(r'path="(res://assets/[^\"]+\.png)"',resource.read_text()):
  if '/knight/purple' not in path:paths.add(path)
for folder in ['stonehenge','town_locations']:
 paths.update('res://'+p.relative_to(ROOT/'game').as_posix() for p in (ROOT/'game/assets/classic'/folder).glob('*.png') if p.name!='frog.png')
paths.add('res://assets/classic/world/tavern-blue.png')
compact=os.environ.get('MOONSTONE_COMPACT_LAYERS')=='1'
compact_masks={}
mask_folder=ROOT/'work/combat-colour-masks'
if compact:mask_folder.mkdir(parents=True,exist_ok=True)
def colour_variants(index,path):
 # Keep large images and temporaries local to one sheet: the previous sheet's
 # buffers must be released before loading the next one on a small handheld.
 # WI1.P and wizard cels0..14 use a fixed palette (including Math's blue
 # robes), not the knight ramp. Only the WI2 knight track uses class colours.
 if path.endswith('/town_locations/gift.png'):return
 if '/town_locations/wizard_' in path and int(Path(path).stem.split('_')[1])<15:return
 file=ROOT/'game'/path.removeprefix('res://')
 screen=('/stonehenge/' in path or '/town_locations/' in path or 'tavern-blue' in path)
 if compact and not screen:
  # The layered renderer colours small pieces at draw time. Keep the original
  # register mask for direct factoring, instead of encoding five full atlases
  # only to decode and discard them in the next conversion step.
  indices=class_mask(file,'clean' in file.stem)
  lookup=np.zeros(256,dtype=np.uint8);lookup[6:9]=[1,2,3]
  mask=lookup[indices]
  target=mask_folder/f'{index}.png'
  Image.fromarray(mask).save(target)
  compact_masks[path]={'mask':target.relative_to(ROOT).as_posix(),
                       'mask_sha256':hashlib.sha256(target.read_bytes()).hexdigest(),
                       'source_sha256':hashlib.sha256(file.read_bytes()).hexdigest()}
  return
 a=rgba_array(file)
 source=ramps[0] if screen else combat[0]
 # Compare channels directly: reducing an HxWx3 temporary dominates conversion
 # on small ARM CPUs, while these masks select exactly the same source pixels.
 # Sprites occupy little of these large atlases. Store only matching offsets,
 # rather than retaining three to five full-sheet boolean masks per variant.
 positions=[np.flatnonzero((a[:,:,0]==r)&(a[:,:,1]==g)&(a[:,:,2]==b)&(a[:,:,3]>0)) for r,g,b in map(rgb,source)]
 original_rgb_matches=sum(len(offsets) for offsets in positions)
 if not screen:
  indices=class_mask(file,'clean' in file.stem)
  positions=[np.flatnonzero((indices==6+i)&(a[:,:,3]>0)) for i in range(3)]
  del indices
 pixels=sum(len(offsets) for offsets in positions)
 if not pixels:return
 choices=[]
 for kind in range(4 if screen else 5):
  b=a.copy()
  flat=b.reshape(-1,4)
  for offsets,c in zip(positions,ramps[kind] if screen else combat[kind]):flat[offsets,:3]=rgb(c)
  assert np.array_equal(a[:,:,3],b[:,:,3])
  if np.array_equal(a,b):choices.append(path)
  else:
   filename=f'variant-{index}-{kind}.png';Image.fromarray(b).save(out/filename)
   choices.append('res://assets/classic/knight_selection/'+filename)
  del flat,b
 row=dict(path=path,pixels=pixels,source_sha256=hashlib.sha256(file.read_bytes()).hexdigest(),size=[a.shape[1],a.shape[0]],screen=screen,indexed_class_mask=not screen,original_rgb_matches=original_rgb_matches,blue_class_correction=choices[0]!=path)
 return choices,row

variants={};audit=[]
progress=ImportProgress()
for index,path in enumerate(sorted(paths)):
 progress.update(index+1,len(paths),'Colour sheet')
 result=colour_variants(index,path)
 if result is not None:
  choices,row=result;variants[path]=choices;audit.append(row)
if compact:
 (mask_folder/'manifest.json').write_text(json.dumps({'version':1,'paths':compact_masks},indent=2)+'\n')
 print('Direct layers:',len(compact_masks),'indexed combat masks; no baked combat colour variants',flush=True)
text=f'[gd_resource type="Resource" load_steps={len(refs)+2} format=3]\n[ext_resource type="Script" path="res://scripts/content/knight_art.gd" id="script"]\n'
for path,id in refs.items():text+=f'[ext_resource type="Texture2D" path="{path}" id="{id}"]\n'
text+='[resource]\nscript = ExtResource("script")\n'
for key,value in [('portraits',portraits),('life_icons',life),('tokens',tokens),('active_tokens',active),('frogs',frogs)]:text+=key+' = ['+', '.join(f'ExtResource("{id}")' for id in value)+']\n'
text+=f'highlight = ExtResource("{highlight}")\nfont_atlas = ExtResource("{fontref}")\nglyphs = '+gd(glyphs)+'\nvariants = '+gd(variants)+'\n'
(out/'art.tres').write_text(text)
trace=dict(version=1,retail_sha1=MOG_SHA1,sources=source_hashes,portraits=[2,3,4,5],portrait_x=[12,88,164,240],portrait_y=80,palette=palette,name_max=13,names=[d[a:d.index(0,a)].decode().strip() for a in [96,118,140,162]],home_nodes=[0,1,2,3],solo_start=[15,100],ramp5=ramps,combat_ramps=combat,variant_audit=audit,source='Pinned scene_menu.cpp SceneKnights; rt/screens.cpp colourRamp; engine/display_fx.cpp fighterColors; rt/arena.cpp resetGame.',limits=['Solo human selection only; existing AI ally/three rival turns retained.','Name and confirmed setup persist; cancelled draft is presentation-only.','Combat class registers6..8 are reconstructed from original indexed layers; clean substitutions and occlusion are retained. Screens use reviewed four/five-shade ramps, excluding Math fixed-palette layers. Shared job/palette phase still needs original comparison.','Highlight pulse timing, fades, name editor and mouse/keyboard adaptation are native; original comparison pending.','No source art/executables/runtime decoder/emulation added to exports.'])
trace['fixed_wizard_palette']='WI1.P and Wi1.C cels0..14 are fixed; neither Math nor his robes change with the chosen knight.'
trace['class_masks']='Combat changes are restricted to original registers6..8 through source pose geometry, occlusion and clean substitutions. Same RGB values at other registers are preserved.'
used={Path(p).name for choices in variants.values() for p in choices if '/knight_selection/' in p}
for file in out.glob('variant-*.png'):
 if file.name not in used:
  file.unlink()
  sidecar=Path(str(file)+'.import')
  if sidecar.exists():sidecar.unlink()
(ROOT/'docs/knight-selection-reference.json').write_text(json.dumps(trace,indent=2)+'\n');print('Selection:',len(refs),'native textures;',len(variants),'colour-aware base textures; original portrait/font/map cels')
