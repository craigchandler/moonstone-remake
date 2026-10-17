extends Resource

# Finite native clocks, independent of art and the one-time original-data import.
@export var clocks: Dictionary = {}

func duration(family: String, clip: String) -> int:
    return int(clocks[family][clip].ticks)

func solo_limit(family: String, clip: String) -> int:
    var entry: Dictionary = clocks[family][clip]
    if entry.death_mark == null: return int(entry.ticks)
    # Original fight-finished delay is50 creature steps after the death mark.
    return mini(int(entry.ticks), int(entry.death_mark)+300)
