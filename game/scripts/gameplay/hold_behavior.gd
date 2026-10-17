extends Resource

# First bounded gameplay interface, API 1. The host supplies copied plain data;
# a script returns one command, never a model, node, clock, RNG or mutable actor.
@export var behavior_id: StringName
@export var api_version: int = 1
@export var content_version: int = 1

func decide(_context: Dictionary) -> Dictionary:
    return {"operation":"wait"}
