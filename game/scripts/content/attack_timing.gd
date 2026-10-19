extends Resource

# Bundled content API1. Clocks are simulation ticks; no sprite or audio IDs.
@export var profile_id: String = "classic:combat_pacing"
@export var api_version: int = 1
@export var content_version: int = 1
@export var moves: Dictionary = {}
@export var reactions: Dictionary = {}

# Original surviving-hurt paths without any hurt-list draws. Pure gameplay IDs;
# renderers and sprite visibility never decide whether a hit is accepted.
@export var untargetable_reactions: Dictionary = {}
