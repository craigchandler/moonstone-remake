#!/usr/bin/env python3
"""Bake the verified retail axe Trogg's finite scripts into native content."""
from pathlib import Path
import hashlib
import json
import struct
from PIL import Image
from import_knight_animations import ROOT, MOG_SHA1, read_poses, read_contact_points, gd, parse_hunk_file

ROOTS = {
    "idle": [7646], "walk": [7986,8000,8014],
    "walk_away": [8034,8048,8062,8076], "walk_toward": [8090,8104,8118,8132],
    "axe_swing": [7666], "axe_chop": [7790],
    "hurt_a": [8146], "hurt_b": [8284], "hurt_c": [8400],
    "defeat": [8764], "defeat_split": [8858], "defeat_guts": [8524],
}
PHASES = {
    "axe_swing": {"windup":[0],"active":[1,2,3],"recovery":[4]},
    "axe_chop": {"windup":[0,1,2],"active":[3,4],"recovery":[5,6]},
}
CELL_W, CELL_H, COLUMNS = 384, 176, 8
AX, AY = 128, 128


def main():
    binary = (ROOT / "reference/extracted/A/mog").read_bytes()
    if hashlib.sha1(binary).hexdigest() != MOG_SHA1:
        raise ValueError("Untraced original binary")
    hunks = parse_hunk_file(binary).hunks
    refs = {struct.unpack_from(">I", h.data, off)[0]
            for h in [hunks[0], hunks[4]] for g in h.reloc32 if g.target_hunk == 4
            for off in g.offsets}
    poses, clips = [], {}
    for name, offsets in ROOTS.items():
        first = len(poses)
        for offset in offsets:
            if offset not in refs:
                raise ValueError(f"Unreferenced root {offset}")
            poses.extend(read_poses(hunks[4], offset))
        clips[name] = {"frames": list(range(first, len(poses))),
                       "weights": [p["hold"] for p in poses[first:]],
                       "step_ticks": 6 if name.startswith("walk") else 1}
        if name in PHASES:
            clips[name]["phases"] = {phase:[first+i for i in frames] for phase,frames in PHASES[name].items()}
        if name.startswith("defeat_"):
            clips[name]["clean_fallback"] = "defeat"
    clips["attack_return"]={"frames":[clips["axe_chop"]["frames"][-1]],"weights":[1],"step_ticks":1}
    out = ROOT / "game/assets/classic/trogg_axe"
    out.mkdir(parents=True, exist_ok=True)
    source = ROOT / "game/assets/classic/recovered/B"
    families = ["TROGGAxe1.CEL", "TROGGAxe2.CEL"]
    colours = [0x104, 0x102, 0x000, 0x600, 0x300, 0x693, 0xC00] # original region-0 cave row
    for clean in [False, True]:
        atlas = Image.new("RGBA", (COLUMNS * CELL_W, ((len(poses) + COLUMNS - 1) // COLUMNS) * CELL_H))
        for index, pose in enumerate(poses):
            rendered = pose
            if clean:
                for name in ["defeat_split", "defeat_guts"]:
                    frames = clips[name]["frames"]
                    if index in frames:
                        fallback = clips["defeat"]["frames"]
                        rendered = poses[fallback[min(len(fallback)-1, frames.index(index)*len(fallback)//len(frames))]]
            for layer in rendered["layers"]:
                if clean and layer["flags"] & 0x80:
                    continue
                image = Image.open(source / families[layer["slot"]] / "frames" / f'{layer["frame"]:03d}.png')
                palette = image.getpalette()
                for entry, colour in enumerate(colours, 9):
                    palette[entry*3:entry*3+3] = [((colour >> shift) & 15)*17 for shift in (8,4,0)]
                for entry, colour in enumerate([0x00A,0x007,0x004],6):
                    palette[entry*3:entry*3+3] = [((colour >> shift) & 15)*17 for shift in (8,4,0)]
                image.putpalette(palette)
                if clean:
                    alpha = bytearray([255]*256); alpha[0] = alpha[15] = 0
                    image.info["transparency"] = bytes(alpha)
                image = image.convert("RGBA")
                x, y = AX + layer["x"], AY + layer["y"]
                if x<0 or y<0 or x+image.width>CELL_W or y+image.height>CELL_H:
                    raise ValueError((index,layer,"atlas bounds"))
                atlas.alpha_composite(image, (index%COLUMNS*CELL_W+x,index//COLUMNS*CELL_H+y))
        atlas.save(out / ("clean.png" if clean else "gore.png"))
    resource = '''[gd_resource type="Resource" script_class="MoonstoneAnimationSet" load_steps=4 format=3]
[ext_resource type="Script" path="res://scripts/content/animation_set.gd" id="1"]
[ext_resource type="Texture2D" path="res://assets/classic/trogg_axe/gore.png" id="2"]
[ext_resource type="Texture2D" path="res://assets/classic/trogg_axe/clean.png" id="3"]
[resource]
script = ExtResource("1")
default_variant = "purple"
atlases = {"purple": ExtResource("2"), "blue": ExtResource("2"), "purple_clean": ExtResource("3"), "blue_clean": ExtResource("3")}
poses = [
'''
    resource += ",\n".join('{"region": Rect2(%d, %d, %d, %d), "offset": Vector2(%d, %d)}' %
                            (i%COLUMNS*CELL_W,i//COLUMNS*CELL_H,CELL_W,CELL_H,-AX,-AY) for i in range(len(poses)))
    resource += "\n]\nclips = " + gd(clips) + "\n"
    (out/"animations.tres").write_text(resource)
    contact_frames = read_contact_points("TroggAxe2.cel",79)
    attacks = {}
    for name in PHASES:
        attacks[name] = []
        for pose_index in clips[name]["phases"]["active"]:
            pose = poses[pose_index]
            points = []
            for layer in pose["layers"]:
                if layer["flags"] & 2:
                    points.extend([[layer["x"]+x,layer["y"]+y] for x,y in contact_frames[layer["frame"]]])
            if not points: raise ValueError((name,pose_index,"missing axe contacts"))
            attacks[name].append({"points":points,"weight":pose["hold"]})
    (ROOT/"game/content/generated/axe_collision.tres").write_text('''[gd_resource type="Resource" script_class="MoonstoneCombatGeometry" load_steps=2 format=3]
[ext_resource type="Script" path="res://scripts/content/combat_geometry.gd" id="1"]
[resource]
script = ExtResource("1")
attacks = ''' + gd(attacks)+"\n")
    (out/"provenance.json").write_text(json.dumps({"mog_sha1":MOG_SHA1,"roots":ROOTS,"poses":poses,"clips":clips,"contacts":attacks,"timing":"Provisional native timing; original frame holds preserved"},indent=2)+"\n")
    print(f"Imported axe Trogg: {len(poses)} poses, {len(clips)} clips")


if __name__ == "__main__":
    main()
