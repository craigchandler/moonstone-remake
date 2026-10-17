extends RefCounted

# Pure arithmetic shared by live characters and validated save records. Callers
# validate IDs/counts before reading content; no state or randomness lives here.
static func maximum_health(rules: Resource, constitution: int, armour: String, items: Dictionary) -> int:
    var base: int = int(rules.base_health) + constitution * int(rules.constitution_health)
    var equipment: int = int(rules.armours[armour].health)
    var protection: int = int(items.get("ring_of_protection", 0)) * int(rules.protection_health)
    return base + equipment + protection

static func talisman_shift(items: Dictionary) -> int:
    return clampi(int(items.get("talisman_of_the_wyrm", 0)), 0, 31)

static func dragon_damage(amount: int, shift: int) -> int:
    return amount >> clampi(shift, 0, 31)
