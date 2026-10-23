"""Build a code-only PCK directly from public source, never a provisioned export."""
from pathlib import Path
import json
import re
from portmaster_content import write_pack, MEDIA_ROOTS
from network_fingerprint import manifest, MANIFEST
from campaign_fingerprint import manifest as campaign_manifest, MANIFEST as CAMPAIGN_MANIFEST

SOURCE_SUFFIXES = {'.gd', '.gdshader', '.uid', '.tscn', '.tres', '.json'}


def source_files(root):
    game = root / 'game'
    files = {}
    for folder in ['scripts', 'scenes', 'content', 'debug', 'tests', 'server']:
        for path in (game / folder).rglob('*'):
            if not path.is_file() or path.suffix not in SOURCE_SUFFIXES:continue
            name = path.relative_to(game).as_posix()
            if name.startswith(MEDIA_ROOTS):continue
            if path.is_symlink():raise ValueError('Release source cannot be a symlink: ' + name)
            files[name] = path.read_bytes()
    files['project.godot'] = (game / 'project.godot').read_bytes()
    files[MANIFEST] = (json.dumps(manifest(game), indent=2) + '\n').encode()
    files[CAMPAIGN_MANIFEST] = (json.dumps(campaign_manifest(game), indent=2) + '\n').encode()
    return files


def script_classes(files):
    def base_of(name, visited):
        if name in visited:raise ValueError('Cyclic script inheritance: ' + name)
        text = files[name].decode()
        parent = re.search(r'^extends\s+(?:"res://([^"\n]+)"|(\w+))', text, re.M)
        if parent is None:raise ValueError('Missing script base: ' + name)
        if parent[2]:return parent[2]
        target = parent[1]
        declared = re.search(r'^class_name\s+(\w+)', files[target].decode(), re.M)
        return declared[1] if declared else base_of(target, visited | {name})
    classes = []
    names = set()
    for name, data in sorted(files.items()):
        if not name.endswith('.gd'):continue
        text = data.decode()
        declared = re.search(r'^class_name\s+(\w+)', text, re.M)
        if declared is None:continue
        if declared[1] in names:raise ValueError('Duplicate script class: ' + declared[1])
        names.add(declared[1])
        classes.append({'base': base_of(name, set()), 'class': declared[1], 'icon': '',
                        'is_abstract': '@abstract' in text.splitlines(),
                        'is_tool': '@tool' in text.splitlines(),
                        'language': 'GDScript', 'path': 'res://' + name})
    return ('list=' + json.dumps(sorted(classes, key=lambda row: row['class'])) + '\n').encode()


def build_code_pack(root, version):
    files = source_files(root)
    files['.godot/global_script_class_cache.cfg'] = script_classes(files)
    project = files['project.godot'].decode()
    project = project.replace('[application]', '[application]\nconfig/version=' + json.dumps(version))
    files['project.godot'] = project.encode()
    # Keep all classes in the main pack. The content pack has declarative media
    # only and is mounted by the first autoload, before presentation preloads.
    return write_pack(files), files
