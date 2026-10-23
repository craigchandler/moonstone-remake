# Moonstone on PortMaster

This is an experimental ARM64 PortMaster testing package. The Anbernic RG40XX H
running muOS is the existing hardware baseline; other firmware/devices need testing.
The external-assets package supplies game code and import tools. It contains no
original disk images or playable Moonstone artwork, fonts, music or sounds.
Documentation screenshots for the catalogue/menu are included separately.
The first launch converts the user's supported disks into a separate content
pack on the SD card. Combat, RNG, network fingerprints and save formats remain
independent of artwork. This is not a PortMaster catalogue release.

## Install

See the [short PortMaster installation guide](portmaster-readme.md), also included
as `moonstone/README.md` in the release ZIP. It lists
controls, disk names, content-copy paths, artwork and troubleshooting.
The longer development/testing guides stay in the source repository.

The ZIP uses the standard **`Moonstone.sh` + `moonstone/`** layout. On most
PortMaster firmware, place both inside the firmware's ports directory. For a
**muOS manual install**, place the launcher in `roms/PORTS/` and the directory in
`ports/`, on the same games SD card. Do not extract the new ZIP straight to the
SD-card root. Existing installed muOS paths have not changed.

Install **Godot 4.6.3** (not Mono) and **Westonpack 0.2** with PortMaster's Runtime
Manager. The launcher requests missing runtimes when connected; install them
before playing offline. Place your own `Moonstone_DiskA.ipf`,
`Moonstone_DiskB.ipf` and `Moonstone_DiskC.ipf` in `moonstone/disks/`, or copy
verified desktop-created content into `moonstone/content/`. Open Moonstone from
Ports. Allow at least **1 GB free** for temporary conversion files.

The earlier RG40XX H/muOS importer completed conversion and validation in **1:56**,
with a user-reported **2:08 overall** including tool setup and automatic launch.
This is a hardware baseline, not a promised time or validation of a later ZIP.

Only the traced retail IPF version described in [importing](importing.md) is
supported. ADFs and other releases are not accepted. Originals are read only.
The package includes its ARM64 Python/image libraries and prebuilt converters;
players need no compiler, Godot editor, Python installation or network for the
conversion itself. The runtime dependencies still need to be installed first.

The startup screen explains missing disks. **A** retries and **B** exits.
During conversion it shows the current step and elapsed time, with sheet/family
counters inside the two long sprite-conversion steps. Steps vary in
length; the progress bar is not an estimate of the time remaining. The setup
window limits its refresh rate and uses no audio device to leave resources for
conversion. This does not limit the game's frame rate or audio.
Interrupted or failed conversion cannot replace an existing completed content
pack. Failure details are in `ports/moonstone/import.log`.
Completed stages record their duration in that log and in the generated content
manifest. CPU time and major page faults are recorded per sequential stage or
parallel batch, so simultaneous jobs are not double-counted. Final packing also
reports its resource count.
Resource packing runs in separate headless processes, followed by a validated
streaming merge. Rendering objects are never shared between workers. Duplicate
resources and corrupt payloads are rejected before content activation.
Combat colours are derived directly from the original register masks into the
layered sprites. The handheld importer avoids generating full colour-variant
combat sheets that its layered renderer does not use. Town/selection colour
variants remain available. Layer masks are computed within each pose rectangle,
and large image buffers are released between phases. All pose/colour/gore
comparisons still run; the desktop importer also retains the independent baked
variant path for comparison. Pack verification checks every payload without
retaining a second full copy of the content in memory. Original-data and game
startup checks remain in place.

Within each creature, decoded cels are reused, and repeated source draw programs
share tightly cropped atlas regions. Frame order, holds and drawing anchors are
preserved. Independent converters use up to four bounded CPU lanes; conversions that
update the same family remain ordered, and colour/timing stages wait for their
inputs. Sprite families are also checked in parallel. Set
`MOONSTONE_IMPORT_JOBS=1` in the launcher environment to use a single worker when
diagnosing a smaller device. Failure or cancellation stops all active converter
groups before discarding the incomplete workspace.

The packaged importer uses native kernels for MFM sector checks, LZSS decoding
and exact layer comparisons. Python reference paths remain available for
independent checks. Workers inherit preloaded libraries but run each converter
in a fresh process, retaining stage isolation and cancellation of helper groups.
Temporary PNGs use fast lossless compression. Only recovered images referenced
by game code or generated resources are packed; the recovery workspace retains
the complete extracted image set for validation. Audio retains QOA compression
to keep game memory use bounded on the 1 GB handheld.

## External content and updates

Game code is in `moonstone.pck`. Generated content lives separately under
`content/classic-v1-<checksum>/assets.pck`, selected by `content/current.json`.
The importer checks the disk filesystem, supported executable hash and generated
pack, then starts the game in an isolated smoke check before activating it.
Original sound tables remain disk-derived data; the prebuilt audio converters
contain no compiled-in original sample or sequence tables.

Completed content is reused after a checksum check. Disk images are not required
for later play. Normal code updates do not touch `content/`, `disks/` or `conf/`.
Keep old content until its replacement has been validated. A content-format
change requires a new importer/content version; code-only fixes do not.

The RG40XX H graphics runtime has shown an allocator abort while closing the
setup window after a successful import. The launcher handles that exit only
when the saved content passes a fresh checksum verification, then opens the
game. Cancellation and other setup errors still stop the launch. This is a
handoff workaround; the underlying graphics-runtime shutdown error remains.

