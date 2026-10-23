# Moonstone Remake — PortMaster testing build

An unofficial, work-in-progress native remake of Moonstone: A Hard Day's Knight
(1991). **Original game data required.** This package contains game code, import
tools and documentation screenshots, but no original disks or playable artwork,
fonts, music or sound pack. It is an experimental community testing build, not
an accepted PortMaster catalogue release.

Thanks to Rob Anderson, Mindscape and the original credited Moonstone team;
Jarskih for Moonstone ACE's separately licensed import helpers; and the Godot,
FRT and PortMaster contributors. Remake and port: Craig Chandler.
Source: https://github.com/craigchandler/moonstone-remake

## Install

Use a current PortMaster installation on **64-bit ARM (aarch64)** firmware.
The bundled importer needs glibc 2.28 or newer. Godot 4 needs working GLES 3
graphics. The minimum target display is 640×480. RG40XX H with muOS is the
tested hardware baseline; other firmware, devices and resolutions need testing.

The ZIP contains `Moonstone.sh` and `moonstone/`. Keep the directory name lowercase.
Do not extract this ZIP straight to the SD-card root.

| Firmware | Where the ZIP's items go |
| --- | --- |
| Standard PortMaster layout | Put both `Moonstone.sh` and `moonstone/` inside the firmware's `ports` directory. |
| muOS manual install | Put `Moonstone.sh` in `roms/PORTS/` and the `moonstone/` directory in `ports/`, on the same games SD card. Example: `/mnt/mmc/roms/PORTS/Moonstone.sh` and `/mnt/mmc/ports/moonstone/`. Use the corresponding second-card paths when applicable. |

The `moonstone/` directory is the **game folder** in the instructions below.
For an update, close the game, back up `moonstone/conf/`, and merge the new files
into the existing installation. Preserve `content/`, `disks/` and `conf/`.
This replaces the earlier SD-root ZIP layout; the installed muOS paths stay the same.

Install **Godot 4.6.3** (not Mono) and **Westonpack 0.2** using PortMaster's Runtime
Manager. The launcher requests missing runtimes when connected. Offline users
must install them beforehand. They are not bundled with this ZIP.

## Supply your game data

Choose either method:

1. **Import on the handheld:** put your own supported retail IPF images in the
   game folder's `disks/` directory with these exact names:

   ```text
   Moonstone_DiskA.ipf
   Moonstone_DiskB.ipf
   Moonstone_DiskC.ipf
   ```

   Open Moonstone from the Ports menu. Setup shows progress and elapsed time,
   then starts the game. Allow at least **1 GB free** for conversion and keep
   the device powered on. The earlier RG40XX H/muOS test took **2:08 overall**;
   this is a measured baseline, not a guarantee for this build or other hardware.
   Only the supported retail IPF disk set is accepted; ADF and other editions
   are not supported. Originals are read only. Setup: A retries, B exits.

2. **Skip handheld conversion:** generate content with the Linux or Windows ZIP
   from the same release. With both games closed, copy the named generation
   directory first and `current.json` last into the handheld's game folder:

   ```text
   moonstone/content/current.json
   moonstone/content/classic-v1-<16-character checksum>/assets.pck
   moonstone/content/classic-v1-<16-character checksum>/manifest.json
   ```

   Copy the actual directory named in `current.json`; do not rename it or create
   `content/content/`. Do not copy desktop executables, importer tools, caches
   or saves. A valid copied pack skips conversion and importer unpacking.

Later launches reuse content. Disk images are not needed during play. Generated
content contains original media: keep it private and do not attach it to test reports.

## Command-line import and verification

From a terminal/SSH session on the handheld, in the directory containing the launcher:

```sh
bash ./Moonstone.sh --import-content
bash ./Moonstone.sh --verify-content
bash ./Moonstone.sh --import-content --force
```

On muOS, for example:

```sh
bash /mnt/mmc/roms/PORTS/Moonstone.sh --import-content
bash /mnt/mmc/roms/PORTS/Moonstone.sh --verify-content
```

CLI import exits after conversion. `--force` rebuilds while preserving the last
working pack until the replacement passes validation. See `docs/releases.md`
for desktop commands and content export/install helpers.

## Controls

Defaults below use the RG40XX H's printed labels. Other controllers may display
different labels. Options → Controller supports remapping; existing remaps remain.

| Control | Action |
| --- | --- |
| D-pad / left stick | Move / menu navigation |
| A (right) | Confirm / lunge; confirm battle result |
| B (bottom) | Back / reverse strike |
| X (top) | Swing; end map turn; panel help |
| Y (left) | Overhead strike; inventory outside combat |
| L1 / R1 | Upward thrust / dagger; panel pages |
| L2 | Guard; Down + guard escapes supported holds |
| L2 / R2 in panels | Previous / next sheet |
| Right stick / R3 | Move cursor / click |
| L3 + L1/R1 | Own pack page modifier |
| SE / Select | Retreat |
| ST / Start | Pause / menu |
| Select + Start | PortMaster force exit |

After death animations finish, A returns to the map after defeat or opens loot
after victory. Use the game's normal exit when possible to finish saving.

## Menu artwork

`gameinfo.xml`, `port.json` and the 640×480 `screenshot.png` are included for
PortMaster and compatible frontends. The screenshot doubles as the optional cover.
Manual extraction alone may not import metadata into a frontend's database.

For muOS, copy **`muos-thumbnail.png`**, renamed to **`Moonstone.png`**, to the
card selected for Catalogue storage at `MUOS/info/catalogue/External - Ports/box/`.
This is the tested `External - Ports` catalogue association; use your assigned
catalogue directory if it differs. Then leave and reopen Ports. This 320×200 image stays beside the menu. Do not
use the full-size catalogue screenshot as muOS box artwork; it can cover the menu.

## Saves, troubleshooting and testing

Saves/settings: `moonstone/conf/godot/app_userdata/Moonstone Remake/`.
Back up `conf/` before updates. Copying content does not copy saves.

If launch returns to the menu, check `moonstone/log.txt`. Conversion errors are
in `moonstone/import.log`; `moonstone/import-status.json` records progress.
Check the installation paths, free space, runtimes and architecture. Setup and
the game have a known RG40XX H graphics-runtime shutdown error; a nonzero exit
after deliberately quitting is different from a mid-game crash. The launcher
verifies completed content before recovering the known setup shutdown failure.

Start with Practice: test movement, attacks, guard, pause, audio and result
confirmation. Then test a solo journey, inventory, town entry and Save/Continue.
Report the ZIP version/checksum, device, firmware/version, resolution, fresh
import or copied content, exact steps and whether you chose to exit. Include
relevant logs, not disk images or generated packs. More test cases and a report
template are in `docs/portmaster-testing.md`.

## Source, build and licences

Build instructions: https://github.com/craigchandler/moonstone-remake/blob/main/docs/releases.md
(also `docs/releases.md` in this ZIP). The `v*` release workflow uses public
source and pinned toolchains; it does not need or upload original game data.

New code is MIT licensed. Original game material and the screenshots retain
their respective rights. Import dependencies include separately licensed
noncommercial helpers. Read `SOURCE-LICENSE.txt`, `ATTRIBUTION.txt` and `licenses/`.
Importer helper sources and further notices are also retained inside `importer.tar`.
