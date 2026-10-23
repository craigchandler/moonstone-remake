# Downloading, installing and creating content

Each `vX.Y.Z` release provides Linux x86_64, Windows x86_64 and PortMaster ARM64
game ZIPs, plus separate Linux and Windows standalone server ZIPs. Download the
ZIP for your platform and check its SHA256 against the release's `SHA256SUMS`.
Extract the entire ZIP, keeping its directories together. The game packages
include their engine/import tools; Python, Pillow and NumPy do not need separate
installation. Original disks and playable artwork/audio packs are not included.
PortMaster includes documentation screenshots for its catalogue and menu.

The server packages are asset-free and need neither disks nor conversion tools.
Use `Moonstone-Server.sh` or `Moonstone-Server.cmd`; their `READ ME.txt` explains
duel and campaign hosting. Use clients and servers from the same release for
matching gameplay protocols and fingerprints. Server display versions are
independent of the game version.

## Game installation

Use a writable folder, with at least 1 GB free for conversion. Avoid installing
inside Windows Program Files. Do not launch a file from inside the ZIP viewer.

| Platform | Extract to | Start the game | Original disks | Generated content |
| --- | --- | --- | --- | --- |
| Linux x86_64 | Any writable game folder | `./Moonstone.sh` | `disks/` beside the launcher | `content/` beside the launcher |
| Windows x86_64 | Any writable game folder | Double-click `Moonstone.cmd` | `disks\` beside the launcher | `content\` beside the launcher |
| PortMaster ARM64 | `Moonstone.sh` + `moonstone/` inside the firmware ports directory; muOS: launcher → `roms/PORTS/`, folder → `ports/` | Ports → Moonstone | `disks/` inside `moonstone/` | `content/` inside `moonstone/` |

Linux uses glibc 2.28 or newer and a working OpenGL 3.3 driver/display environment;
normal system graphics/audio libraries are still required. Windows uses 64-bit
Windows and an OpenGL 3.3 capable driver. PortMaster needs its Godot 4.6.3 FRT and
Westonpack runtimes; its launcher offers to install missing runtimes through
PortMaster when connected. See [PortMaster details](portmaster.md) for muOS paths
and runtime installation. PortMaster is an experimental testing ZIP with metadata
and a screenshot, not
an accepted catalogue release. Read `moonstone/README.txt` before installing;
the ZIP no longer has the earlier muOS SD-root wrapper directories. See the
[short PortMaster guide](portmaster-readme.md) and [testing guide](portmaster-testing.md).

Place your supported retail IPF images in the platform's `disks` directory with
these exact names:

```text
Moonstone_DiskA.ipf
Moonstone_DiskB.ipf
Moonstone_DiskC.ipf
```

Start with the launcher listed above, rather than the engine executable. If
there is no valid content pack, setup opens automatically, checks the disks and
shows conversion progress and elapsed time. The game starts after content passes
validation. Later launches reuse the pack. Missing or unsupported disks produce
an explanation; original disk files are read only. The supported retail images
are identified by checksums in the importer; ADF, modified and other disk sets
are not silently accepted. See [importing](importing.md) for the source workflow.

On the tested RG40XX H/muOS baseline, first setup took about 2 minutes 8 seconds
including tool unpacking. Device/storage and build differences affect time; this
is a measured baseline, not a promised upper limit. Creating content on a desktop
and copying it avoids that conversion on the handheld.

## Command-line conversion

Run commands from the extracted game folder. Quotes are required around paths
containing spaces. Conversion ends without starting the game and returns a
nonzero status on failure. No graphical desktop is required for CLI conversion.

Linux:

```sh
./Import-Content.sh
# Equivalent:
./Moonstone.sh --import-content
./Moonstone.sh --verify-content
# Explicitly rebuild while preserving the previous working generation:
./Moonstone.sh --import-content --force
```

Windows Command Prompt:

```bat
Import-Content.cmd
Moonstone.cmd --import-content
Moonstone.cmd --verify-content
Moonstone.cmd --import-content --force
```

In PowerShell prefix the launcher with `.\`, for example
`.\Moonstone.cmd --import-content`.

PortMaster (a terminal/SSH session on muOS, adjusting the SD path if necessary):

```sh
bash "/mnt/mmc/roms/PORTS/Moonstone.sh" --import-content
bash "/mnt/mmc/roms/PORTS/Moonstone.sh" --verify-content
bash "/mnt/mmc/roms/PORTS/Moonstone.sh" --import-content --force
```

PortMaster CLI import uses the installed PortMaster runtime and control files;
it is not a generic ARM Linux launcher. Original disks go in the directories
listed above. `import.log` and `import-status.json` beside the game's PCK contain
conversion diagnostics and progress. A failed/cancelled rebuild preserves the
previous content pointer and saves. Keep the device powered during writes.

## Copy content between platforms

Content format 1 is shared by Linux, Windows and PortMaster. Create it once from
your disks, then copy it to your other installations of the same release.
Executable files, import tools and caches are platform-specific; do not copy
those as content. Content contains original-game media; keep it private.

With both games closed, copy `current.json` and the directory it names into the
destination's `content` directory:

```text
content/
  current.json
  classic-v1-<16-character checksum>/
    assets.pck
    manifest.json
