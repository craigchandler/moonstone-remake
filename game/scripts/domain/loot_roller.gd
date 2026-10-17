class_name LootRoller
extends RefCounted

var rules: Resource
var state: int
var last_slot: int = -1

func _init(loot_rules: Resource, seed_value: int) -> void:
    rules = loot_rules
    state = seed_value & 0xffffffff
    # 0 is fixed and 1 shifts directly to 0 in this generator.
    if state <= 1: state = 2

func next_value() -> int:
    # Original eight-round feedback generator, expressed as bounded native integer data.
    for step in range(8):
        var rotated: int = ((state >> 3) | (state << 29)) & 0xffffffff
        var feedback: int = (((rotated ^ state) >> 1) & 1) << 31
        state = (feedback | (state >> 1)) & 0xffffffff
    return state

func percent() -> int:
    # The original folds 100..127 down by 27; this is intentionally not uniform 1..100.
    var value: int = next_value() & 0x7f
    return value - 27 if value >= 100 else value

func gold() -> int:
    var value: int = next_value() & 0x1f
    return value if value > 21 else value + 10

func item(pile: Dictionary) -> String:
    for attempt in range(1024):
        var roll: int = percent()
        for band in rules.item_bands:
            if roll > int(band[0]): continue
            var slot: int = band[1]
            if slot == last_slot: break
            last_slot = slot
            var id: String = band[2]
            if slot == 4 and int(pile.get(id, 0)) > 0: break
            pile[id] = int(pile.get(id, 0)) + 1
            return id
    # The retail tables cannot exhaust this bound with a nonzero seed.
    push_error("Loot item roll exhausted its bound")
    return ""

func roll_lair() -> Dictionary:
    var kind: int = 4
    var roll: int = percent()
    for band in rules.lair_bands:
        if roll <= int(band[0]):
            kind = band[1]
            break
    var pile: Dictionary = {"gold": 0, "items": {}, "kind": kind}
    if kind in [1, 3]: pile.gold = gold()
    for step in range(3 if kind == 2 else (2 if kind == 3 else 0)):
        item(pile.items)
    return pile
