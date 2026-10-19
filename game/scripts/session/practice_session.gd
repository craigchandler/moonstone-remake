extends RefCounted

# Standalone fights have no campaign/store reference or reward transaction.
const Session = preload("res://scripts/session/local_session.gd")
const CHOICES: Array[String] = ["duel", "spear_lair", "axe_lair", "hammer_lair", "beast_lair", "rat_lair", "mud_lair", "troll_lair", "balok_lair", "dragon_fight", "guardian_fight", "black_knight_fight"]
const LABELS = {"duel":"KNIGHT", "spear_lair":"SPEAR TROGG", "axe_lair":"AXE TROGG", "hammer_lair":"HAMMER TROGG", "beast_lair":"WAR BEAST", "rat_lair":"RATMAN", "mud_lair":"MUDMAN", "troll_lair":"CLUB TROLL", "balok_lair":"BALOK", "dragon_fight":"DRAGON", "guardian_fight":"GUARDIAN", "black_knight_fight":"BLACK KNIGHT"}
const SEED: int = 0x50524143
var rules: Resource
var fight: RefCounted
var encounter: StringName = &"duel"

func _init(rule_set: Resource) -> void:
    rules = rule_set

func settings() -> Dictionary:
    return {"combat_seed":SEED}

func start(choice: StringName) -> bool:
    if String(choice) not in CHOICES or (choice != &"duel" and not rules.encounters.has(String(choice))): return false
    var next: RefCounted = Session.new(rules)
    next.start(&"competitive", choice, settings())
    encounter = choice
    fight = next
    return true
