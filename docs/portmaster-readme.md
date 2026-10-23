## Notes

Thanks to Rob Anderson, Mindscape and the original Moonstone team, and to
Jarskih, Godot, FRT and PortMaster for their tools. Remake and port: Craig Chandler.

An unofficial native remake of Moonstone: A Hard Day's Knight (1991).
**Your own original game data is required.**

Use 64-bit ARM firmware, glibc 2.28+, GLES 3 and a 640×480 or larger display.
RG40XX H/muOS is the tested baseline. Update PortMaster, then install **Godot
4.6.3** and **Westonpack 0.2** through its Runtime Manager.

Put `Moonstone.sh` and `moonstone/` in the firmware's ports directory.
For **muOS manual installation**, put the launcher in `roms/PORTS/` and the
folder in `ports/` on the same SD card.

Put these supported retail IPF images in `moonstone/disks/`:

```text
Moonstone_DiskA.ipf
Moonstone_DiskB.ipf
Moonstone_DiskC.ipf
```

First launch converts them locally; allow **1 GB free** and keep the device
powered on. Setup uses A to retry and B to exit. ADF images are not supported.
Later launches reuse the converted content without needing the disks.

Alternatively, copy the `content/current.json` and its named
`content/classic-v1-<checksum>/` folder from the matching Linux/Windows release
into `moonstone/content/`. Copy the generation folder first and `current.json`
last. Keep generated content private.

For updates, close the game, back up `moonstone/conf/`, then merge the package
into the installation. Preserve `conf/`, `content/` and `disks/`.
Saves/settings are in `conf/godot/app_userdata/Moonstone Remake/`.

For muOS menu artwork, copy `muos-thumbnail.png` as `Moonstone.png` into
`MUOS/info/catalogue/External - Ports/box/` on the Catalogue storage card.
Use the small thumbnail here; `screenshot.png` is the PortMaster catalogue image.

If launch fails, check `log.txt` and `import.log` in `moonstone/`.
The RG40XX H runtime can report an error on deliberate exit; report whether
it happened during play or after quitting.
[Full installation and troubleshooting guide](https://github.com/craigchandler/moonstone-remake/blob/main/docs/portmaster.md).

## Controls

Defaults use the RG40XX H's printed labels. Remap in Options → Controller.

| Button | Action |
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

Use the game's normal exit when possible to finish saving.

## Compile

Follow the [source build instructions](https://github.com/craigchandler/moonstone-remake/blob/main/docs/releases.md#building-and-releasing-from-source)
to install the pinned toolchains. From that checkout:

```bash
python3 tools/build_portmaster_importer.py \
  --upstream work/release-toolchain/upstream \
  --runtime-cache work/release-toolchain/runtimes \
  --output work/release-importer-arm --arch aarch64 --fetch-runtimes
python3 tools/release.py --tag v0.1.0 --platform PortMaster \
  --importer work/release-importer-arm --output outputs/release-build
```

Use the version in `game/version.json`. No original data is needed to build.
New source is MIT licensed; original content and import dependencies retain
separate terms. Notices are in `licenses/`; helper sources are in `importer.tar`.
