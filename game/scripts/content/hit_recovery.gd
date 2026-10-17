extends Resource

# Numeric native rules, shared by classic and future artwork.
@export var clocks: Dictionary = {}

func duration(family: String, clip: String, fallback: int) -> int:
    return int(clocks.get(family,{}).get(clip,fallback))

func committed(family: String, clip: String) -> bool:
    return clocks.get(family,{}).has(clip)
