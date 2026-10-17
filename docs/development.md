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

The baseline has 66 Godot suites and dependency-free Python tool tests. The
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
entry points, not advertised normal game controls.

## Repository hygiene

Public documentation and active build/import tools are selected by `.gitignore`.
Historical research, local continuation notes and blog material remain outside
the committed tree. Run `tools/check_public_tree.py` on the staged index before
committing; use `--ref HEAD --history` before preparing public publication.
