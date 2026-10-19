extends Resource

# Numeric native rules, shared by classic and future artwork.
@export var clocks: Dictionary = {}
@export var base: Resource

func duration(family: String, clip: String, fallback: int) -> int:
    if clocks.get(family,{}).has(clip): return int(clocks[family][clip])
    return base.duration(family,clip,fallback) if base else fallback

func committed(family: String, clip: String) -> bool:
    return clocks.get(family,{}).has(clip) or (base != null and base.committed(family,clip))
