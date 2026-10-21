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

DuelHost owns one ENet room, stable seats 1/2 and NetworkDuelSession authority.
DuelHostRunner advances the ordinary 50-tick Simulation independently of screens,
including while local menus are open. Every player uses DuelConnection and a
DuelReplica without command/step authority. In-game hosting starts the same
runner plus a loopback client reserved for seat 1. The command-line host has two
remote clients and occupies neither seat. No presentation node steps the host.

Clients send bounded sequence-numbered held input, never positions, damage,
actor IDs or outcomes. The host schedules both seats three ticks after receipt;
this is a common buffer, not latency compensation. Held intent expires after ten
more ticks without replacement. Late/duplicate/previous-round inputs are rejected
without weakening CombatSimulation.submit's tick/owner checks. There is no AI
takeover. Combat and campaign/save schemas are unchanged.

Compressed control, round results and periodic checkpoints use a reliable ordered
channel. Current full-state frames and held input use separate unreliable ordered
channels, so retrying an old frame cannot block the current position. Decompression is bounded
to 64 KiB and object/resource decoding is disabled. DuelReplica is a detached
read model with no command/step API. Each accepted frame carries the complete
combat snapshot plus that tick's feedback; rendering/audio consume those values.
Skipped state packets may skip transient feedback; animation phases continue
from authoritative clocks. State hashes validate transfer, not remote authentication. Local menus neutralise
input while the host clock continues. Both players must ready before play and
agree to rematch. Disconnect or prolonged stale state stops the match. The
standalone host clears players, input and combat/RNG state. After a brief
notification grace, a fresh ENet listener on the same port replaces the retired
transport and accepts a fresh pair. This releases absent peers and avoids
Godot 4.6.1 per-peer cleanup during the next match. In-game hosting stops its runner when
its local client leaves. Rejoining starts a new match; live reconnection, host
migration and simultaneous rooms remain future work.

The build fingerprints the static combat-code/rule dependency closure, including
collision and timing resources but excluding images/audio/presentation code.
Editor play checks for stale source hashes. Generate the compatibility file with
`python3 tools/network_fingerprint.py` after gameplay edits; normal builds do
this before importing/exporting. Mismatched peers are rejected before play.
Protocol 2 rejects older client/server builds. The standalone export stages the
same code and numeric rules into a minimal project with its own import cache,
no client autoloads and no artwork/audio. Its entry point parses the mode/settings, selects the shared duel or campaign
runner and logs lifecycle events. See [hosting](server-guide.md).

## Network campaign

Classic campaigns use four stable knight seats, with one to four humans and
computer knights in the remaining seats. `CampaignSession` owns the existing
`JourneySession`/`LocalParty` policies and schedules map travel, computer turns,
monster/human battles, towns, quest scenes and ending clocks at 50 Hz. The same
`CampaignHostRunner` runs in the game and the standalone server. The embedded
host's player connects through the ordinary client path and occupies one seat;
a standalone server occupies none.

Computer knights retain the existing world behavior: off-screen lair visits use
world logic rather than hidden monster simulations. Encounter policies, combat
rules, seeded streams and save migrations are shared with local play. Human
knight encounters require both participants ready, and each controls their own
fighter even when defending outside their map turn.

`CampaignProjection` produces detached live read models, separate from disk
checkpoints. They expose the active screen and the requesting seat's inventory.
Unrevealed pre-rolled treasure, campaign random streams and private reconnect
credentials stay on the host. Rival possessions are supplied to the active
knight when an Acquisition scroll needs its existing object-selection UI.
Classic network panels submit commands through a replica adapter. Waiting
players watch the active screen and browse their own inventory read-only;
browsing does not pause the host. Rendering never advances campaign policy.

Campaign protocol 1 uses direct Godot 4.6.1 ENet connections. Clients must match the
campaign source/content fingerprint. Reliable sequenced commands and replies
carry purchases, loot and turn transitions; stale epochs, duplicate transactions
and incorrect seat ownership are rejected. Map frames use a separate channel at
25 Hz, combat frames at 50 Hz and held input a separate channel with a one-tick
receipt buffer and ten-tick expiry. Shared frames are compressed once per host
update. Recent feedback IDs avoid duplicate hit effects after packet loss.

Client movement forecasting is limited to eight unacknowledged idle inputs and
changes presentation positions only. Remote positions receive bounded smoothing.
Confirmed combat ticks, attacks, collision, damage and random decisions remain
host-owned. This is not attack rollback or a claim of unnoticeable high latency.
Tests distinguish local UDP with injected faults from separate-PC/internet play.
See [Godot's channel documentation](https://docs.godotengine.org/en/4.6/tutorials/networking/high_level_multiplayer.html#channels).

A stalled connection pauses after 1.5 seconds; confirmed disconnection reserves
the knight and requires all humans to rejoin and choose Ready. Godot 4.6.1 native
transport recovery reopens the listener while retaining the logical campaign,
including exact live battle state. Old held input is cleared. Private client
credentials are stored locally by room; the host saves only their hashes.

Network campaigns use a separate checksummed host envelope with backup/atomic
replacement and the existing schema 17 safe checkpoint. It is saved on commands,
phase changes, pause/close and every two seconds on the map. Solo/local saves
remain separate. Live reconnect resumes an exact paused fight while the host
survives. Restarting the host process follows existing disk semantics: an
unfinished fight resumes at its entrance. It is not an exact combat save.

Each host runs one campaign or one practice-duel room. Simultaneous campaigns
need a separate scheduler and mode identity, with encounter ownership, contested
locations and calendar policies. Multiple rooms, host migration, directories,
relays and optional platform invites are later work. Connection data remains
independent of any platform; an optional invite layer can reuse it.

## Gameplay extension points

The first built-in [gameplay pack](gameplay-packs.md) contains classic combat
defaults and reviewed numeric tables. Its manifest and static references are
fingerprinted. The legacy CombatRules class remains a compatibility wrapper,
and saved content IDs and combat values are preserved. Actor/policy resources
remain a shared catalogue. The curated campaign tables extend the same source content directory; runtime
mod loading remains later work.

Trusted GDScript policy interfaces currently cover encounter scaling, entry
placement and a bounded hold interaction. Hosts supply copied facts and validate
commands/results before changing authoritative state. This is not a public mod
loader or sandbox.

Future scripts need supplied simulation ticks/RNG, explicit serializable state,
stable IDs, API/pack versions, deterministic load order, save migrations and
multiplayer fingerprints. Engine services retain validation, persistence and
network authority; policies/content define gameplay choices.

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
filters their arguments and actions. Solo/local debug sessions keep save/preferences in memory and do not overwrite
normal progress. Network client profile persistence/resume is disabled in debug
mode, and network fixtures use isolated user-data directories. Diagnostic modules load lazily;
tests are excluded from player exports. See [development](development.md) for
validation levels and commands.
