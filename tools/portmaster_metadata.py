"""PortMaster package metadata and validation, independent of original game data."""
import json
from pathlib import PurePosixPath
import xml.etree.ElementTree as ET
from zipfile import ZipFile

from check_public_tree import valid_screenshot


def metadata_files(root):
    info = json.loads((root / 'tools/portmaster-port.json').read_text())
    tree = ET.Element('gameList')
    game = ET.SubElement(tree, 'game')
    for name, text in {
        'path': './Moonstone.sh', 'name': info['attr']['title'],
        'desc': info['attr']['desc'], 'developer': 'Craig Chandler',
        'publisher': 'Craig Chandler', 'genre': 'Action / RPG',
        'players': '1-4', 'image': './moonstone/screenshot.png',
    }.items():
        ET.SubElement(game, name).text = text
    ET.indent(tree, space='  ')
    screenshot = (root / 'docs/screenshots/portmaster.png').read_bytes()
    if not valid_screenshot(screenshot, (640, 480)):
        raise ValueError('PortMaster screenshot must be a complete 640x480 PNG')
    readme = (root / 'docs/portmaster-readme.md').read_bytes()
    return {
        'port.json': (json.dumps(info, indent=2) + '\n').encode(),
        'gameinfo.xml': ET.tostring(tree, encoding='utf-8', xml_declaration=True) + b'\n',
        'README.md': readme, 'README.txt': readme,
        'screenshot.png': screenshot,
        'override.cfg': b'[display]\nwindow/stretch/aspect="keep"\n',
    }


def validate_archive(path):
    """Fail release packaging on unsafe layout, stale metadata or bundled content."""
    with ZipFile(path) as archive:
        names = archive.namelist()
        if len({name.casefold() for name in names}) != len(names):
            raise ValueError('Duplicate PortMaster archive path')
        for name in names:
            item = PurePosixPath(name)
            if (item.is_absolute() or '..' in item.parts or '\\' in name or
                    (name != 'Moonstone.sh' and not name.startswith('moonstone/'))):
                raise ValueError('Unexpected PortMaster archive path: ' + name)
            mode = archive.getinfo(name).external_attr >> 16
            if mode & 0o170000 == 0o120000:
                raise ValueError('Symlink in PortMaster archive: ' + name)
            if name.startswith(('moonstone/content/', 'moonstone/disks/', 'moonstone/conf/')) and name not in {
                'moonstone/content/PUT-CONTENT-HERE.txt', 'moonstone/disks/PUT-YOUR-DISKS-HERE.txt',
            }:
                raise ValueError('Player content entered PortMaster archive: ' + name)
        expected = {'Moonstone.sh', 'moonstone/moonstone.pck', 'moonstone/importer.pck',
                    'moonstone/moonstone-run',
                    'moonstone/importer.tar', 'moonstone/importer.sha256',
                    'moonstone/README.txt', 'moonstone/README.md', 'moonstone/port.json',
                    'moonstone/gameinfo.xml', 'moonstone/screenshot.png',
                    'moonstone/override.cfg', 'moonstone/muos-thumbnail.png'}
        if not expected.issubset(names):
            raise ValueError('Missing PortMaster files: ' + ', '.join(sorted(expected - set(names))))
        if not (archive.getinfo('Moonstone.sh').external_attr >> 16) & 0o111:
            raise ValueError('PortMaster launcher is not executable')
        info = json.loads(archive.read('moonstone/port.json'))
        attr = info['attr']
        if (info['version'] != 4 or info['name'] != 'moonstone.zip' or
                info['items'] != ['Moonstone.sh', 'moonstone'] or
                attr['rtr'] is not False or attr['exp'] is not True or
                attr['porter'] != ['Craig Chandler'] or
                attr['arch'] != ['aarch64'] or attr['min_glibc'] != '2.28' or
                set(attr['runtime']) != {'godot_4.6.3.squashfs', 'weston_pkg_0.2.squashfs'}):
            raise ValueError('Incorrect PortMaster requirements or installation metadata')
        xml = ET.fromstring(archive.read('moonstone/gameinfo.xml'))
        if xml.tag != 'gameList' or len(xml.findall('game')) != 1:
            raise ValueError('Invalid PortMaster gameinfo root')
        game = xml.find('game')
        if (game.findtext('path') != './Moonstone.sh' or
                game.findtext('image') != './moonstone/screenshot.png' or
                game.findtext('developer') != 'Craig Chandler' or
                game.findtext('publisher') != 'Craig Chandler' or
                game.findtext('name') != attr['title'] or game.findtext('desc') != attr['desc']):
            raise ValueError('PortMaster XML disagrees with package metadata')
        for name, size in [('screenshot.png', (640, 480)), ('muos-thumbnail.png', (320, 200))]:
            if not valid_screenshot(archive.read('moonstone/' + name), size):
                raise ValueError('Invalid PortMaster image: ' + name)
        if archive.testzip():
            raise ValueError('PortMaster ZIP integrity failure')
    return {'result': 'PASS', 'files': len(names), 'metadata_version': 4,
            'layout': 'Moonstone.sh + moonstone/', 'hardware_execution': 'NOT_RUN'}
