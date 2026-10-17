class_name MoonstoneWorldDefinition
extends Resource

# Travel/encounter data is independent of the map artwork and presentation.
@export var content_id: StringName = &"journey.v8"
@export var dragon_rules: Resource = preload("res://content/classic_map_dragon.tres")
# Empty terrain keeps the old explicit replay fixtures flat. The production world
# selects the verified original grid in first_journey.tres.
@export var travel_rules: Resource
@export var bounds: Rect2i = Rect2i(12, 8, 296, 187)
@export var start_position: Vector2i = Vector2i(40, 63)
@export var ticks_per_step: int = 2
@export var entry_radius: int = 5
@export var rival_turns: bool = false # Historical single-knight replay fixtures remain explicit.
@export var confirm_entry: bool = false # Historical explicit fixtures keep automatic entry.
@export var lairs: Array[Dictionary] = [
    {"id": "grassland_west", "name": "West lair", "position": Vector2i(65, 63), "encounter": &"spear_lair", "region": "Misty Moors"},
    {"id": "grassland_east", "name": "East lair", "position": Vector2i(111, 71), "encounter": &"balok_lair", "region": "Misty Moors"},
    {"id": "grassland_north", "name": "North lair", "position": Vector2i(92, 33), "encounter": &"axe_lair", "region": "Misty Moors"},
    {"id": "grassland_south", "name": "South lair", "position": Vector2i(90, 112), "encounter": &"troll_lair", "region": "Misty Moors"},
    {"id": "lair_05", "name": "Forest lair 1", "position": Vector2i(24, 112), "encounter": &"spear_lair", "region": "Great Forest"},
    {"id": "lair_06", "name": "Forest lair 2", "position": Vector2i(104, 120), "encounter": &"axe_lair", "region": "Great Forest"},
    {"id": "lair_07", "name": "Forest lair 3", "position": Vector2i(120, 144), "encounter": &"spear_lair", "region": "Great Forest"},
    {"id": "lair_08", "name": "Forest lair 4", "position": Vector2i(80, 184), "encounter": &"axe_lair", "region": "Great Forest"},
    {"id": "lair_09", "name": "Forest lair 5", "position": Vector2i(24, 160), "encounter": &"spear_lair", "region": "Great Forest"},
    {"id": "lair_10", "name": "Forest lair 6", "position": Vector2i(48, 136), "encounter": &"axe_lair", "region": "Great Forest"},
    {"id": "lair_11", "name": "Wastes lair 1", "position": Vector2i(296, 32), "encounter": &"balok_lair", "region": "Northern Wastes"},
    {"id": "lair_12", "name": "Wastes lair 2", "position": Vector2i(232, 16), "encounter": &"troll_lair", "region": "Northern Wastes"},
    {"id": "lair_13", "name": "Wastes lair 3", "position": Vector2i(176, 48), "encounter": &"balok_lair", "region": "Northern Wastes"},
    {"id": "lair_14", "name": "Wastes lair 4", "position": Vector2i(240, 48), "encounter": &"troll_lair", "region": "Northern Wastes"},
    {"id": "lair_15", "name": "Wastes lair 5", "position": Vector2i(216, 72), "encounter": &"balok_lair", "region": "Northern Wastes"},
    {"id": "lair_16", "name": "Wastes lair 6", "position": Vector2i(272, 80), "encounter": &"troll_lair", "region": "Northern Wastes"},
    {"id": "lair_17", "name": "Wetland lair 1", "position": Vector2i(208, 104), "encounter": &"spear_lair", "region": "Wetlands"},
    {"id": "lair_18", "name": "Wetland lair 2", "position": Vector2i(248, 120), "encounter": &"axe_lair", "region": "Wetlands"},
    {"id": "lair_19", "name": "Wetland lair 3", "position": Vector2i(168, 136), "encounter": &"spear_lair", "region": "Wetlands"},
    {"id": "lair_20", "name": "Wetland lair 4", "position": Vector2i(152, 176), "encounter": &"axe_lair", "region": "Wetlands"},
    {"id": "lair_21", "name": "Wetland lair 5", "position": Vector2i(232, 176), "encounter": &"spear_lair", "region": "Wetlands"},
    {"id": "lair_22", "name": "Wetland lair 6", "position": Vector2i(288, 176), "encounter": &"axe_lair", "region": "Wetlands"},
    {"id": "lair_23", "name": "Moor lair 1", "position": Vector2i(24, 24), "encounter": &"spear_lair", "region": "Misty Moors"},
    {"id": "lair_24", "name": "Moor lair 2", "position": Vector2i(96, 16), "encounter": &"axe_lair", "region": "Misty Moors"}
]
@export var towns: Array[Dictionary] = [
    {"id": "highwood", "name": "Highwood", "position": Vector2i(82, 28), "services": ["smith", "healer", "temple", "tavern"]},
    {"id": "waterdeep", "name": "Waterdeep", "position": Vector2i(277, 143), "services": ["smith", "healer", "tavern", "mystic"]}
]
@export var special_encounters: Array[Dictionary] = [
    {"id": "valley_guardian", "name": "Valley of the Gods", "position": Vector2i(152,97), "encounter": &"guardian_fight", "region": "Valley", "experience": 3, "life_cost": 3, "marker": "V"},
    {"id": "roaming_dragon", "name": "Roaming Dragon", "position": Vector2i(210,90), "encounter": &"dragon_fight", "region": "Wandering", "experience": 2},
    {"id": "roaming_black_knight", "name": "Black Knight", "position": Vector2i(45,90), "encounter": &"black_knight_fight", "region": "Wandering", "experience": 0, "marker": "K", "route": [Vector2i(45,90),Vector2i(125,125),Vector2i(195,65),Vector2i(240,165)]}
]
