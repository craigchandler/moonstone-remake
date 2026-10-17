extends Resource

# Bundled gameplay API1. The host supplies copied, plain character/site facts.
# Scripts return only bounded total/concurrent counts; no campaign or RNG handle.
@export var behavior_id: StringName
@export var api_version: int = 1
@export var content_version: int = 1

func decide(_facts: Dictionary) -> Dictionary:
    return {}
