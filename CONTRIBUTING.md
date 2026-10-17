# Contributing

This is an unofficial game reconstruction under active development. Small,
focused changes are easier to verify than simultaneous gameplay and renderer
rewrites. Discuss large features before implementing them.

## Local setup

Follow [development](docs/development.md). The public checkout excludes original
assets. Contributors with a compatible local asset set can run the Godot suites;
without assets, Python build/publication tests remain available.

```bash
python3 -m unittest discover -s tools/tests
bash tools/build.sh --skip-import --tests-only
```

The second command requires provisioned assets and the matching Godot editor.
Do not claim a game test passed when only the Python checks ran.

## Changes

- Keep game rules deterministic and independent of textures, sound and rendering.
- Maintain stable content IDs and existing save migrations. Use semantic actor
  actions and presentation events rather than image frame numbers in gameplay.
- Test meaningful behavior, particularly saves, commands and renderer isolation.
- Report which platforms and validation levels actually ran.
- Do not commit original/recovered assets, footage, packages, credentials,
  personal notes, upstream checkouts or machine-specific configuration.

Public documentation and tools are intentionally selected in `.gitignore`.
Explicitly add a suitable allowlist entry when adding a new public document or
build tool. Keep research reports and blog source material local.

Before committing:

```bash
git diff --check
python3 tools/check_public_tree.py
```

The publication check reads staged Git objects, including objects deleted or
modified in the working tree. After committing, `--ref HEAD` checks that commit;
`--history` additionally checks every commit reachable from that reference.

New contributions use the repository’s MIT licence; include attribution for any
separately licensed material and do not relicense someone else’s work. Read
[THIRD_PARTY.md](THIRD_PARTY.md) and [asset policy](docs/asset-policy.md).
