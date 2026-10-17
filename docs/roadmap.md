# Roadmap

The baseline is a playable native classic-style reconstruction, still requiring
fidelity and platform playtesting. Planned capabilities below are not claims of
implemented features.

## Next: graphics foundation

Work on a separate graphics branch. First decouple logical dimensions/anchors
and cursor picking from image resolution. Define a semantic actor/animation/
equipment view and make the classic renderer consume it. Prove unchanged combat
traces, state and save behavior before adding an enhanced knight prototype.
See [art packs](art-packs.md) for the contract and acceptance requirements.

The initial graphics pass preserves combat timing, collision, damage,
progression and controller mapping. Enhanced artwork and future 3D character
scenes must share the existing rules. New original assets require recorded
provenance and their own publication decision.

## Subsequent work

- Resolve concrete playtest defects and verify graphical Linux/real Windows
  behavior, controllers and remaining original-game differences.
- Extend the enhanced art pipeline after a small playable comparison succeeds.
- Expand bounded script/content interfaces with versioning and save migration;
  then design a public mod API/loader with explicit trust boundaries.
- Add human cooperative encounters and later competitive/cooperative internet
  sessions, preserving stable identities, determinism and content fingerprints.

Sequence and scope may change with testing. New rendering should not force a
rules rewrite, and planned network/mod capabilities do not exist merely because
current state and content are structured for them.
