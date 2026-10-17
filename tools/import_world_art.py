#!/usr/bin/env python3
"""Bake local map icons using the original map's colour registers, once at import."""
from pathlib import Path
import hashlib
import json
import re
import struct
from PIL import Image
from import_knight_animations import MOG_SHA1, parse_hunk_file, gd

ROOT = Path(__file__).resolve().parents[1]


def main():
    recovered = ROOT / "game/assets/classic/recovered/B"
    source = ROOT / "reference/extracted/B/test"
    metadata = json.loads((recovered / "test/sidecar.json").read_text())
    assert hashlib.sha1(source.read_bytes()).hexdigest() == metadata["source_sha1"]
    icons = json.loads((recovered / "mi.c/sidecar.json").read_text())
    assert hashlib.sha1((ROOT / "reference/extracted/B/mi.c").read_bytes()).hexdigest() == icons["source_sha1"]
    colours = metadata["records"][8]["palette_rgb12"]
    palette = [((colour >> shift) & 15) * 17 for colour in colours for shift in (8, 4, 0)]
    palette += [0] * (768 - len(palette))
    out = ROOT / "game/assets/classic/world"
    out.mkdir(parents=True, exist_ok=True)
    for name, frame in [("knight", 0), ("knight_active",5), ("lair", 20)]:
        image = Image.open(recovered / f"mi.c/frames/{frame:03d}.png")
        image.putpalette(palette)
        image.info["transparency"] = 0
        image.convert("RGBA").save(out / f"{name}.png")
    mog = (ROOT / "reference/extracted/A/mog").read_bytes()
    assert hashlib.sha1(mog).hexdigest() == MOG_SHA1
    hunks = parse_hunk_file(mog).hunks
    data = hunks[4]
    relocated = {o for group in data.reloc32 if group.target_hunk == 4 for o in group.offsets}
    roots = struct.unpack_from(">16I", data.data, 31594)
    assert all(31594+4*i in relocated for i in range(16))
    assert list(roots) == [31658+8*(i//2) for i in range(16)]
    dragon_offsets = []
    for i,root in enumerate(roots[::2]):
        op,frame,y,flags,x,term = struct.unpack_from(">BBbBhH",data.data,root)
        assert op==0 and frame==34+i and flags==0 and x==-17 and term==0xffff
        image = Image.open(recovered / f"mi.c/frames/{frame:03d}.png")
        image.putpalette(palette); image.info["transparency"]=0
        image.convert("RGBA").save(out / f"dragon_{i}.png")
        dragon_offsets.append([x,y])
    # Independent retail guard for the spawn counter and both flight speeds.
    assert hunks[36].data[1454:1458] == bytes.fromhex("0c790002")
    assert struct.unpack_from(">hh",hunks[36].data,2050)==(2,1)
    moon_folder=ROOT / "game/assets/classic/recovered/B/ki.cel"
    moon_meta=json.loads((moon_folder / "sidecar.json").read_text())
    assert hashlib.sha1((ROOT / "reference/extracted/B/ki.cel").read_bytes()).hexdigest()==moon_meta["source_sha1"]
    assert data.data[239:247] == bytes([45,46,47,48,49,48,47,46])
    # The lunar clock uses the inventory/UI cel set, not the map icon set.
    ui_colours=struct.unpack_from(">32H",hunks[4].data,39160)
    ui_palette=[((colour>>shift)&15)*17 for colour in ui_colours for shift in (8,4,0)]+[0]*672
    for i in range(5):
        image=Image.open(moon_folder / f"frames/{45+i:03d}.png")
        assert image.size==(57,44)
        image.putpalette(ui_palette);image.info["transparency"]=0
        image.convert("RGBA").save(out / f"moon_{i}.png")
    town_sources = {}
    for name in ["HighWood.PIV", "WaterDeep.PIV"]:
        town_meta = json.loads((ROOT / "game/assets/classic/recovered/C" / name / "sidecar.json").read_text())
        assert hashlib.sha1((ROOT / "reference/extracted/C" / name).read_bytes()).hexdigest() == town_meta["source_sha1"]
        town_sources[name] = town_meta["source_sha1"]
    # Decode the immediate rectangle writes in this exact retail binary, offline.
    # The menu lettering and parchment are already part of each complete picture.
    mog = (ROOT / "reference/extracted/A/mog").read_bytes()
    assert hashlib.sha1(mog).hexdigest() == MOG_SHA1
    code = parse_hunk_file(mog).hunks[0].data
    layouts = {}
    for name,offset,x,ys,fourth_height,fourth in [
        ("highwood",5336,256,[30,66,106,140,183],26,"temple"),
        ("waterdeep",5530,0,[26,63,101,134,182],31,"mystic")]:
        assert code[offset:offset+6] == struct.pack(">HHH",0x317c,x,12)
        end = code.index(b"\x4e\x75",offset)+2
        block = code[offset:end]
        assert 150 < len(block) < 220
        values = lambda field: [struct.unpack(">H",m.group(1))[0] for m in re.finditer(re.escape(b"\x31\x7c")+b"(..)"+re.escape(struct.pack(">H",field)),block,re.DOTALL)]
        assert values(14) == ys and values(4) == [64,64]
        assert values(6) == [16,fourth_height,12]
        layouts[name] = {"entries":["smith","tavern","healer",fourth,"leave"],
                         "rectangles":[[x,y,64,[16,16,16,fourth_height,12][i]] for i,y in enumerate(ys)]}
    pictures = {"healer":"hea.piv","mystic":"mys.piv","tavern":"tav.piv","dice":"dice.piv"}
    service_sources = {}
    sprites = {}
    for service,filename in pictures.items():
        folder = ROOT / "game/assets/classic/recovered/C" / filename
        meta = json.loads((folder / "sidecar.json").read_text())
        assert hashlib.sha1((ROOT / "reference/extracted/C" / filename).read_bytes()).hexdigest() == meta["source_sha1"]
        service_sources[filename] = meta["source_sha1"]
        if service == "tavern":
            ramp = bytes.fromhex("30fc005d30fc003b30fc002830fc001630bc0003")
            assert code.count(ramp) == 1 and code.index(ramp) == 43464
            colours = meta["palette_rgb12"].copy()
            colours[6:11] = [struct.unpack_from(">H",ramp,i*4+2)[0] for i in range(5)]
            pal = [((colour>>shift)&15)*17 for colour in colours for shift in (8,4,0)]
            pal += [0]*(768-len(pal))
            image = Image.open(folder / "image.png")
            image.putpalette(pal)
            image.convert("RGB").save(out / "tavern-blue.png")
            continue
        cel = "dice.cel" if service == "dice" else "mys.cel"
        cel_folder = ROOT / "game/assets/classic/recovered/C" / cel
        cel_meta = json.loads((cel_folder / "sidecar.json").read_text())
        assert hashlib.sha1((ROOT / "reference/extracted/C" / cel).read_bytes()).hexdigest() == cel_meta["source_sha1"]
        service_sources[cel] = cel_meta["source_sha1"]
        pal = [((colour>>shift)&15)*17 for colour in meta["palette_rgb12"] for shift in (8,4,0)]
        pal += [0]*(768-len(pal))
        for frame in range(6 if service == "dice" else 8):
            image = Image.open(cel_folder / f"frames/{frame:03d}.png")
            image.putpalette(pal); image.info["transparency"] = 0
            key = f"{service}_{frame}"
            image.convert("RGBA").save(out / (key+".png"))
            sprites[key] = f"res://assets/classic/world/{key}.png"
    data = parse_hunk_file(mog).hunks[4]
    relocated = {o for group in data.reloc32 if group.target_hunk == 4 for o in group.offsets}
    dialogue = {}
    for name,start in [("healer",34720),("mystic",35214)]:
        rows = []; pointer = start
        for _ in range(8):
            assert pointer in relocated
            text,x,y,style,next_record = struct.unpack_from(">IHHHI",data.data,pointer)
            assert x == 0 and style == 1 and 160 <= y <= 190
            end = data.data.index(0,text)
            rows.append({"text":data.data[text:end].decode("ascii"),"y":y})
            if not next_record: break
            assert pointer+10 in relocated
            pointer = next_record
        else: raise ValueError("Unterminated service greeting")
        dialogue[name] = rows
    resource = '''[gd_resource type="Resource" script_class="MoonstoneWorldArt" load_steps=7 format=3]
[ext_resource type="Script" path="res://scripts/content/world_art.gd" id="1"]
[ext_resource type="Texture2D" path="res://assets/classic/recovered/B/test/08/image.png" id="2"]
[ext_resource type="Texture2D" path="res://assets/classic/world/knight.png" id="3"]
[ext_resource type="Texture2D" path="res://assets/classic/world/lair.png" id="4"]
[ext_resource type="Texture2D" path="res://assets/classic/recovered/C/HighWood.PIV/image.png" id="5"]
[ext_resource type="Texture2D" path="res://assets/classic/recovered/C/WaterDeep.PIV/image.png" id="6"]
[resource]
script = ExtResource("1")
background = ExtResource("2")
knight = ExtResource("3")
lair = ExtResource("4")
highwood = ExtResource("5")
waterdeep = ExtResource("6")
''' + "town_layouts = " + gd(layouts) + "\n"
    extra = {}
    for name,filename in pictures.items():
        extra["picture_"+name] = "res://assets/classic/world/tavern-blue.png" if name == "tavern" else "res://assets/classic/recovered/C/"+filename+"/image.png"
    extra.update(sprites)
    extra.update({f"moon_{i}":f"res://assets/classic/world/moon_{i}.png" for i in range(5)})
    extra["knight_active"]="res://assets/classic/world/knight_active.png"
    extra.update({f"dragon_{i}":f"res://assets/classic/world/dragon_{i}.png" for i in range(8)})
    declarations = "".join(f'[ext_resource type="Texture2D" path="{path}" id="{key}"]\n' for key,path in extra.items())
    resource = resource.replace("load_steps=7",f"load_steps={7+len(extra)}").replace("[resource]",declarations+"[resource]")
    resource += 'service_pictures = {'+', '.join(f'"{name}": ExtResource("picture_{name}")' for name in pictures)+'}\n'
    resource += 'service_sprites = {'+', '.join(f'"{name}": ExtResource("{name}")' for name in sprites)+'}\n'
    resource += 'service_dialogue = '+gd(dialogue)+'\n'
    resource += 'dragon_frames = Array[Texture2D](['+', '.join(f'ExtResource("dragon_{i}")' for i in range(8))+'])\n'
    resource += 'knight_active = ExtResource("knight_active")\n'
    resource += 'moon_frames = Array[Texture2D](['+', '.join(f'ExtResource("moon_{i}")' for i in [0,1,2,3,4,3,2,1])+'])\n'
    resource += 'dragon_offsets = Array[Vector2i](['+', '.join(f'Vector2i({x}, {y})' for x,y in dragon_offsets)+'])\n'
    (out / "art.tres").write_text(resource)
    (out / "provenance.json").write_text(json.dumps({
        "backdrop": "B/test, picture index 8 (original pack picture 9)",
        "source_sha1": metadata["source_sha1"],
        "icon_source_sha1": icons["source_sha1"],
        "icons": {"knight": "B/mi.c frame 0", "lair": "B/mi.c frame 20"},
        "palette": "map picture colour registers; transparent index 0",
        "map_clock_art":{"active_knight_frame":5,"moon_frames":[45,46,47,48,49,48,47,46],"source":"retail hunk4:239 moon cycle; B/ki.cel frames45..49, inventory palette hunk4:39160","moon_source_sha1":moon_meta["source_sha1"]},
        "map_dragon":{"frames":list(range(34,42)),"offsets":dragon_offsets,"table":{"hunk":4,"offset":31594},"spawn_counter":{"hunk":36,"offset":1454,"value":2},"speed":{"hunk":36,"offset":2050,"value":[2,1]},"glide_frame":37,"phase_holds":2},
        "town_sources": town_sources,
        "town_layouts": layouts,
        "service_sources":service_sources,"greeting_roots":{"hunk":4,"healer":34720,"mystic":35214},
        "tavern_knight_ramp":{"hunk":0,"offset":43464,"registers":"6..10","rgb12":[0x05d,0x03b,0x028,0x016,0x003]},
        "town_layout_source": {"sha1":MOG_SHA1,"hunk":0,"highwood":5336,"waterdeep":5530,
                               "method":"verified MOVE.W immediate rectangle writes through RTS; no runtime interpreter"},
        "layout": "Complete original town pictures include parchment and lettering; native hit regions use recovered logical coordinates doubled once"
    }, indent=2) + "\n")
    print("Imported original map backdrop and map-palette knight/lair icons")


if __name__ == "__main__":
    main()
