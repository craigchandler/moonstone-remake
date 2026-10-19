# Development and validation

## Requirements

The current build runs on Linux and exports Linux/Windows x86_64 players.

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

The classic gameplay build has 81 Godot suites and dependency-free Python tool tests. The
repeatable exported Linux acceptance covers input/debug guards, save/backup
continuation, local-party flow, standalone startup and retained combat traces.
Source checks, headless exported execution, graphical Linux playtests, physical
controllers, Windows runtime and matched original-game comparisons are distinct
results. State exactly which ran; passing one does not prove the others.

## Diagnostics

Normal play saves progress. Development shortcuts require `--debug` after the
engine argument separator; packaged launchers add that separator themselves:

```bash
./Moonstone.sh --debug
./Moonstone-<build>-linux.x86_64 -- --debug
```

Debug sessions do not create/replace progress, backups, temporary saves or
preferences. Their checkpoints remain process-local. An editor/debug executable
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
A loopback UDP proxy adds40-48ms each way and drops every257th datagram. These
are same-machine network checks, not two-machine LAN or internet validation.
Use `tools/verify_network.py --binary <player>` to repeat them. The guarded
`--network-role` diagnostic drives ordinary UI/inputs and never writes progress.
Graphical captures require a display and remain separate from headless checks.

Additional real-socket regressions cover cancellation/retry, an unavailable host,
a silent handshake, a stalled ready screen, protocol/build rejection and malformed
headers. The optional `--profile stress` proxy adds100-140ms each way, drops every
17th datagram and interrupts traffic for0.8 seconds after six seconds. Use
`--rounds 6` with a current source build (or `--editor` and a Godot editor binary)
for a longer sequence of alternating wins and agreed rematches. Defaults retain
the shorter standard build acceptance. These simulated faults do not establish
internet suitability or replace separate-computer playtesting.

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
