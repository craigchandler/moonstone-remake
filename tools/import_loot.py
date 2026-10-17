#!/usr/bin/env python3
"""Recover retail reward tables and palette, and bake native inventory-screen artwork."""
from pathlib import Path
import hashlib
import json
import struct
from PIL import Image
from import_knight_animations import ROOT, MOG_SHA1, parse_hunk_file, gd

ITEMS = [
    (0, "healing_potion", "Potion of Healing", 4),
    (2, "gem_of_seeing", "Gem of Seeing", 9),
    (4, "sword_of_sharpness", "Sword of Sharpness", 25),
    (6, "ring_of_protection", "Ring of Protection", 3),
    (8, "talisman_of_the_wyrm", "Talisman of the Wyrm", 10),
    (10, "scroll_of_haste", "Scroll of Haste", 11),
    (12, "scroll_of_acquisition", "Scroll of Acquisition", 12),
    (14, "scroll_of_the_hawk", "Scroll of the Hawk", 13),
    (16, "scroll_of_the_wyrm", "Scroll of the Wyrm", 14),
    (18, "scroll_of_protection", "Scroll of Protection", 15),
]
# Original panel draw-list coordinates; no original executable/interpreter is shipped.
PANELS = [(26,296,83,0),(34,154,23,0),(35,181,29,0),(36,181,10,0),
          (34,288,23,1),(35,273,29,1),(36,235,10,1),(26,0,83,0),
          (26,148,83,0),(34,6,23,0),(35,33,29,0),(36,33,10,0),
          (34,140,23,1),(35,125,29,1),(36,87,10,1)]


