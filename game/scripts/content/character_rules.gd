class_name MoonstoneCharacterRules
extends Resource

# Classic reference values live here so balancing and menu changes do not alter
# inventory ownership or combat code. Campaign contexts are deliberately explicit.
@export var content_id: StringName = &"classic.character.v1"
@export var stat_limit: int = 5
@export var stat_costs: Array[int] = [3, 2, 1, 1]
@export var lair_experience: int = 1
@export var dragon_experience: int = 2
@export var guardian_experience: int = 3
@export var starting_gold: int = 10
@export var gold_limit: int = 150
@export var life_limit: int = 5
@export var dagger_limit: int = 10
@export var healer_health_price: int = 10
@export var healer_life_price: int = 15
@export var dagger_price: int = 2
@export var base_health: int = 10
@export var constitution_health: int = 10
@export var protection_health: int = 20
@export var base_endurance: int = 4
@export var endurance_per_stat: int = 2
@export var travel_per_endurance: int = 16
@export var weapons: Dictionary = {
    "long_sword": {"name": "Long sword", "price": 0, "damage": 0, "rank": 0},
    "broad_sword": {"name": "Broad sword", "price": 10, "damage": 2, "rank": 1},
    "claymore": {"name": "Claymore", "price": 25, "damage": 3, "rank": 2},
    "sword_of_sharpness": {"name": "Sword of Sharpness", "price": 0, "damage": 5, "rank": 3}}
@export var armours: Dictionary = {
    "padded_armour": {"name": "Padded armour", "price": 0, "health": 0, "endurance": 0, "rank": 0},
    "chainmail": {"name": "Chainmail", "price": 30, "health": 10, "endurance": 2, "rank": 1},
    "platemail": {"name": "Platemail", "price": 50, "health": 20, "endurance": 0, "rank": 2},
    "battleplate": {"name": "Battleplate", "price": 75, "health": 30, "endurance": 2, "rank": 3}}
@export var items: Dictionary = {
    "healing_potion": {"effect": "heal", "description": "Restores all health. At full health, restores one life (up to 5). Used once."},
    "gem_of_seeing": {"effect": "reveal", "description": "Choose a lair to inspect its actual treasure without fighting. Used once after choosing."},
    "sword_of_sharpness": {"effect": "passive", "description": "Automatically wielded while carried: +5 sword damage, doubled on an overhead chop. Never consumed."},
    "ring_of_protection": {"effect": "passive", "description": "Each ring adds 20 maximum health while carried. Automatically active; rings stack."},
    "talisman_of_the_wyrm": {"effect": "dragon_passive", "description": "Automatically halves dragon damage once per talisman while carried. Talismans stack and are never consumed."},
    "scroll_of_haste": {"effect": "haste", "description": "Doubles this turn's travel allowance. Used once; expires when the turn ends."},
    "scroll_of_acquisition": {"effect": "rival", "description": "Choose a living rival and one carried magical object, key or moonstone. Cancel without spending it."},
    "scroll_of_the_hawk": {"effect": "teleport", "description": "Choose a destination on this journey's map. Used once on arrival. Cancel without spending it."},
    "scroll_of_the_wyrm": {"effect": "dragon_target", "description": "Choose a living rival for the Dragon to pursue after its first appearance. Cancel without spending it."},
    "scroll_of_protection": {"effect": "ambush", "description": "When a Black Knight attacks, a message opens your pack. Choose this scroll to avoid battle; close the pack without using it to fight. Used once."}}
