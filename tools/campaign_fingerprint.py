#!/usr/bin/env python3
"""Fingerprint the shared campaign authority, policies and numeric dependency closure."""
from pathlib import Path
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = 'content/campaign_compatibility.json'
ROOTS = ['scripts/session/campaign_session.gd', 'scripts/session/campaign_projection.gd',
         'scripts/session/campaign_protocol.gd', 'scripts/session/campaign_host.gd',
         'scripts/session/campaign_connection.gd', 'scripts/session/campaign_store.gd']


def manifest(game):
    todo, files = list(ROOTS), {}
    while todo:
        name = todo.pop()
        if name == MANIFEST or name == 'content/network_compatibility.json' or name in files:continue
        path = game / name
        if path.suffix not in {'.gd', '.tres', '.json'}:continue
        if name.startswith(('assets/', 'content/generated/')) or '..' in Path(name).parts:
            raise ValueError('Campaign server needs curated source gameplay content: ' + name)
        data = path.read_bytes()
        files[name] = hashlib.sha256(data).hexdigest()
        todo.extend(re.findall(r'res://([^"\s]+\.(?:gd|tres|json))', data.decode()))
    files = dict(sorted(files.items()))
    material = 'moonstone-campaign:1:godot4.6.1:50hz\n' + ''.join(f'{name}:{value}\n' for name, value in files.items())
    return {'protocol': 1, 'digest': hashlib.sha256(material.encode()).hexdigest(), 'files': files}


if __name__ == '__main__':
    result = manifest(ROOT / 'game')
    (ROOT / 'game' / MANIFEST).write_text(json.dumps(result, indent=2) + '\n')
    print(f"Campaign compatibility: {len(result['files'])} source gameplay resources.")
