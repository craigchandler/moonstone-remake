class_name MoonstoneGameplayPack
extends Resource

# Trusted built-in pack identity. Exact code/data hashes determine network
# compatibility; the readable version alone is never sufficient.
@export var pack_id: StringName = &""
@export var pack_version: String = ""
@export var api_version: int = 1
@export var display_name: String = ""
@export var scope: String = "combat"
@export var dependencies: PackedStringArray = []
