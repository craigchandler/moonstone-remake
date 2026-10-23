# One-time original-data import

Linux, Windows and PortMaster [release ZIPs](releases.md) include self-contained
automatic and command-line setup. Use that guide for player commands, disk
locations and copying content between platforms. This page describes the offline
source-development workflow.
Its output is native PNG/audio and
Godot content; the exported game contains no disk-image loader, original
executable, original-script VM or Amiga emulator.

The public repository does not supply disk images or converted assets. Use your
own compatible original data and observe its rights. Current converters require
the traced retail MOG SHA1 `bb38bc0b39f146b30bac959bea717202cf13b965`;
other releases are rejected rather than silently mapped to wrong offsets.

## Additional requirements

- C/C++17 compiler, make, autoconf, autoheader and ripgrep (`rg`).
- Python image dependencies from `requirements-import.txt` (recorded versions
  used by the current conversion tools).
- Separately licensed CAPS and Moonstone ACE tools at the pinned revisions in
  [upstream-sources.json](upstream-sources.json); see [THIRD_PARTY.md](../THIRD_PARTY.md).

From the repository root:

```bash
mkdir -p work/upstream reference/original
python3 -m venv work/import-venv
work/import-venv/bin/pip install -r requirements-import.txt
# Activate this environment before running the Python/shell import commands.
source work/import-venv/bin/activate

git clone https://github.com/Jarskih/moonstone-ace-public work/upstream/moonstone-ace
git -C work/upstream/moonstone-ace checkout --detach f0d699a2b92d42d5380429ea9f2d94f7534324ef
git clone https://github.com/FrodeSolheim/capsimg work/upstream/capsimg
git -C work/upstream/capsimg checkout --detach ed4cb0912fb1a2a0d5203111c6f6abd50d411b56
```

Build the pinned CAPS library locally:

```bash
(cd work/upstream/capsimg/CAPSImg && autoconf && autoheader)
(cd work/upstream/capsimg && ./configure && make -j2)
```

Place the three owned IPFs in `reference/original/` under the names below,
then extract into a previously empty destination:

```bash
python3 tools/import_ipf.py   reference/original/Moonstone_DiskA.ipf   reference/original/Moonstone_DiskB.ipf   reference/original/Moonstone_DiskC.ipf   --files-only --out reference/extracted

python3 work/upstream/moonstone-ace/tools/artconv.py export   --disks reference/extracted --out game/assets/classic/recovered

bash tools/import_assets.sh
```

The extractor checks sector/filesystem checksums and file chains and refuses to
overwrite a nonempty destination. `--files-only` permits the supported original
protection track to be omitted from file extraction; it does not create an
archival preservation copy. Originals remain unchanged.

Subsequent converters check hashes and relocated references, resolve finite
animation branches offline, compose the original artwork and render audio using
optional reference helpers. They do not execute those scripts during gameplay.
Source holds and native timing adaptations are not proof of exact Amiga cadence.

Outputs go to local `game/assets/classic/` and `game/content/generated/`.
The final import stage also builds and verifies the separated classic layer
pages and `classic_layered_art.tres`; no manual copying from another checkout
is required for a fresh supported-disk import.
The curated [classic gameplay definitions](gameplay-packs.md) ship combat and
campaign numeric rules in source. Imported combat/campaign tables are local comparison candidates and do not
overwrite those rules; artwork imports cannot silently alter server combat.
Converters may also write ignored trace reports under `docs/` and `work/`;
these are not required by a normally provisioned build. After import:

```bash
bash tools/build.sh --skip-import
```

For development on another computer, provision your compatible native asset set
privately; do not attach it to a public issue or commit it. No cloud asset store
or automatic game-data download is configured.
