class_name MoonstoneArtPack
extends Resource

@export var pack_id: StringName
@export var display_name: String
@export var background: Texture2D
@export var textures: Dictionary = {}
@export var logical_sizes: Dictionary = {}
@export var animations: Dictionary = {}
@export var encounter_backgrounds: Dictionary = {}
@export var attack_returns: Dictionary = {}
@export var projectiles: Dictionary = {}
@export var effects: Dictionary = {}

func background_for(encounter: StringName) -> Texture2D:
    return encounter_backgrounds.get(String(encounter), background)

func texture_for(kind: String) -> Texture2D:
    return textures.get(kind)

func size_for(kind: String) -> Vector2:
    return logical_sizes.get(kind, Vector2(24, 54))

func animation_for(kind: String) -> Resource:
    return animations.get(kind)
