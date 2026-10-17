#!/usr/bin/env python3
"""Flatten original knight draws into native, anchored animation atlases.

Runs once on local recovered files. The game receives PNGs and named clips,
never Amiga executable code or a bytecode interpreter. Uses Moonstone ACE's
separate PolyForm Noncommercial hunk-file reader as an import dependency.
"""
from pathlib import Path
import hashlib
import json
import struct
import sys
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "work/upstream/moonstone-ace/tools"))
from hunkfile import parse_hunk_file

# Verified for this retail mog. Other versions must be traced separately.
MOG_SHA1 = "bb38bc0b39f146b30bac959bea717202cf13b965"
ROOTS = {
    "idle": 4196, "walk": [4268, 4288, 4308, 4328],
    "walk_away": [4348, 4362, 4376, 4390],
    "walk_toward": [4404, 4418, 4432, 4446],
    "swing": 4744, "heavy": 4946, "lunge": 5144, "block": 5592,
    "reverse": 4460, "hurt_a": 5788, "hurt_b": 5644, "defeat": 5920,
    "upward": 5374, "dagger": 4594, "defeat_gory": 6040,
}
# These are mappings to the prototype's phases, not original hit timings.
PHASES = {
    "swing": {"windup": [0], "active": [1, 2, 3], "recovery": [4, 5, 6]},
    "heavy": {"windup": [0, 1], "active": [2, 3, 4], "recovery": [5, 6]},
    "lunge": {"windup": [0], "active": [1, 2], "recovery": [3, 4, 5]},
    "reverse": {"windup": [0, 1], "active": [2, 3], "recovery": [4]},
    "upward": {"windup": [0], "active": [1, 2], "recovery": [3]},
    "dagger": {"windup": [0, 1], "active": [2], "recovery": [2]},
}
FAMILIES = ["KN1.ob", "KN2.ob", "KN3.ob", "KN4.ob"]
CELL_W, CELL_H, COLUMNS = 256, 144, 8
ANCHOR_X, ANCHOR_Y = 128, 128


def read_poses(hunk, start):
    """Read only the finite draw/hold subset used by these knight roots.

    Sound/call events are skipped. Stop at the first script end;
    unrelated scripts, branches and unsupported opcodes fail closed.
    """
    data = hunk.data
    position, layers, poses, hold, mirror = start, [], [], 1, False
    loop_start, loop_count = 0, 0
    while position < start + 2048:
        op, arg = data[position:position + 2]
        if op in (0, 4, 8, 12):
            dx = struct.unpack_from(">h", data, position + 4)[0]
            dy = struct.unpack_from(">b", data, position + 2)[0]
            layers.append({"slot": op // 4, "frame": arg, "x": dx,
                           "y": dy - 52, "flags": data[position + 3]})
            position += 6
        elif op == 0x88 and arg > 0:
            hold = arg
            position += 2
        elif op == 0xA4:
            position += 2
        elif op == 0xCC and arg == 0:
            # This retail version has a two-byte CC00 control record that
            # contributes no drawing data. Do not apply the newer upstream
            # interpreter's eight-byte CC format to this exact file.
            position += 2
        elif op == 0x80 and arg == 0xFF:
            mirror = not mirror
            position += 2
        elif op == 0xB4:
            # Nonlethal hurt path. Death is imported from its own explicit root.
            target = struct.unpack_from(">I", data, position + 2)[0]
            expected = {5644: 5920, 5788: 5920, 9054: 9894, 9200: 10030, 9320: 9466,
                        8146: 8764, 8284: 8858, 8400: 8524, 25038: 25122, 20484: 20542}
            if expected.get(start) != target:
                raise ValueError(f"Unexpected death branch at {position}")
            position += 6
        elif op == 0xC4 and start == 20062:
            # This retail idle condition is an eight-byte field test. Both
            # paths draw the same body; native presentation omits its shadow job.
            if position != 20068 or data[position:position+4] != bytes.fromhex("c401000d") or struct.unpack_from(">I", data, position+4)[0] != 20108:
                raise ValueError("Untraced Balok idle condition")
            position += 8
        elif op == 0xAC and start in (20152, 20542):
            expected = {20152: (20152, 1, 20210), 20542: (20544, 0, 0)}
            if (position, arg, struct.unpack_from(">I", data, position+2)[0]) != expected[start]:
                raise ValueError("Untraced Balok shadow job")
            position += 6 # Native ground shadow is rendered independently.
        elif op == 0xC4 and start == 4594:
            # Original throw's no-ammo branch; native ammunition is in the model.
            position += 8
        elif op == 0x98 and start in (6040, 10030, 8858):
            # Bake the gore path. Clean atlases use a separately traced fallback.
            position += 6
        elif op == 0x94 and arg > 0 and start in (9466, 8524):
            loop_start, loop_count = len(poses), arg
            position += 2
        elif op == 0xBC:
            position += 2 # native defeated actors persist independently of original job disposal
        elif op in (0xB0, 0x84):
            # A relocated routine call or deferred return to the idle script.
            targets = [g.target_hunk for g in hunk.reloc32 if position + 2 in g.offsets]
            if len(targets) != 1 or (op == 0x84 and arg != 0):
                raise ValueError(f"Unsupported call at {position}")
            position += 6
        elif op == 0xFF and arg in (0, 0xFE, 0xFF):
            if not layers:
                if arg == 0xFF and poses:
                    return poses
                raise ValueError(f"Empty pose at {position}")
            poses.append({"layers": layers, "hold": hold, "mirror": mirror})
            if arg == 0xFE and loop_count:
                poses.extend(poses[loop_start:].copy() * (loop_count - 1))
                loop_count = 0
            layers, hold = [], 1
            position += 2
            if arg == 0xFF:
                return poses
        else:
            raise ValueError(f"Unsupported knight event {op:02x} at {position}")
    raise ValueError(f"Unterminated clip at {start}")


