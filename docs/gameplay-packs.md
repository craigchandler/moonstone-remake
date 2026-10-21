# Gameplay packs

The built-in **Classic combat** pack is the first gameplay module. It is the
starting point for treating the base game as a mod: readable data plus trusted
GDScript policies, running through the shared deterministic simulation. Its
current scope is combat, including every existing creature and both knight
kinds. Campaign content is not yet collected into a pack.

## Files and identity

| File | Purpose |
| --- | --- |
| `game/content/packs/classic/manifest.tres` | Stable pack ID, pack version, API version, scope and dependencies |
| `game/content/packs/classic/combat.gd` | Actor/policy references, move clocks, damage defaults and encounter definitions |
| `game/content/packs/classic/tables/*.tres` | Reviewed numeric contacts, recovery, death, knockback, Guardian and entry rules |
| `game/content/actors/*.tres` | Shared editable actor definitions used by the classic pack |
| `game/content/behaviors/*.tres` | Configured policy resources used by the classic pack |
| `game/scripts/content/` | Typed resource schemas and existing rule implementations |
| `game/scripts/gameplay/` | Bounded policy interfaces and their native implementations |

`content/foundation_rules.tres` selects the built-in rules. The historical
`CombatRules` class remains a compatibility entry point that inherits the pack;
existing callers and saved content IDs are preserved. The pack uses shared
catalogue resources rather than copying actor definitions into multiple places.

Pack ID `moonstone:classic-combat`, pack version `1.0.0` and API version `1` are
separate from the game version, server version and wire protocol. The manifest
and all statically referenced code/data are included in the network fingerprint.
A version label is not a substitute for that fingerprint. Changing a rule,
script or manifest requires compatible clients and servers to be rebuilt.

## Reading the numbers

The text resources can be edited in Godot's inspector or a text editor. Existing
values and provisional timing comments are retained in the classic pack.

- Combat runs at 50 ticks per second. Move `windup`, `active` and `recovery`
  fields are simulation durations; presentation does not determine these clocks.
- Contact tables map semantic move IDs to ordered frames. A frame has `points`
  and a positive relative `weight`. Points use the actor's logical foot origin,
  with positive X facing right and negative Y above the foot; simulation mirrors
  the horizontal offset when facing left. Weights select contact drawings within
  an active phase; they are not additional damage events or seconds.
- Actor definitions specify health, permitted moves, logical hurt boxes and AI
  settings. Damage can also depend on existing equipment and encounter policies.
- Recovery and death tables map actor/clip IDs to authoritative clocks. The
  `classic_hit_recovery.tres` overrides remain separate from the recovered base.
- Entry placement and scaling policies consume plain facts. Their host owns
  persistent counters, positions and seeded random state.

The campaign subdirectory contains curated map-travel, loot and quest resources
and the existing69-tick town dice clock. These let the same native campaign run
on an asset-free server. They are included in its separate campaign fingerprint;
combat pack identity and historical saved content IDs are unchanged.

The sixteen combat source tables were promoted from the reviewed local numeric inputs.
Their values are unchanged. They contain no images, sound, fonts, original
archives or interpreter bytecode. Original-derived numbers retain the attribution
and ownership boundaries described in [THIRD_PARTY](../THIRD_PARTY.md).

## Script extension boundaries

The existing `entry_placement.gd`, `encounter_scaling.gd` and
`hold_behavior.gd` interfaces are the first bounded script hooks. Their classic
implementations use configured Resource properties and copied facts, returning
choices which the host validates. For example, an entry-placement implementation
extends `scripts/gameplay/entry_placement.gd` and implements
`decide(facts: Dictionary) -> Dictionary`; the classic resource configures its
stable behavior ID, API/content versions and numeric properties.

For a source-level experiment, copy the classic pack to a new directory, give it
a new stable ID, update its static resource references, and select its rules
through the foundation resource. Keep actor, move and behavior IDs stable where
save compatibility is intended. Declare migrations before changing persisted
state or IDs. Run deterministic and network tests before using another build.

Scripts are trusted application code. There is currently no runtime mod picker,
automatic dependency loader, public stable mod API or script sandbox. Arbitrary
GDScript is not made safe by a manifest. New hooks must receive simulation ticks
and the supplied seeded RNG, keep serializable explicit state, and avoid wall
clocks, global random calls, filesystem/network side effects and presentation
callbacks in authoritative decisions. Dynamically loaded scripts need explicit
fingerprint/dependency support before multiplayer use.

## Imports, art and releases

Offline importers continue writing ignored candidates to
`game/content/generated/`. They do not overwrite the curated source tables.
Review a candidate's numeric differences and regression results before deliberately
updating a source pack. A later art import cannot silently change server combat.
The full classic game still requires local generated presentation resources
and artwork/audio; see [importing](importing.md).

Artwork/audio packs remain separate and local. The dedicated server needs the
combat/campaign numeric definitions and shared code only. Its [release workflow](server-guide.md#server-releases)
builds without original disks, art, audio or writable caches from a game checkout.
