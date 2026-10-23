# Moonstone Remake

An unofficial native remake of **Moonstone: A Hard Day’s Knight (1991)** by
Craig Chandler, built with Godot for Linux, Windows and PortMaster ARM64.

The project recreates the original game’s combat and campaign while preparing
for replaceable graphics and gameplay content. It is a work in progress, not a
finished or fully accurate reproduction.

**This repository contains source code and documentation screenshots. Original
game data, runtime artwork/audio packs, reference footage and playable packages
are not included.**
Running the classic version requires a separately provisioned local asset set
or a one-time import from your own compatible original data. Disk images are
not needed during play.

## Screenshots

| Intro | Main menu |
| --- | --- |
| [![Druids in the opening sequence](docs/screenshots/intro.png)](docs/screenshots/intro.png) | [![Classic main menu](docs/screenshots/main-menu.png)](docs/screenshots/main-menu.png) |

| Practice menu | World map |
| --- | --- |
| [![Practice opponent selection with layered knight and Balok previews](docs/screenshots/practice-menu.png)](docs/screenshots/practice-menu.png) | [![Campaign world map](docs/screenshots/world-map.png)](docs/screenshots/world-map.png) |

| Battle | Highwood |
| --- | --- |
| [![Blue knight striking a Balok](docs/screenshots/battle.png)](docs/screenshots/battle.png) | [![Highwood town and services](docs/screenshots/town-highwood.png)](docs/screenshots/town-highwood.png) |

| Waterdeep | Tavern |
| --- | --- |
| [![Waterdeep town and services](docs/screenshots/town-waterdeep.png)](docs/screenshots/town-waterdeep.png) | [![Tavern dice table](docs/screenshots/town-tavern.png)](docs/screenshots/town-tavern.png) |

[Capture details and artwork attribution](docs/screenshots.md).

## Current game

- Native combat against the original creature roster, with directional sword
  attacks, throwing daggers, holds, deaths, gore options and sound.
- World travel, lairs, loot, equipment, experience, stat upgrades, towns and
  quest progression.
- Four knight identities, computer rivals, local human turns and human duels.
- Standalone practice against every native creature and knight opponent.
- Direct two-player network practice duels with host/join, readiness and rematches.
- Classic network campaigns for one to four humans, with computer knights filling
  the other seats, spectator inventory browsing and reserved-seat reconnect.
- Optional command-line host for campaigns or practice duels, sharing the same
  authority as in-game hosting.
- Keyboard, mouse and configurable controller input; campaign save/continue.
- Native opening, menus, location scenes and ending sequences.

Simultaneous campaign turns, internet matchmaking/relay, human cooperative encounters,
a public mod API and HD/3D renderers are future work. Some timings, movement and presentation remain native
adaptations. Automated checks do not establish complete original-game parity.

## Set up and play

| What you want to do | Start here | Original assets needed? |
| --- | --- | --- |
| Install a release ZIP or copy content between platforms | [Release and content guide](docs/releases.md) | Your supported disks on first setup, or a copied content pack |
| Play an installed game | [Player guide](docs/player-guide.md) | A separately generated content pack |
| Run on RG40XX H / muOS | [PortMaster guide](docs/portmaster.md) | Generated on first launch from your own supported disks |
| Build the classic game from your own disks | [One-time import](docs/importing.md), then [build instructions](docs/development.md) | Yes |
| Host from the game | [Network journey](docs/player-guide.md#network-journey) | A provisioned game client |
| Run or build a standalone server | [Server setup](docs/server-guide.md) | No |

Tag-triggered public releases build without original assets and include automatic
and command-line setup. See the [release guide](docs/releases.md) for downloads,
exact disk/content paths, desktop-to-handheld copying, and the `v*` workflow.
Standalone server ZIPs remain asset-free and contain no importer.

For a private asset-containing development build, use **Godot 4.6.1**, matching Linux/Windows export templates,
Python 3.11+, Bash and Git. After provisioning compatible local assets or
completing the one-time import, run from the repository root:

```bash
bash tools/build.sh --skip-import
```

Extract `outputs/Moonstone-Network-Campaign-Linux.zip` or
`outputs/Moonstone-Network-Campaign-Windows.zip`. Run `Moonstone.sh` on Linux or
`Moonstone.cmd` on Windows. Players need neither Godot nor the import/build tools.
The public repository does not include these asset-containing game packages.

For a campaign, choose **Network journey** on the title screen. One player uses
**Host new journey**, or everyone joins a [standalone server](docs/server-guide.md#host-a-campaign).
All humans choose **Ready**. The default is **UDP 27867**; practice duels use
**UDP 27866**. Use the host computer's LAN address when joining from another
computer. See the guides for reconnect, backups and troubleshooting.

Standalone server builds need source and the pinned toolchain, with no original
assets or disk import. See the [complete server build steps](docs/server-guide.md#build-the-server-from-source).
Server versions and `server-v*` tags are independent of the game version.

Current validation includes automated source tests, exported Linux execution,
scripted graphical Linux checks and local UDP tests with injected delay/loss.
The external-content release packages also pass Linux checks and Windows
conversion/content-transfer checks under Wine. Native Windows execution, separate-machine campaign LAN
play, manual full-campaign playthroughs and the hosted release workflow still
need validation. See [validation status](docs/development.md#evidence).

Without original assets, build-tool and publication checks can still run
(install `requirements-import.txt` to include conversion tests):

```bash
python3 -m unittest discover -s tools/tests
python3 tools/check_public_tree.py --ref HEAD
```

## Project documentation

- [Architecture and deterministic gameplay](docs/architecture.md)
- [Classic gameplay pack and script boundaries](docs/gameplay-packs.md)
- [Artwork and renderer boundaries](docs/art-packs.md)
- [Install releases, extract and copy content](docs/releases.md)
- [Build, test and export workflow](docs/development.md)
- [Screenshot gallery](docs/screenshots.md)
- [Command-line hosting](docs/server-guide.md)
- [Original-data import](docs/importing.md)
- [Asset and distribution policy](docs/asset-policy.md)
- [Roadmap](docs/roadmap.md)
- [Contributing](CONTRIBUTING.md)
- [Third-party references and dependencies](THIRD_PARTY.md)

## Licence and attribution

New source code in this repository is licensed under [MIT](LICENSE). This does
not grant rights to the original Moonstone game, its title, artwork, music,
sounds or other separately licensed material. This project is not affiliated
with or endorsed by the original creators or rights holders.

The original game’s credits are retained in locally imported content.
[THIRD_PARTY.md](THIRD_PARTY.md) records reference projects and the separate
licences of optional import dependencies.
