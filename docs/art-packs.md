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
It does not change damage or outcomes. The playable classic renderer consumes
a detached CombatFrame; it does not receive mutable simulation objects.

Classic conversion outputs belong under `game/assets/classic/` and
`game/content/generated/`. Enhanced local assets belong under
`game/assets/modern/`. Neither directory’s artwork is published by default;
see [asset policy](asset-policy.md).

## Layered classic combat

Normal combat uses `content/generated/classic_layered_art.tres`. Its animation
sets retain the original logical pose bounds, anchors, clip indices and holds.
Each set references a MoonstoneSpriteLayers resource containing:

- Shared body pieces with fixed colours and shading.
- Neutral colour-mask pieces modulated by the knight identity's palette shades.
- Separate gore and clean replacement pieces where the drawing differs.

Pieces are trimmed, deduplicated and packed into pages no larger than 2048 by
2048. Their drawing offsets and sizes are explicit logical units. Colour masks
use ordinary transparent textures and CanvasItem colour modulation: there is no
per-frame image recolouring or full-colour texture generation. Fixed monster
colours and the purple rival remain independent of the player's chosen colour.

Blood bursts are separate presentation effects. Decapitation and other changes
to body shape retain replacement artwork; switching gore off is not a universal
red-pixel deletion. UI and cinematics keep their existing resources.

`tools/import_classic_layers.py` reads provisioned native atlases and their exact
class variants. It writes a new local pack without changing those inputs. Every
converted pose, colour and gore/clean combination is compared pixel-for-pixel
with the previous composites. Original composites remain available for regression
and fallback; smaller distribution packages are a separate optimisation.

The classic implementation establishes the asset contract. It does not supply
HD animations, independent armour/sword artwork, or a complete modding API.

A future 3D renderer can map ground position and height to a scene with an
orthographic camera initially. Animation must follow the authoritative clock;
root motion, skeletons, shaders and frame callbacks have no gameplay authority.

## Equipment and animation requirements

Armour is a complete appearance: headwear, torso, hands, legs and footwear.
The existing armour item selects the outfit; extra equipment slots are not
implied. Keep knight colour visible across all armour tiers. Sword appearance
must follow the effective weapon, including carried-item overrides.

Use shared foot anchors and explicit hand sockets/draw order for equipment.
Prefer reusable weapon/armour layers over every baked combination. Before
replacing playable classic combat, the new pack must cover idle,
walking/turning, ordinary/overhead/reverse/upward
strikes, lunge, dagger throw, hurt, holds, executions and death, including gore
and clean variants. A painted concept is not an animation-ready asset or rig.

The graphics milestone does not change simulation timing, collision, damage,
progression, save formats, controller mapping or multiplayer behavior.
