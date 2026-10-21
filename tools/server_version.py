"""Server release identity is independent of game identity and wire compatibility."""
from pathlib import Path
import json
import re

TAG_PREFIX = 'server-v'
VERSION_FILE = 'game/server/version.json'
NUMBER = r'(?:0|[1-9][0-9]*)'
VERSION = re.compile(rf'{NUMBER}\.{NUMBER}\.{NUMBER}(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?')


def validate_version(value):
    match = VERSION.fullmatch(value) if isinstance(value, str) else None
    if not match or (match.group(1) and any(part.isdigit() and len(part) > 1 and part.startswith('0') for part in match.group(1).split('.'))):
        raise ValueError('Expected a server version such as 0.1.0 or 0.1.0-rc.1.')
    return value


def server_version(root):
    return validate_version(json.loads((Path(root) / VERSION_FILE).read_text())['version'])


def validate_tag(tag, root):
    expected = TAG_PREFIX + server_version(root)
    if tag != expected:
        raise ValueError('Server release tag must match ' + VERSION_FILE + ': ' + expected)
    return expected
