#!/usr/bin/env python3
"""Self-contained desktop launcher and CLI for portable external content."""
from pathlib import Path
import argparse
import json
import os
import subprocess
import sys

GAME = Path(__file__).resolve().parent
IMPORTER = GAME / 'importer'
sys.path.insert(0, str(IMPORTER / 'project/tools'))


def main(argv=None):
    parser = argparse.ArgumentParser(description='Moonstone: launch or create portable original-game content.')
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument('--import-content', action='store_true', help='Create content from disks without opening the game (headless).')
    modes.add_argument('--verify-content', action='store_true', help='Check the installed pack and print its path.')
    modes.add_argument('--export-content', type=Path, metavar='DIRECTORY', help='Copy a checked portable content folder to a new destination.')
    modes.add_argument('--install-content', type=Path, metavar='DIRECTORY', help='Validate and install a copied content folder; preserve saves.')
    modes.add_argument('--prepare-content', action='store_true', help=argparse.SUPPRESS)
    parser.add_argument('--force', action='store_true', help='Rebuild content; keep the old generation until the replacement passes.')
    args, game_args = parser.parse_known_args(argv)
    if args.force and not (args.import_content or args.prepare_content):parser.error('--force requires --import-content')
    if any((args.import_content, args.verify_content, args.export_content, args.install_content, args.prepare_content)) and game_args:
        parser.error('Unexpected arguments for the content command: ' + ' '.join(game_args))
    from portmaster_import import import_content, installed_content, atomic_json
    from import_transfer import export_content, install_content
    suffix = '.exe' if os.name == 'nt' else ''
    engine = GAME / ('moonstone' + suffix)
    setup_engine = GAME / ('moonstone-importer' + suffix)
    import_engine = GAME / ('moonstone-importer.console.exe' if os.name == 'nt' else 'moonstone-importer')
    game_probe = GAME / ('moonstone.console.exe' if os.name == 'nt' else 'moonstone')
    os.environ.update(MOONSTONE_GAME_DIR=str(GAME), MOONSTONE_IMPORTER_DIR=str(IMPORTER),
                      MOONSTONE_LAUNCHER_PYTHON=sys.executable, MOONSTONE_GAME_ENGINE=str(game_probe),
                      MOONSTONE_ENGINE_PACK_MODE='adjacent', PYTHONDONTWRITEBYTECODE='1', OPENBLAS_NUM_THREADS='1')
    # Preserve normal Godot save locations. Temporary smoke checks isolate their
    # own directories inside the importer; content is always beside the game.
    if args.verify_content:
        pack = installed_content(GAME)
        if not pack:raise ValueError('No valid content. Put your disks in ' + str(GAME/'disks') + ' and use --import-content.')
        print(pack);return 0
    if args.export_content:
        export_content(GAME, args.export_content);print('Portable content copied to ' + str(args.export_content.resolve()));return 0
    if args.install_content:
        install_content(GAME, args.install_content);print('Content installed. Original disks are not needed to play.');return 0
    if args.import_content or args.prepare_content:
        if not args.prepare_content:(GAME/'import-cancel').unlink(missing_ok=True)
        try:
            import_content(GAME, IMPORTER, import_engine, force=args.force)
        except Exception as error:
            atomic_json(GAME/'import-status.json', {'state':'failed','message':str(error),'percent':0})
            raise
        print('Content ready: ' + str(installed_content(GAME)));return 0
    if not installed_content(GAME):
        code = subprocess.call([str(setup_engine), '--audio-driver', 'Dummy'])
        if code:return code
        if not installed_content(GAME):raise ValueError('Content setup did not complete. See import.log beside the game.')
    os.environ['MOONSTONE_CONTENT_PACK'] = str(installed_content(GAME))
    return subprocess.call([str(engine), '--', *game_args])


if __name__ == '__main__':
    try:raise SystemExit(main())
    except (OSError, ValueError, RuntimeError) as error:
        print('Moonstone: ' + str(error), file=sys.stderr);raise SystemExit(1)