The earlier **Moonstone-RG40XXH-muOS.zip** is a separate private package containing
preconverted assets. `tools/package_portmaster.py` can still reproduce that
baseline. It must not be confused with the external-assets distribution.

The ZIP includes `port.json`, `gameinfo.xml`, a 640×480 gameplay `screenshot.png`
and a separate 320×200 `muos-thumbnail.png`. For muOS copy the thumbnail, renamed
`Moonstone.png`, to `MUOS/info/catalogue/External - Ports/box/` on the card selected for
Catalogue storage (the tested muOS association is `External - Ports`). Leave and reopen Ports. Do not use the full-size screenshot
as muOS box art; it can cover the menu. XML/JSON metadata can be consumed by
PortMaster and compatible frontends; manual extraction alone may not update a
frontend's database. See [muOS artwork storage](https://muos.dev/installation/artwork).

## Controls and first test

The game uses native controller support. For the muOS Deeplay controller, the
launcher translates the legacy SDL2 mapping to Godot's SDL3 button numbering
before the engine starts. Face-button names match the letters printed on the
handheld; shoulders use L1/R1 and L2/R2, with SE/ST for Select/Start. Other
controllers retain their usual labels. Saved remaps remain in effect; the table
below describes defaults.

PortMaster's gptokeyb2 supplies only the Select + Start exit chord, with no mapping
file or virtual keyboard/mouse. Godot continues to read the real controller.
Update PortMaster if the launcher reports that gptokeyb2 is missing.

| Control | Action |
| --- | --- |
| D-pad / left stick | Movement and menu navigation |
| A (right) | Confirm / lunge |
| B (bottom) | Back / reverse strike |
| X (top) | Swing; end turn on map; help in panels |
| Y (left) | Overhead strike; inventory outside combat |
| L1 / R1 | Upward thrust / dagger; panel pages |
| L2 | Guard; Down + guard escapes supported holds |
| L2 / R2 in panels | Previous / next sheet |
| Right stick / R3 | Move sword cursor / click |
| L3 + L1/R1 | Own pack page modifier |
| SE (Select) | Retreat from combat |
| ST (Start) | Pause combat / menu |
| Select + Start | PortMaster force exit |

After a campaign battle, **A** confirms the result: return to the map after
defeat, or open loot after victory. If Choose has been remapped, the result
prompt names that button instead. Confirmation waits for death animations to
finish. **SE** remains the retreat/back route.

Start with **Practice**, select an opponent, then check movement, all seven
attacks/guard, sound, pause and return to the picker. Then start a solo journey,
enter your home village, open/close inventory and check Continue after exiting.
Use the game's normal exit when possible so it can finish saving.

The 640×400 game view keeps its aspect ratio on the 640×480 display. Black bars
are expected. Options → Controller provides remapping. The earlier RG40XX H/muOS tests
confirmed button recognition and battle-result
confirmation. The repackaged release and other devices still need physical testing.

## Saves and troubleshooting

Saves and controller preferences live in:

```text
ports/moonstone/conf/godot/app_userdata/Moonstone Remake/
```

Back up the entire `conf` folder before replacing a build. Package updates do
not contain or replace `conf`. The game ZIP includes no player saves or network
reconnect keys. Network play is present, but communication between the desktop
4.6.1 engine and handheld 4.6.3 runtime has not been verified.

If launch returns to the menu, inspect `ports/moonstone/log.txt`. Check that the
game folder and launcher are on the same SD card, PortMaster is updated, and
both runtimes are installed in the PortMaster installation used by the launcher.
The log records device/firmware/architecture
and Godot errors. If controls fail or double-trigger, retain that log and report
which buttons work. The log also records the mapping actually supplied to Godot.
The controller settings screen should identify the built-in pad as **RG40XX H**.
Do not reset your saved bindings unless you want to restore the defaults.

## Community testing

See [testing coverage and report template](portmaster-testing.md). Metadata requires
original data, ARM64, glibc 2.28+, and a 640×480-or-larger display. The ZIP follows
the installed PortMaster layout; a future catalogue source PR has a separate
structure and review process.

## Build locally

The tag-triggered [release workflow](releases.md#building-and-releasing-from-source)
builds the code pack directly from public source. No original images, converted
assets or prior desktop exports are needed. Install its pinned toolchains, then:

```bash
python3 tools/build_portmaster_importer.py \
  --upstream work/release-toolchain/upstream \
  --runtime-cache work/release-toolchain/runtimes \
  --output work/release-importer-arm --arch aarch64 --fetch-runtimes
python3 tools/release.py --tag v0.1.0 --platform PortMaster \
  --importer work/release-importer-arm --output outputs/release-build
```

Use the version in `game/version.json`. The guide covers Zig/compiler setup,
automatic and CLI import, and the exact `content/` layout for desktop-to-device
copies. Runtime archives/wheels are SHA256-pinned in
`tools/portmaster-importer-runtimes.json`; build sources/compiler are pinned in
`tools/release-toolchain.json`. `--resume` refreshes an explicitly selected local
importer directory. Outputs remain ignored local material.

The older `tools/package_portmaster_external.py` remains a local diagnostic path
that splits an already accepted, asset-containing private desktop export. It is
not used by public release automation.

The importer retains upstream notices and helper sources. CAPSImg and Moonstone
ACE have separate noncommercial terms; their inclusion does not relicense them
as MIT or grant redistribution rights to original content. See [THIRD_PARTY.md](../THIRD_PARTY.md).

Desktop import, exported runtime probes, rendered captures and real handheld
execution are distinct checks. Do not describe ARM64 build success as proof of
on-device extraction, memory use, audio or performance.
