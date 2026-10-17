class_name KnightProgression
extends RefCounted

const Math = preload("res://scripts/domain/character_math.gd")

var rules: Resource
var stats: Dictionary = {"strength": 1, "constitution": 1, "endurance": 1}
var experience: int = 0
var lives: int = 5
var health: int = 20
var daggers: int = 10
var weapon: String = "long_sword"
var armour: String = "padded_armour"
var life_loss: int = 0 # Original curse byte +130; future sources/ticking are separate.

func _init(character_rules: Resource) -> void:
    rules = character_rules
    lives = rules.life_limit
    daggers = rules.dagger_limit
    health = maximum({})

func maximum(items: Dictionary) -> int:
    return Math.maximum_health(rules, int(stats.constitution), armour, items)

func endurance() -> int:
    return int(rules.base_endurance) + int(stats.endurance) * int(rules.endurance_per_stat) + int(rules.armours[armour].endurance)

func effective_weapon(items: Dictionary) -> String:
    return "sword_of_sharpness" if int(items.get("sword_of_sharpness", 0)) > 0 else weapon

func combat_profile(items: Dictionary) -> Dictionary:
    return {"health": health, "maximum": maximum(items), "daggers": daggers,
        "endurance_stat": int(stats.endurance),
        "dragon_damage_shift": Math.talisman_shift(items),
        # Base moves include the original starting strength of one; add upgrades here.
        "damage_bonus": int(stats.strength) - 1 + int(rules.weapons[effective_weapon(items)].damage)}

func upgrade(stat: String, cost: int, items: Dictionary) -> bool:
    if not stats.has(stat) or cost < 1 or experience < cost or int(stats[stat]) >= int(rules.stat_limit): return false
    stats[stat] += 1
    experience -= cost
    if stat == "constitution": health += int(rules.constitution_health)
    health = mini(health, maximum(items))
    return true

func heal(items: Dictionary) -> bool:
    if health >= maximum(items) and lives >= int(rules.life_limit): return false
    if health >= maximum(items): lives = mini(lives + 1, int(rules.life_limit))
    health = maximum(items)
    return true

func rest(items: Dictionary) -> void:
    var missing: int = maxi(0, maximum(items) - health)
    if missing > 0: health = mini(maximum(items), health + ((missing >> 2) | 1))

func snapshot() -> Dictionary:
    return {"stats": stats.duplicate(true), "experience": experience, "lives": lives,
        "health": health, "daggers": daggers, "weapon": weapon, "armour": armour, "life_loss": life_loss}
