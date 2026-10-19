# Architecture

The game is native Godot/GDScript. No Amiga CPU, chipset emulator, original
executable or original-script interpreter runs inside the game. Offline tools
convert supported original data into native resources.

## Layers

| Layer | Location | Responsibility |
| --- | --- | --- |
| Domain | `game/scripts/domain/` | Fixed-tick combat, world rules, progression, validation and transactions |
| Sessions | `game/scripts/session/` | Commands, AI scheduling, campaign flow, saves and local player identity |
| Gameplay policies | `game/scripts/gameplay/` | Small replaceable rules through bounded host interfaces |
| Content | `game/content/`, `game/scripts/content/` | Actor/move definitions, semantic resources, rules and art-pack schemas |
| Presentation | `game/scripts/presentation/` | Screens, input adapters, animation sampling, audio and transient effects |
| Diagnostics | `game/debug/`, `game/tests/` | Explicit development fixtures and automated checks |
| Offline tooling | `tools/` | Import, build, verification and local packaging |

## Deterministic state

CombatSimulation owns a fixed 50-tick clock and authoritative actor/projectile
state. Commands carry an owner, sequence and tick. Positions and guards resolve
before collected hits so simultaneous attacks do not gain actor-order priority.
Collision resources and move clocks are independent of artwork. Balok flight
uses actor-owned integer trajectory/retry state and a versioned content profile;
its aimed distance determines the number of steps. The five-tick flight cadence
is calibrated to reference footage and remains a bounded approximation.

Successful basic slashes retain a five-tick impact drawing before their
fifteen-tick visible follow-through. A held early-contact slash restarts after
31 ticks; misses and other moves retain their clocks. Explicit gameplay content
defines source-derived monster hurt durations and targetability, including the
War Beast's dedicated hurt state. Stagger expiry permits commands before contact
collection on that tick. The three Troggs clear their attack delay on a received
hit; Hammer spacing and recovery share its five-tick attack cadence. These
source-count corrections remain provisional in original wall-clock seconds.
Render poses never decide vulnerability or action readiness.

Ratman floor landings return to decisions after the existing flight; only tree
perching retains its 180-tick wait. A successful ground hit starts a shared
fifteen-step pause, consumed by eligible grounded decisions at the native
six-tick handler cadence. The inclusive five-pixel lane and 40/50-pixel ground
attack choices follow the original rule. Shared wait and actor decision clocks
are explicit versioned state; artwork supplies none of these values.

Black Knights use a bounded original-derived decision policy with encounter-local
seeded randomness, range/defence checks and previous-action memory. Eligible
choices run at a six-tick native cadence; busy attacks and hurt states consume
no decision draws. The unsupported blanket post-attack pause is removed; the
existing entry grace is retained. Both knight kinds finish their matching
thirty-tick protected ordinary hurt sequence before accepting fresh actions.
Special holds, knockback and death paths remain separate. Attack clocks and
classic layers are unchanged. Both source guard choices currently project onto
the existing native guard; separate original guard poses/rules remain provisional.

Sessions coordinate simulation and campaign transactions. Seeded random streams
and explicit state make rewards and gameplay reproducible. Renderers, sounds,
controllers and feedback must not consume gameplay RNG or mutate simulation
state. Presentation history such as pose sampling and blood particles is transient.

## Campaign and saves

JourneySession manages campaign flow. JourneyArchive validates/migrates saves;
JourneyStore writes whole checkpoints atomically with backup recovery. A live
fight resumes at its entrance, while settled loot preserves remaining treasure
and already-earned progress.

LocalParty keeps four stable seats and projects the active character into the
campaign session. Personal inventory, identity and effects stay with their seat;
calendar, quest and shared world state remain common. Rival/view-relative IDs
are translated to stable seats before persistence or targeted transactions.

Current formats are combat25, world3, solo campaign16 and party envelope17.
Preserve existing migrations and validate the whole transaction before mutation.

## Practice

PracticeSession creates a standalone LocalSession with a fixed local seed and
ordinary encounter definitions. It has no JourneySession or save-store reference.
The title keeps its saved checkpoint while the practice picker/fight is active;
world/party updates are suspended. Retry resets the complete fight state, not
just health. Returning to the picker or title performs no campaign settlement.

Practice uses the classic panel arches, bitmap text and layered actor previews.
Those selections and drawings do not alter simulation rules or campaign RNG.
## Network practice duels

DuelConnection uses ENet for one host and one guest. NetworkDuelSession maps
their connection identities to stable actor owners1/2 and steps the ordinary
50-tick Simulation only on the host. There is no AI takeover. Clients send bounded
sequence-numbered held input, never positions, damage, actor IDs or outcomes.
The host schedules both seats three ticks after receipt. Held intent expires
after ten more ticks without replacement. Late/duplicate/previous-round inputs
are rejected without weakening CombatSimulation.submit's tick/owner checks.

Compressed control, round results and periodic checkpoints use a reliable ordered
channel. Current full-state frames and held input use separate unreliable ordered
channels, so retrying an old frame cannot block the current position. Decompression is bounded
to64KiB and object/resource decoding is disabled. DuelReplica is a detached
read model with no command/step API. Each accepted frame carries the complete
combat snapshot plus that tick's feedback; rendering/audio consume those values.
Skipped state packets may skip transient feedback; animation phases continue
from authoritative clocks. State hashes validate transfer, not remote authentication. Local menus neutralise
input while the host clock continues. Both players must ready before play and
agree to rematch. Disconnect or prolonged stale state stops the match; rejoining
starts a new match. There is no live reconnection or host migration.

The build fingerprints the static combat-code/rule dependency closure, including
collision and timing resources but excluding images/audio/presentation code.
Editor play checks for stale source hashes. Generate the compatibility file with
`python3 tools/network_fingerprint.py` after gameplay edits; normal builds do
this before importing/exporting. Mismatched peers are rejected before play.
Combat/save schemas and ordinary campaign sessions are unchanged.

## Gameplay extension points

Trusted GDScript policy interfaces currently cover encounter scaling, entry
placement and a bounded hold interaction. Hosts supply copied facts and validate
commands/results before changing authoritative state. This is not a public mod
loader or sandbox.

Future scripts need supplied simulation ticks/RNG, explicit serializable state,
stable IDs, API/pack versions, deterministic load order, save migrations and
multiplayer fingerprints. Engine services retain validation, persistence and
future network authority; policies/content define gameplay choices.

## Rendering and input

The current renderer consumes a detached actor view with named actions/phases,
effective equipment and colour identity. Logical dimensions and anchors are
independent of texture resolution. Classic combat uses reusable body, colour
and gore/clean pieces; see [art packs](art-packs.md). HD sprites and future 3D actors must consume the
same authoritative state and must not drive damage through root motion or
animation callbacks.

Controller/keyboard/mouse adapters produce the same commands. Device IDs are
transient; saved choices use logical ports. Controller remapping is presentation
configuration rather than gameplay state.

## Diagnostics

Development shortcuts require the explicit `--debug` game flag. Normal play
filters their arguments and actions. Debug sessions keep save/preferences in
memory and do not overwrite normal progress. Diagnostic modules load lazily;
tests are excluded from player exports. See [development](development.md) for
validation levels and commands.
