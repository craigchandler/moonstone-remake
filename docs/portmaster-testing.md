# PortMaster community testing

This is an experimental ARM64 build of an unofficial native remake, not an
accepted PortMaster catalogue port. RG40XX H with muOS is the existing hardware
baseline. The standard ZIP layout and metadata are checked by the release build;
that check is not evidence of execution on other firmware.

See the [short installation guide](portmaster-readme.md) and
[PortMaster's packaging/testing process](https://portmaster.games/packaging.html).
The community testing thread precedes any catalogue submission. Maintainers
decide acceptance and the appropriate repository for this unofficial remake.

## Suggested testing-thread introduction

> Moonstone Remake — experimental ARM64 testing build
>
> This is an unofficial native Godot remake of Moonstone: A Hard Day's Knight.
> It is still in development. The existing hardware baseline is RG40XX H/muOS;
> I'm looking for feedback on fresh installation and other compatible ARM64
> firmware/devices, resolutions and controllers.
>
> You need your own supported retail IPF disk set, or a content pack generated
> using the Linux/Windows package from the same release. No original disks or
> playable content pack are included. First launch can convert your disks;
> desktop-created content can be copied over to skip handheld conversion.
>
> Install Godot 4.6.3 and Westonpack 0.2 through PortMaster. The ZIP contains
> Moonstone.sh and moonstone/. Read moonstone/README.txt before extracting:
> muOS puts the launcher and game folder in separate locations.
>
> Please report your device, firmware/version, resolution, ZIP version/checksum,
> setup method, controls, audio, gameplay, battle-result confirmation and
> Save/Continue. If it fails, include log.txt and import.log when present, plus
> whether you deliberately exited. Please don't share disks or generated content.

Attach the actual tested ZIP or its GitHub release link and SHA256. Include the
results for that exact archive; the earlier 2:08 handheld import measurement is
a baseline, not an acceptance test of every subsequent build. A GitHub source
commit alone is not a playable download. Never claim a test was run from this template.

## Coverage to record

Record device/firmware versions and a result separately for each case:

- Fresh install with missing disks: useful setup message and clean exit.
- Supported disks: progress, total time including tool unpacking, automatic
  game launch; subsequent launch reuses content.
- Content copied from the matching Linux/Windows release: verifies and starts
  without converting; no desktop binaries copied.
- Practice: face buttons, both sticks, shoulders/triggers, remapping, pause,
  sound and normal exit. Check result confirmation after both victory and defeat.
- Journey: map movement, inventory, town entry, combat, loot, Save/Continue.
- Update an existing install: content, settings and saves survive a file merge.
- Menu image beside the muOS list; catalogue screenshot/metadata on other frontends.
- 640×480 and higher-resolution displays; optional 720×720 coverage. Current
  metadata excludes displays below 640×480; 480×320 support is not claimed.
- muOS, AmberELEC, dArkOS, ROCKNIX (different graphics stacks) and Knulli on
  compatible ARM64 hardware. Mark unavailable combinations NOT_RUN.

Desktop/handheld network interoperability needs separate testing; differing
Godot runtime versions and successful local play do not establish network support.

## Report template

```text
ZIP version and SHA256:
Device / RAM / resolution:
Firmware and version / PortMaster version:
Install: fresh / update; SD layout:
Content: handheld import / copied from Linux / copied from Windows:
Setup time (include unpacking), automatic launch, subsequent launch:
Controls / audio / display:
Practice victory and defeat confirmation:
Journey / loot / town / Save-Continue:
Normal exit or unexpected crash:
Reproduction steps and relevant logs:
Result: PASS / FAIL / NOT_RUN for each tested case
```

## Package structure and eventual submission

The release ZIP uses `Moonstone.sh` at its root and puts metadata, README,
screenshot, notices, import tools and game code inside `moonstone/`. Current
HarbourMaster accepts `moonstone/port.json`; the older `*.port.json` spelling is
not duplicated. Metadata marks the port experimental and not ready-to-run,
declares its ARM64 importer and both runtimes, and links XML to the actual launcher
and screenshot. A separate cover is optional; the gameplay screenshot is used.

A future PortMaster source PR has a different layout: `ports/moonstone/` contains
`port.json`, `README.md`, `gameinfo.xml`, `screenshot.png`, `Moonstone.sh` and the
inner `moonstone/` payload. Follow the current upstream tools when preparing it.
The uncompressed `importer.tar` exceeds their 90 MB per-file repository limit;
use upstream `tools/build_data.py` to split it for a PR. That is a Git repository
limit, not a requirement to split the downloadable ZIP. Do not put the package,
disk images or generated content into this source repository.
