#!/usr/bin/env python3
"""Fingerprint the static combat-code/rules dependency closure, excluding pixels/audio."""
from pathlib import Path
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[1]
ROOTS = ("scripts/domain/combat_simulation.gd", "content/foundation_rules.tres", "scripts/session/network_duel_session.gd", "scripts/session/duel_protocol.gd", "scripts/session/duel_replica.gd", "scripts/session/duel_connection.gd")
MANIFEST = "content/network_compatibility.json"


def manifest(game):
    todo, files = list(ROOTS), {}
    while todo:
        name = todo.pop()
        if name == MANIFEST or name in files:
            continue
        path = game / name
        if path.suffix not in {".gd", ".tres", ".json"}:
            continue
        data = path.read_bytes()
        files[name] = hashlib.sha256(data).hexdigest()
        todo.extend(re.findall(r'res://([^"\s]+\.(?:gd|tres|json))', data.decode()))
    files = dict(sorted(files.items()))
    material = "moonstone-duel:1:godot4.6.1:50hz\n" + "".join(f"{name}:{value}\n" for name, value in files.items())
    return {"protocol": 1, "digest": hashlib.sha256(material.encode()).hexdigest(), "files": files}


def main():
    result = manifest(ROOT / "game")
    (ROOT / "game" / MANIFEST).write_text(json.dumps(result, indent=2) + "\n")
    print(f"Network compatibility: {len(result['files'])} combat code/rule resources.")


if __name__ == "__main__":
    main()