```

For example, Linux `Moonstone/content/` → muOS
`/mnt/mmc/ports/moonstone/content/`. On a card reader or MTP, open the SD card's
`ports/moonstone/content` directory and place the two items there. Do not create
`content/content/`. Copy the generation directory first and `current.json` last.
Existing unrelated generations can remain. A transferred valid pack skips disk
conversion; original disks are then unnecessary for play. PortMaster can also
verify transferred content before unpacking its importer tools.

The desktop launchers can make and install checked copies:

```sh
# Linux: export to a new folder (the destination must not already exist).
./Moonstone.sh --export-content "/path/to/transfer/moonstone-content"
# On another Linux installation:
./Moonstone.sh --install-content "/path/to/transfer/moonstone-content"
```

```bat
rem Windows: same content folder, including one generated on Linux.
Moonstone.cmd --install-content "D:\transfer\moonstone-content"
Moonstone.cmd --export-content "D:\transfer\new-moonstone-content"
```

These commands check pack checksums, version and media-only paths before
activation. They copy only the active generation, not disks, logs, temporary
work, caches or saves. Raw copy has the same layout; use `--verify-content`
afterward. Rebuild from your disks if a future release changes content format or
requires new resources. Do not mix arbitrary game/code versions with a pack.

Saves and controller settings are separate. Desktop uses Godot's per-user
`Moonstone Remake` data directory (normally
`~/.local/share/godot/app_userdata/Moonstone Remake/` on Linux and
`%APPDATA%\Godot\app_userdata\Moonstone Remake\` on Windows). PortMaster keeps
them in `ports/moonstone/conf/`. Copying content does not transfer saves.

## Building and releasing from source

The public pipeline in `.github/workflows/release.yml` runs on pushed `v*` tags.
It requires an exact match to `game/version.json`. The existing `server-v*`
pipeline remains available for independent server releases.

The build reads only public source and checksum-pinned tools. It builds the
code-only game PCK directly, generates the setup PCK, builds native importer
helpers for each platform, and packages the required Python runtime. It does not
use a previously provisioned desktop export, your `reference/` folder or any
original disk images. Linux and Windows acceptance jobs run the shipped
launchers, native dependencies, setup and synthetic content transfer checks.
The server job also checks real exported Linux duel/campaign networking. CI
does not claim original-disk conversion, graphical playtesting, ARM execution,
or native Windows server networking from these checks.

For a local Linux build, install Python 3, C/C++ build utilities and MinGW-w64
(`x86_64-w64-mingw32-g++` for Windows helpers), then:

```sh
python3 tools/install_server_toolchain.py
python3 tools/install_release_toolchain.py
# Add the printed Zig directory to PATH. The GitHub job does this automatically.
export GODOT_BIN="$PWD/work/server-toolchain/Godot_v4.6.1-stable_linux.x86_64"
export GODOT_TEMPLATES_DIR="$PWD/work/server-toolchain/templates"
python3 tools/build_portmaster_importer.py \
  --upstream work/release-toolchain/upstream \
  --runtime-cache work/release-toolchain/runtimes \
  --output work/release-importer-linux --arch x86_64 --fetch-runtimes
python3 tools/release.py --tag v0.1.0 --platform Linux \
  --importer work/release-importer-linux --output outputs/release-build
python3 tools/verify_release.py --platform Linux \
  --archive outputs/release-build/Moonstone-0.1.0-Linux.zip \
  --output outputs/release-build/Linux-acceptance.json
```

Use a fresh output folder per importer build, or `--resume` to refresh its
source/helpers. For Windows use `--arch windows-x86_64 --platform Windows`; for
PortMaster use `--arch aarch64 --platform PortMaster`. Run Windows acceptance on
Windows. Use `tools/server_release.py --tag server-v0.1.0` for the two lightweight
server ZIPs. Update example versions to match the corresponding version files.
Build-only dependencies do not need installing on player machines.

To publish: review and commit the source changes, set `game/version.json`, run
the relevant checks and public-tree audit, then push that commit and its matching
tag. For example, after preparing version 0.1.0:

```sh
git tag v0.1.0
git push origin v0.1.0
```

The workflow builds all five ZIPs, checks the evidence and hashes, and creates a
GitHub Release with the exact asset allowlist and `SHA256SUMS`. Prerelease tags
such as `v0.1.0-rc.1` are marked prerelease. Normal branch pushes do not publish.
Publishing requires the repository's Actions token to have release permission;
the workflow requests `contents: write` only in its final publishing job.
