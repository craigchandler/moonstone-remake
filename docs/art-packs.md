# Artwork and rendering

Artwork illustrates game state; it does not define game rules. The classic
resources are a separate local pack so enhanced visuals can share the same
mechanics and saves.

## Current resources

MoonstoneArtPack maps stable actor IDs to textures/animation sets, logical sizes,
encounter backgrounds, projectiles and transient effects. Animation sets contain
anchored poses, named clips and phase/hold metadata. ActorAnimator selects poses
from authoritative actions, phases and elapsed clocks.

Map, inventory, towns and cinematic screens have separate content resources.
Equipment item IDs and effective weapon/armour come from progression rules.
Gore selection changes presentation, including composite deaths and hit effects.
It does not change damage or outcomes.

Classic conversion outputs belong under `game/assets/classic/` and
`game/content/generated/`. Enhanced local assets belong under
`game/assets/modern/`. Neither directory’s artwork is published by default;
see [asset policy](asset-policy.md).

## Next graphics milestone

This is the implementation plan, not an already available HD/3D renderer.

1. Give screen artwork and icons explicit logical dimensions, draw rectangles,
   anchors and picking regions. Replacing an image with a larger texture must
   not alter apparent size, layout or cursor targets.
2. Introduce a presentation view of actors: stable ID, ground position, vertical
   height, facing, semantic action/stage, elapsed/duration, colour identity,
   effective armour/weapon and gore preference. Preserve named presentation events.
3. Adapt classic drawing to that view and an interchangeable renderer boundary.
   Retain complex tree/hold/execution/death compositions and final remains.
4. Check unchanged combat traces, state and saves, plus equivalent classic
   placement/picking. Only then prototype one enhanced knight before producing
   a complete art set.

A future 3D renderer can map ground position and height to a scene with an
orthographic camera initially. Animation must follow the authoritative clock;
root motion, skeletons, shaders and frame callbacks have no gameplay authority.

## Equipment and animation requirements

Armour is a complete appearance: headwear, torso, hands, legs and footwear.
The existing armour item selects the outfit; extra equipment slots are not
implied. Keep knight colour visible across all armour tiers. Sword appearance
must follow the effective weapon, including carried-item overrides.

Use shared foot anchors and explicit hand sockets/draw order for equipment.
Prefer reusable weapon/armour layers over every baked combination. Any initial
prototype must cover idle, walking/turning, ordinary/overhead/reverse/upward
strikes, lunge, dagger throw, hurt, holds, executions and death, including gore
and clean variants. A painted concept is not an animation-ready asset or rig.

The graphics milestone does not change simulation timing, collision, damage,
progression, save formats, controller mapping or multiplayer behavior.
