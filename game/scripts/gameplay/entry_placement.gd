extends Resource

@export var behavior_id: StringName = &""
@export var api_version: int = 1
@export var content_version: int = 1
@export var initial_counter: int = 0
@export var default_low_edge: int = 99
@export var site_edges: Dictionary = {}

# Copied plain facts in; the host owns the persistent cursor and actor positions.
func decide(_facts: Dictionary) -> Dictionary:
    return {}