def gd(value):
    if isinstance(value, dict):
        return "{" + ", ".join(gd(k) + ": " + gd(v) for k, v in value.items()) + "}"
    if isinstance(value, list):
        return "[" + ", ".join(gd(v) for v in value) + "]"
    if isinstance(value, str):
        return json.dumps(value)
    return str(value)


def read_contact_points(name="kn4.ob", expected_count=26):
    lines = (ROOT / "reference/extracted/B/collide.hit").read_text().splitlines()
    starts = [i for i, line in enumerate(lines) if line.lower() == name.lower()]
    if len(starts) != 1:
        raise ValueError("Expected exactly one original sword contact set")
    position, frames = starts[0] + 1, []
    while lines[position] != "99":
        count = int(lines[position]); position += 1
        points = []
        if count:
            kind = int(lines[position]); encoded = lines[position + 1]; position += 2
            if kind != 0 or len(encoded) != count * 6 or not encoded.isdigit():
                raise ValueError("Unsupported sword contact record")
            points = [[int(encoded[i:i + 3]), int(encoded[i + 3:i + 6])]
                      for i in range(0, len(encoded), 6)]
        frames.append(points)
    if len(frames) != expected_count:
        raise ValueError("Sword contact/frame count differs")
    return frames


def main():
    binary = (ROOT / "reference/extracted/A/mog").read_bytes()
    if hashlib.sha1(binary).hexdigest() != MOG_SHA1:
        raise ValueError("Animation offsets require the traced retail mog version")
    hunks = parse_hunk_file(binary).hunks
    hunk = hunks[4]
    roots = {name: offsets if isinstance(offsets, list) else [offsets]
             for name, offsets in ROOTS.items()}
    # Independently verify every root is referenced by the original code.
    referenced = {struct.unpack_from(">I", hunks[0].data, off)[0]
                  for group in hunks[0].reloc32 if group.target_hunk == 4
                  for off in group.offsets}
    poses, clips = [], {}
    for name, offsets in roots.items():
        first = len(poses)
        for offset in offsets:
            if offset not in referenced:
                raise ValueError(f"Unreferenced animation root {offset}")
            poses.extend(read_poses(hunk, offset))
        frames = list(range(first, len(poses)))
        clips[name] = {"frames": frames, "weights": [p["hold"] for p in poses[first:]],
                       "step_ticks": 5 if name.startswith("walk") else 1}
        if name == "defeat":
            # The final original hold is an end-of-battle wait. The native
            # corpse persists indefinitely after the collapse finishes.
            clips[name]["weights"][-1] = 1
        if name == "defeat_gory":
            clips[name]["clean_fallback"] = "defeat"
        if name == "dagger":
            for pose in poses[first:]:
                pose["omit_projectile"] = True
        if name in PHASES:
            clips[name]["phases"] = {phase: [first + n for n in indices]
                                      for phase, indices in PHASES[name].items()}
    destination = ROOT / "game/assets/classic/knight"
    destination.mkdir(parents=True, exist_ok=True)
    rows = (len(poses) + COLUMNS - 1) // COLUMNS
    pose_rects = []
    for index, pose in enumerate(poses):
        pose_rects.append({"region": [index % COLUMNS * CELL_W, index // COLUMNS * CELL_H,
                                      CELL_W, CELL_H], "offset": [-ANCHOR_X, -ANCHOR_Y]})
    source = ROOT / "game/assets/classic/recovered/B"
    # Index 6..8 are the original knight's class colours, not a whole-image tint.
    variants = {"blue": [0x00A, 0x007, 0x004], "purple": [0x206, 0x103, 0x001],
                "blue_clean": [0x00A, 0x007, 0x004], "purple_clean": [0x206, 0x103, 0x001]}
    for variant, colours in variants.items():
        atlas = Image.new("RGBA", (COLUMNS * CELL_W, rows * CELL_H))
        for index, pose in enumerate(poses):
            cell_x, cell_y = index % COLUMNS * CELL_W, index // COLUMNS * CELL_H
            rendered_pose = pose
            gory_frames = clips["defeat_gory"]["frames"]
            if variant.endswith("_clean") and index in gory_frames:
                n = min(3, gory_frames.index(index) * 4 // len(gory_frames))
                rendered_pose = poses[clips["defeat"]["frames"][n]]
            for layer in rendered_pose["layers"]:
                if variant.endswith("_clean") and layer["flags"] & 0x80:
                    continue
                if rendered_pose.get("omit_projectile") and layer["slot"] == 3 and layer["frame"] == 10:
                    continue
                image = Image.open(source / FAMILIES[layer["slot"]] / "frames" /
                                   f'{layer["frame"]:03d}.png')
                if image.mode != "P":
                    raise ValueError("Expected preserved colour indices")
                palette = image.getpalette()
                for entry, colour in enumerate(colours, 6):
                    palette[entry * 3:entry * 3 + 3] = [((colour >> shift) & 15) * 17
                                                       for shift in (8, 4, 0)]
                palette[45:48] = [204, 0, 0]  # original combat palette's blood entry 15
                image.putpalette(palette)
                if variant.endswith("_clean"):
                    alpha = bytearray([255] * 256)
                    alpha[0] = alpha[15] = 0
                    image.info["transparency"] = bytes(alpha)
                image = image.convert("RGBA")
                local_x = layer["x"]
                if rendered_pose["mirror"]:
                    local_x = -local_x - image.width
                    image = image.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
                x, y = ANCHOR_X + local_x, ANCHOR_Y + layer["y"]
                if x < 0 or y < 0 or x + image.width > CELL_W or y + image.height > CELL_H:
                    raise ValueError("Pose exceeds its anchored atlas cell")
                atlas.alpha_composite(image, (cell_x + x, cell_y + y))
        atlas.save(destination / f"{variant}.png")
    resource = '''[gd_resource type="Resource" script_class="MoonstoneAnimationSet" load_steps=6 format=3]

[ext_resource type="Script" path="res://scripts/content/animation_set.gd" id="1"]
[ext_resource type="Texture2D" path="res://assets/classic/knight/blue.png" id="2"]
[ext_resource type="Texture2D" path="res://assets/classic/knight/purple.png" id="3"]
[ext_resource type="Texture2D" path="res://assets/classic/knight/blue_clean.png" id="4"]
[ext_resource type="Texture2D" path="res://assets/classic/knight/purple_clean.png" id="5"]

[resource]
script = ExtResource("1")
atlases = {"blue": ExtResource("2"), "purple": ExtResource("3"), "blue_clean": ExtResource("4"), "purple_clean": ExtResource("5")}
default_variant = "blue"
'''
    resource += "poses = [\n" + ",\n".join(
        '{"region": Rect2(%s), "offset": Vector2(%s)}' %
        (", ".join(map(str, pose["region"])), ", ".join(map(str, pose["offset"])))
        for pose in pose_rects) + "\n]\nclips = " + gd(clips) + "\n"
    (destination / "animations.tres").write_text(resource)
    contact_frames = read_contact_points()
    attacks = {}
    for name in PHASES:
        attacks[name] = []
        for index in clips[name]["phases"]["active"]:
            pose = poses[index]
            points = []
            for layer in pose["layers"]:
                if layer["slot"] == 3 and layer["flags"] & 2:
                    points.extend([[layer["x"] + x, layer["y"] + y]
                                   for x, y in contact_frames[layer["frame"]]])
            attacks[name].append({"points": points, "weight": pose["hold"]})
    geometry_path = ROOT / "game/content/generated"
    geometry_path.mkdir(parents=True, exist_ok=True)
    geometry = '''[gd_resource type="Resource" script_class="MoonstoneCombatGeometry" load_steps=2 format=3]
[ext_resource type="Script" path="res://scripts/content/combat_geometry.gd" id="1"]
[resource]
script = ExtResource("1")
attacks = ''' + gd(attacks) + "\n"
    (geometry_path / "classic_collision.tres").write_text(geometry)
    (destination / "provenance.json").write_text(json.dumps({
        "mog_sha1": MOG_SHA1, "hunk": 4, "roots": ROOTS, "poses": poses,
        "clips": clips, "contact_geometry": attacks,
        "anchor_note": "Original job y + 52 is the standing foot baseline",
        "timing_note": "Original holds retained as weights; phase mapping and walking speed provisional",
        "palette_note": "Original class triplets and blood entry 15; other entries retain preview palette"
    }, indent=2) + "\n")
    print(f"Imported {len(poses)} anchored knight poses in {len(clips)} named clips")


if __name__ == "__main__":
    main()
