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
Collision resources and move clocks are independent of artwork.

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

Current formats are combat22, world3, solo campaign16 and party envelope17.
Preserve existing migrations and validate the whole transaction before mutation.

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

The current renderer draws classic 2D atlases using named actions and phases.
Some drawing and picking still derive dimensions from texture pixels. The next
renderer pass will introduce explicit logical bounds and a semantic actor view;
see [art packs](art-packs.md). HD sprites and future 3D actors must consume the
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
