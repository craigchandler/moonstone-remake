# Development and validation

## Requirements

The public [release workflow](releases.md#building-and-releasing-from-source)
builds Linux/Windows x86_64 and PortMaster ARM64 packages from public source
without original assets. Their setup/import tools generate a separate portable
`content/` directory on the player's machine. The `v*` pipeline also produces
lightweight asset-free Linux/Windows servers.

The older private development/export workflow below runs on Linux and embeds
locally provisioned assets in Linux/Windows players.

- Godot **4.6.1** and matching Linux/Windows export templates.
- Python **3.11+**, Bash and Git for source checks/build/package tools.
- Locally provisioned `game/assets/classic/` and `game/content/generated/`.

`GODOT_BIN` may name an editor installed anywhere; the fallback is
`work/godot-4.6.1/Godot_v4.6.1-stable_linux.x86_64`, then `godot` on PATH.
The build rejects a different version. Set `GODOT_TEMPLATES_DIR` if matching
standard templates are outside the usual Godot data directory. Presets contain
no developer-specific paths.

Players of a locally built package do not need Godot, Python, import tools,
original disk images or an internet connection. Platform graphics/audio/system
libraries still apply. Actual Windows runtime testing is separate from export.

## Assets

This public checkout is intentionally not runnable on its own. Provision an
existing compatible native asset set into the two paths above, or follow
[importing](importing.md). With native assets provisioned, normal tests/exports
need no original disk images, original executables, upstream checkout or old
review artifacts. Modern concept images alone cannot replace the required
classic packs yet.

The native set now includes `content/generated/classic_layered_art.tres` and
`assets/classic/layered/`. To convert an older provisioned set, install the image
dependencies from `requirements-import.txt`, then run:

```bash
python3 tools/import_classic_layers.py
```

This conversion needs native sprites and class variants, not disk images or
original executable data. It preserves its inputs and reports exhaustive pixel
comparisons in the local layered pack's `provenance.json`.

## Commands

Without game assets:

```bash
python3 -m unittest discover -s tools/tests
python3 tools/check_public_tree.py --ref HEAD --history
```

With native assets and Godot:

```bash
bash tools/build.sh --skip-import --tests-only
bash tools/build.sh --skip-import
```

The full build creates an isolated `work/build-*` directory, imports Godot
resources, discovers `game/tests/test_*.gd`, runs Python build contracts, exports
both targets, generates engine notices, verifies the Linux executable and makes
local ZIPs/checksums. Godot data/config/cache stay isolated from player settings.
Build identity and platform presets are in `tools/build-config.json`.

Optional individual stages:

```bash
python3 tools/verify_build.py
python3 tools/package_builds.py
```

These require a matching successful build manifest. Stale executables, failed
acceptance and mismatched reports reject packaging. `--export-only` skips tests
and acceptance and cannot establish a verified player package. Omit
`--skip-import` only when deliberately checking/converting local original data;
see the import guide for its additional tools and licences.

## Evidence

External-content release validation (2026-10-23) includes 95 Python tests,
workflow lint, a build from an audited source copy without original assets,
native Linux packaged setup/conversion/transfer checks, and Windows equivalents
under Wine. Full disk conversions passed 26,364 pixel comparisons on both,
followed by exported game startup checks. Content generated on either desktop
loaded on the other. The PortMaster x86 runtime loaded the same content and
verified a copied pack before unpacking Python. Windows cancellation preserved
the active content. These checks do not establish native Windows or ARM execution
of the new release packages; CI includes a separate native Windows acceptance
job. The hosted tag workflow has not yet run. The previously verified RG40XX H
2:08 import remains a separate hardware baseline.


The gameplay baseline validation (2026-10-21) passed **86 Godot suites and 37 Python
tool tests**. Exported Linux checks cover input/debug guards, save/backup
continuation, local-party flow, standalone startup and retained combat traces.

Both campaign hosting paths have also passed with two independent exported game
clients on local UDP: in-game host and standalone server. Scripted graphical
Linux checks exercised towns, computer turns, monster combat, personal inventory,
pause/reconnect and turn handoff; the standalone run injected 40–48 ms each-way
delay and packet loss into both client connections. Separately, four asset-free
campaign clients verified the exported server and saved-room process restart.
The complete asset-free server release build passed from an audited source copy.

Native Windows execution, separate-machine campaign
LAN, Internet hosting, physical controllers, manual full-campaign playthroughs,
running-original comparisons and the hosted GitHub release workflow remain
unverified. Source checks, exported headless execution, scripted graphical
checks and human playtesting are different evidence; report which ran.

## Diagnostics

Normal play saves progress. Development shortcuts require `--debug` after the
engine argument separator; packaged launchers add that separator themselves:

```bash
./Moonstone.sh --debug
./Moonstone-<build>-linux.x86_64 -- --debug
```

Solo/local debug sessions do not create/replace their normal progress, backups,
temporary saves or preferences. Their checkpoints remain process-local. Network
client profile persistence/resume is disabled in debug mode; campaign network
fixtures use isolated user-data directories under `work/`. An editor/debug executable
alone does not enable the shortcuts. Diagnostic fixtures are explicit developer
entry points, not advertised normal game controls. The guarded `--recovery-roster`
diagnostic checks held basic slashes against all eleven original monsters at
five distances in both facings, with deterministic replay and layer isolation.
It is a bounded combat check, not proof of original-game balance parity.
The guarded `--ratman-ground-batch` fixture separately covers an idle knight
after an evaded tree-to-ground flight, both facings, the retained perch wait
and prompt melee resumption. Source regressions also check the original caster
decisions and shared successful-hit pause.

The guarded `--practice-probe` exercises the normal title-to-practice UI,
all twelve fights, knight colours, keyboard/mouse/controller selections,
deterministic retries, result handling and solo/party campaign isolation.
Linux exported acceptance repeats it with absent and protected existing save
files. Injected input checks do not establish physical controller coverage.

Network suites separately cover authority, input delay/expiry, native death
states, validated replicas, actual ENet peers and normal classic UI flow. Exported
Linux acceptance launches two independent players for two real combat rounds and
a rematch, then checks graceful leave and abrupt loss of either host or client.
A loopback UDP proxy adds 40–48 ms each way and drops every 257th datagram. These
are same-machine network checks, not two-machine LAN or internet validation.
Use `tools/verify_network.py --binary <player>` to repeat them. The guarded
`--network-role` diagnostic drives ordinary UI/inputs and never writes progress.
Graphical captures require a display and remain separate from headless checks.

Additional real-socket regressions cover cancellation/retry, an unavailable host,
a silent handshake, a stalled ready screen, protocol/build rejection and malformed
headers. The optional `--profile stress` proxy adds 100–140 ms each way, drops every
17th datagram and interrupts traffic for 0.8 seconds after six seconds. Use
`--rounds 6` with a current source build (or `--editor` and a Godot editor binary)
for a longer sequence of alternating wins and agreed rematches. Defaults retain
the shorter standard build acceptance. These simulated faults do not establish
internet suitability or replace separate-computer playtesting.

Campaign source suites cover 1–4 humans, classic turns, all creature snapshots,
human duels, per-seat commands, duplicate loot, hidden rewards/RNG, rendering
isolation, separate inventory, town/wizard panels, private room history and
corrupt-save recovery. `tools/verify_campaign.py <player> --server <server>`
launches two independent game clients against a standalone host. Omit `--server`
to exercise embedded hosting. `--graphical` captures GPU-rendered screens;
`--fault` adds 40–48 ms each-way delay and deterministic datagram loss to both
standalone clients, or to the joining client with an embedded host.

Repeat campaign checks after building the game and, for the second command,
the standalone server:

```bash
python3 tools/verify_campaign.py outputs/Moonstone-Network-Campaign-linux.x86_64
python3 tools/verify_campaign.py outputs/Moonstone-Network-Campaign-linux.x86_64 --server outputs/Moonstone-Duel-Server-linux.x86_64 --graphical --fault
```

`--graphical` requires a working X11 display. The guarded `--campaign-role`
fixture drives ordinary menus, client requests and injected controls through
map travel, a town purchase, computer turns, monster combat, spectator inventory,
pause/reconnect and turn handoff. There are no diagnostic commands on the server.

## Repository hygiene

Public documentation and active build/import tools are selected by `.gitignore`.
Historical research, local continuation notes and blog material remain outside
the committed tree. Run `tools/check_public_tree.py` on the staged index before
committing; use `--ref HEAD --history` before preparing public publication.

The guarded `--knight-rhythm-batch` diagnostic compares seeded Black Knight
fights and complete player recovery in both facings. Its source suite also
checks numeric expectations from independent execution of the owned original
knight decision routine. The original binary, disassembler and research stay
local; runtime uses only native policies and numeric definitions.

## PortMaster

For local RG40XX H / muOS packages, see the [PortMaster guide](portmaster.md).
The external-assets variant separates code from an accepted desktop export and
bundles a standalone original-data importer. Desktop import, external-content
runtime checks and handheld execution remain separate evidence. The older private
package with embedded assets is retained as a baseline.

## Standalone server

The [server setup guide](server-guide.md#build-the-server-from-source) gives a
complete source-only build with pinned toolchain installation. It does not need
a game client or original assets. For extra checks against real game clients,
build the game normally, then use:

```bash
python3 tools/verify_server.py --server outputs/Moonstone-Duel-Server-linux.x86_64 --client outputs/Moonstone-Network-Campaign-linux.x86_64 --output work/server-acceptance
```

This command checks practice duels. Use `tools/verify_campaign.py` as above for
graphical campaign clients; the asset-free release procedure checks both modes.

The server builder stages the shared dependency closure into a fresh project
under `work/server-build-*`, retaining the exact compatibility manifest. It
copies code and numeric rules only, with no artwork, audio, client autoloads or
shared writable cache. Dedicated exports and matching engine notices are local.
See [Godot's dedicated-server export documentation](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_dedicated_servers.html).

Three-process Linux acceptance checks two ordinary clients, real combat wins
in both directions, agreed rematches, sequential reuse of the same server,
100–140ms each-way delay/loss/interruption, client loss and server loss. Both
clients' terminal hashes must match the server. CLI checks cover help, invalid
arguments, display-free startup and Ctrl+C. Graphical captures, separate-computer
LAN play, physical controllers and Windows execution remain distinct evidence.
The earlier user-reported LAN duel test applies to the prior in-game host build;
this refactor needs a fresh real-LAN playtest. See the [server guide](server-guide.md).


## Asset-free server release checks

The [classic combat pack](gameplay-packs.md) supplies the source numeric rules,
so a clean checkout can build the dedicated host without importing original
assets. With Godot 4.6.1 and matching templates configured using the
[server build steps](server-guide.md#build-the-server-from-source), run:

```bash
python3 tools/server_release.py --tag server-v0.1.0
```

The tag must match `game/server/version.json`. This command creates local
versioned server ZIPs and checksums; it does not publish. It runs the shared
network/host suites in an isolated minimal project, exercises the real Linux
server with two art-free duel clients, checks real hits and rematches,
compares terminal snapshots with server logs, and verifies fresh room reuse.
It also runs four campaign clients through classic turns, map agreement, personal
inventory, pause/reserved-seat reconnect and process restart from a saved room.
These clients do not run the game's presentation or player-input adapters.
Full game export acceptance, graphical playtesting, Windows execution and
separate-machine LAN validation remain separate. See [server releases](server-guide.md#server-releases)
for the tag-triggered GitHub workflow and the independent version stream.