def main():
    source = (ROOT / "reference/extracted/A/mog").read_bytes()
    assert hashlib.sha1(source).hexdigest() == MOG_SHA1
    hunks = parse_hunk_file(source).hunks
    data = hunks[4].data
    references = {struct.unpack_from(">I", h.data, offset)[0]
                  for h in hunks for group in h.reloc32 if group.target_hunk == 4
                  for offset in group.offsets}
    # Verify actual retail tables and relocation references, rather than borrowing facts offsets.
    lair_offset = 28352
    bands = list(struct.iter_unpack(">HH", data[lair_offset:lair_offset+16]))
    assert bands == [(50,1),(70,2),(90,3),(100,4)] and lair_offset in references
    item_offset = 31852
    item_bands = list(struct.iter_unpack(">II", data[item_offset:item_offset+80]))
    assert item_bands == [(25,0),(35,2),(45,4),(55,6),(65,8),(75,10),(80,14),(85,12),(94,16),(100,18)]
    assert item_offset in references
    palette_offset = 39160
    colours = list(struct.unpack_from(">32H", data, palette_offset))
    assert palette_offset in references and len(data) == palette_offset+64
    assert colours[:4] == [0,0xfff,0xccc,0xaaa] and all(c <= 0xfff for c in colours)
    palette = [((c >> shift)&15)*17 for c in colours for shift in (8,4,0)] + [0]*672
    recovered = ROOT / "game/assets/classic/recovered/B/ki.cel"
    meta = json.loads((recovered / "sidecar.json").read_text())
    assert hashlib.sha1((ROOT / "reference/extracted/B/ki.cel").read_bytes()).hexdigest() == meta["source_sha1"]
    out = ROOT / "game/assets/classic/loot"
    out.mkdir(parents=True,exist_ok=True)
    frames = []
    for index in range(meta["frame_count"]):
        image = Image.open(recovered / f"frames/{index:03d}.png")
        image.putpalette(palette)
        image.info["transparency"] = 0
        frames.append(image.convert("RGBA"))
    background = Image.new("RGBA",(320,200),(0,0,0,255))
    for frame,x,y,mirror in PANELS:
        image = frames[frame]
        if mirror: image = image.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        background.alpha_composite(image,(x,y))
    background.save(out / "panels.png")
    single = Image.new("RGBA", (320,200), (0,0,0,255))
    for frame,x,y,mirror in PANELS[7:]:
        image = frames[frame]
        if mirror: image = image.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        single.alpha_composite(image,(x+74,y))
    single.save(out / "single.png")
    for frame,x,y in [(31,208,46),(32,226,33),(33,208,60)]:
        background.alpha_composite(frames[frame], (x,y))
    background.save(out / "background.png")
    icons = {item_id: frame for slot,item_id,name,frame in ITEMS}
    icons.update({"moonstone_full":2,"moonstone_new":1,"moonstone_half_a":0,"moonstone_half_b":0,
                  "gold":37,"knight":17,"dagger":21,
                  "long_sword":22,"broad_sword":23,"claymore":24,
                  "padded_armour":27,"chainmail":28,"platemail":29,"battleplate":30,
                  "strength":38,"constitution":39,"endurance":40,
                  "xp_label":41,"gold_label":42,"hit_label":43,
                  "key_moors":5,"key_wetlands":6,"key_wastes":7,"key_forest":8,
                  "scroll_back":16})
    for item_id,frame in icons.items(): frames[frame].save(out / f"{item_id}.png")
    # screenPalette's Knight0 override at UI registers28..29 (LAB_04E1).
    helmet = Image.open(recovered / "frames/017.png")
    helmet_palette = palette.copy()
    for index,colour in [(28,0x03f),(29,0x028)]:
        helmet_palette[index*3:index*3+3] = [((colour>>shift)&15)*17 for shift in (8,4,0)]
    helmet.putpalette(helmet_palette); helmet.info["transparency"] = 0
    helmet.convert("RGBA").save(out / "knight.png")
    # Hardware sprite picture and compact font are ordinary native textures after import.
    cursor_source = ROOT / "game/assets/classic/recovered/B/po.cel"
    cursor_meta = json.loads((cursor_source / "sidecar.json").read_text())
    assert hashlib.sha1((ROOT / "reference/extracted/B/po.cel").read_bytes()).hexdigest() == cursor_meta["source_sha1"]
    cursor = Image.open(cursor_source / "frames/000.png")
    cursor.putpalette(palette); cursor.info["transparency"] = 0
    cursor.convert("RGBA").save(out / "cursor.png")
    font_source = ROOT / "game/assets/classic/recovered/B/Small.font"
    font_meta = json.loads((font_source / "sidecar.json").read_text())
    assert hashlib.sha1((ROOT / "reference/extracted/B/Small.font").read_bytes()).hexdigest() == font_meta["source_sha1"]
    char_offset = 29112
    char_map = data[char_offset:char_offset+224]
    assert char_offset in references and list(char_map[:16]) == [69,62,69,66,67,68,69,70,69,69,69,69,65,69,64,71]
    atlas = Image.new("RGBA", (128,72))
    glyphs = {}
    for code in range(32,127):
        index = char_map[code-32]
        assert index < font_meta["frame_count"]
        im = Image.open(font_source / f"frames/{index:03d}.png")
        im.putpalette([0,0,0,255,255,255]+[0]*762); im.info["transparency"] = 0
        x,y = index%16*8,index//16*12
        atlas.alpha_composite(im.convert("RGBA"),(x,y))
        glyphs[chr(code)] = [x,y,im.width,im.height]
    atlas.save(out / "font.png")
    resource = '[gd_resource type="Resource" script_class="MoonstoneLootArt" load_steps=%d format=3]\n' % (len(icons)+7)
    resource += '[ext_resource type="Script" path="res://scripts/content/loot_art.gd" id="1"]\n'
    resource += '[ext_resource type="Texture2D" path="res://assets/classic/loot/background.png" id="2"]\n'
    resource += '[ext_resource type="Texture2D" path="res://assets/classic/loot/panels.png" id="3"]\n'
    resource += '[ext_resource type="Texture2D" path="res://assets/classic/loot/single.png" id="single"]\n'
    resource += '[ext_resource type="Texture2D" path="res://assets/classic/loot/font.png" id="font"]\n'
    resource += '[ext_resource type="Texture2D" path="res://assets/classic/loot/cursor.png" id="cursor"]\n'
    for index,item_id in enumerate(icons,4):
        resource += f'[ext_resource type="Texture2D" path="res://assets/classic/loot/{item_id}.png" id="{index}"]\n'
    resource += '\n[resource]\nscript = ExtResource("1")\nbackground = ExtResource("2")\npanel_background = ExtResource("3")\nicons = {'
    resource += ', '.join(f'"{item_id}": ExtResource("{index}")' for index,item_id in enumerate(icons,4))+'}\n'
    resource += 'single_background = ExtResource("single")\npixel_font = ExtResource("font")\nsword_cursor = ExtResource("cursor")\nglyphs = '+gd(glyphs)+'\n'
    (out / "art.tres").write_text(resource)
    by_slot = {slot:item_id for slot,item_id,name,frame in ITEMS}
    catalog = {item_id:{"name":name,"slot":slot} for slot,item_id,name,frame in ITEMS}
    generated = ROOT / "game/content/generated/classic_loot.tres"
    generated.write_text('''[gd_resource type="Resource" script_class="MoonstoneLootRules" load_steps=2 format=3]
[ext_resource type="Script" path="res://scripts/content/loot_rules.gd" id="1"]
[resource]
script = ExtResource("1")
''' + 'lair_bands = '+gd([list(row) for row in bands])+'\nitem_bands = '+gd([[limit,slot,by_slot[slot]] for limit,slot in item_bands])+'\nitems = '+gd(catalog)+'\n')
    (out / "provenance.json").write_text(json.dumps({"mog_sha1":MOG_SHA1,"hunk":4,
        "lair_bands_offset":lair_offset,"item_bands_offset":item_offset,"palette_offset":palette_offset,
        "lair_bands":bands,"item_bands":item_bands,"palette":colours,"ki_source_sha1":meta["source_sha1"],
        "icon_frames":icons,"panel_draws":PANELS,
        "single_panel_shift":74,"font_sha1":font_meta["source_sha1"],"char_map_offset":char_offset,
        "cursor_sha1":cursor_meta["source_sha1"],"cursor_palette":"inventory white/grey registers 1..3; hardware colour comparison pending",
        "knight_palette_override":{"28":0x03f,"29":0x028,"reference":"screenPalette LAB_04E1 Knight0"},
        "limits":"Native independent loot seed; no full original campaign RNG order, item effects or saves"},indent=2)+'\n')
    print("Imported retail loot bands, panels, item/key icons, compact font and sword cursor")


if __name__ == "__main__":
    main()
