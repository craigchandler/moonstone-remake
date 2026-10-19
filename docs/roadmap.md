# Roadmap

The baseline is a playable native classic-style reconstruction, still requiring
fidelity and platform playtesting. Planned capabilities below are not claims of
implemented features.

## Current graphics foundation

Logical dimensions, anchors and cursor picking are independent of image
resolution. The classic renderer consumes a detached actor/animation/equipment
view and shared body, colour-mask and gore/clean sprite pieces. Enhanced artwork
and playable HD/3D rendering remain future work.
See [art packs](art-packs.md) for the contract and acceptance requirements.

The initial graphics pass preserves combat timing, collision, damage,
progression and controller mapping. Enhanced artwork and future 3D character
scenes must share the existing rules. New original assets require recorded
provenance and their own publication decision.

## Network practice

Practice supports direct host/join knight duels, shared readiness and agreed
rematches. Host-only combat authority and detached client state preserve the
classic rules. Two-process loopback/fault tests are distinct from real LAN,
internet, Windows and manual playtesting.

## Subsequent work

- Resolve concrete playtest defects and verify graphical Linux/real Windows
  behavior, controllers and remaining original-game differences.
- Extend the enhanced art pipeline after a small playable comparison succeeds.
- Expand bounded script/content interfaces with versioning and save migration;
  then design a public mod API/loader with explicit trust boundaries.
- Validate network practice on separate machines/platforms before adding
  campaign/cooperative networking or internet services, preserving stable
  identities, determinism and content fingerprints.

Sequence and scope may change with testing. New rendering should not force a
rules rewrite, and planned network/mod capabilities do not exist merely because
current state and content are structured for them.
