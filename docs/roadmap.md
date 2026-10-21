# Roadmap

The game is a playable native classic-style reconstruction, still requiring
fidelity and platform playtesting. Current capabilities and future work are
set out below.

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
rematches, plus an optional standalone command-line host for two game clients.
The same independent host core runs inside the game. Host-only combat authority
and detached client state preserve the classic rules. Two-process loopback/fault tests are distinct from real LAN,
internet, Windows and manual playtesting.

## Classic network campaign

Classic sequential campaigns support up to four humans, with computer knights
in the other seats. Both standalone and embedded game hosting use the same
campaign authority. Waiting players watch the active turn and may browse their
own inventory. Disconnect pauses play and reserves the missing player's knight.
All humans agree before resuming. Separate host saves preserve normal solo/local
progress. Live battle reconnect and safe recovery after a host restart are
different contracts; see [the architecture](architecture.md#network-campaign).

Further validation includes sustained human playthroughs, separate-machine LAN,
Internet conditions and Windows execution. Scripted local UDP/fault checks do
not establish those results or complete original-game parity.

A simultaneous campaign follows as a separate mode with explicit encounter,
location-conflict and calendar policies. Optional invites/voice, Internet
connection services and multiple server rooms can be added around the same core.

## Subsequent work

- Resolve concrete playtest defects and extend manual Linux playthroughs, real
  Windows execution, controller checks and original-game comparisons.
- Extend the enhanced art pipeline after a small playable comparison succeeds.
- Expand bounded script/content interfaces with versioning and save migration;
  then design a public mod API/loader with explicit trust boundaries.
- Validate network practice and campaigns on separate machines/platforms before
  cooperative networking or internet services, preserving stable
  identities, determinism and content fingerprints.

Sequence and scope may change with testing. New rendering should not force a
rules rewrite, and planned network/mod capabilities do not exist merely because
current state and content are structured for them.
