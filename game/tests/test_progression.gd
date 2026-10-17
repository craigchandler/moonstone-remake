extends SceneTree

const Journey = preload("res://scripts/session/journey_session.gd")
const Session = preload("res://scripts/session/local_session.gd")
var failures: int = 0
var rules: Resource = preload("res://content/foundation_rules.tres")

func check(condition: bool, message: String) -> void:
    if not condition:
        failures += 1
        push_error(message)

func fresh() -> RefCounted:
    return Journey.new(load("res://scripts/content/world_definition.gd").new(), rules, 0x4d4f4f4e)

func enter(journey: RefCounted, index: int = 0) -> void:
    if not journey.town_id.is_empty(): journey.leave_town()
    journey.begin_turn()
    var site: Dictionary = journey.world.definition.lairs[index]
    journey.world.position = site.position - Vector2i(8, 0)
    for step in range(20):
        if journey.travel(Vector2i.RIGHT): return
    check(false, "Test entrance must start combat")

func visit(journey: RefCounted, service: String = "smith") -> void:
    if not journey.town_id.is_empty(): journey.leave_town()
    journey.begin_turn()
    journey.world.position = journey.town("highwood").position
    journey.enter_town("highwood")
    journey.open_service(service)

func win(journey: RefCounted) -> void:
    journey.combat.simulation.spawn_remaining = 0
    for actor in journey.combat.simulation.actors.values():
        if actor.team == 2: actor.health = 0

func _initialize() -> void:
    var journey: RefCounted = fresh()
    check(journey.character.health == 20 and journey.character.lives == 5 and journey.character.daggers == 10 and journey.inventory.gold == 10, "classic starting kit and derived HP")
    for humans in range(1, 5):
        journey.human_players = humans
        check(journey.upgrade_cost() == [3, 2, 1, 1][humans - 1], "original human-player costs")
    journey.human_players = 1
    journey.mode = &"cooperative"
    check(journey.upgrade_cost() == 3, "AI helper is not a second human")
    check(not journey.upgrade_stat("strength") and not journey.upgrade_stat("invented"), "unaffordable or unknown upgrade refused")
    visit(journey)
    check(journey.buy_equipment("broad_sword") and journey.inventory.gold == 0, "real price deducted and sword equipped")
    check(not journey.buy_equipment("broad_sword") and not journey.buy_equipment("claymore"), "duplicates and unaffordable purchases refused")
    journey.inventory.gold = 150
    check(journey.buy_equipment("chainmail") and journey.character.maximum({}) == 30 and journey.character.health == 30 and journey.character.endurance() == 8, "mail health and endurance bonuses")
    check(journey.buy_equipment("platemail") and journey.character.maximum({}) == 40 and journey.character.health == 40 and journey.character.endurance() == 6, "armour replaces bonuses rather than stacking")
    check(not journey.buy_equipment("chainmail") and not journey.buy_equipment("unknown"), "armour downgrade/unknown purchase has no charge")
    journey.character.daggers = 9
    check(journey.buy_equipment("dagger") and journey.character.daggers == 10 and not journey.buy_equipment("dagger"), "dagger price and cap")
    var gold: int = journey.inventory.gold
    enter(journey)
    check(journey.combat.simulation.actors[1].maximum == 40 and journey.combat.simulation.actors[1].damage_bonus == 2, "journey loadout reaches authoritative combat")
    check(not journey.buy_equipment("claymore") and journey.inventory.gold == gold and not journey.upgrade_stat("strength"), "no shop/upgrades during battle")
    journey.combat.simulation.actors[1].health = 23
    journey.combat.simulation.actors[1].daggers = 7
    journey.return_to_map()
    check(journey.character.health == 23 and journey.character.daggers == 7 and journey.character.experience == 0, "retreat retains spent kit without XP")
    enter(journey, 1)
    check(journey.combat.simulation.actors[1].health == 23 and journey.combat.simulation.actors[1].daggers == 7, "next lair receives retained kit")
    win(journey)
    journey.prepare_loot()
    journey.prepare_loot()
    check(journey.character.experience == 1, "victory awards one XP once even when loot reopens")
    journey.return_to_map()
    check(journey.character.experience == 1 and not journey.return_to_map(), "return cannot double the award")
    # Clear the other two sites through real journey result routing.
    for site_index in [2, 3]:
        enter(journey, site_index)
        win(journey)
        journey.return_to_map()
    check(journey.character.experience == 3, "three unique won battles accumulate three XP")
    visit(journey, "temple")
    check(journey.upgrade_stat("constitution") and journey.character.stats.constitution == 2 and journey.character.experience == 0, "three XP buys one chosen stat")
    journey.character.experience = 99
    for step in range(8): journey.upgrade_stat("strength")
    check(journey.character.stats.strength == 5 and journey.character.experience == 87, "cap five refuses extra deductions")
    var previous_allowance: int = journey.travel_allowance()
    check(journey.upgrade_stat("endurance") and journey.travel_allowance() == previous_allowance + 32, "endurance increases real day budget")
    # Ring, forced sharp sword, healing and retained inventories.
    journey = fresh()
    journey.inventory.items = {"ring_of_protection": 2, "sword_of_sharpness": 1, "healing_potion": 2, "talisman_of_the_wyrm": 2, "scroll_of_haste": 2, "gem_of_seeing": 2, "scroll_of_the_hawk": 1, "scroll_of_acquisition": 1, "scroll_of_the_wyrm": 1, "scroll_of_protection": 1}
    check(journey.character.maximum(journey.inventory.items) == 60 and journey.character.combat_profile(journey.inventory.items).damage_bonus == 5, "rings stack and sharp sword is automatic")
    check(journey.use_item("healing_potion") and journey.character.health == 60 and journey.inventory.items.healing_potion == 1, "potion fully heals once")
    check(not journey.use_item("healing_potion") and journey.inventory.items.healing_potion == 1, "full-health/life potion not wasted")
    journey.character.lives = 4
    check(journey.use_item("healing_potion") and journey.character.lives == 5 and not journey.inventory.items.has("healing_potion"), "potion restores a life when HP is full")
    var before: Dictionary = journey.snapshot()
    for id in ["sword_of_sharpness", "ring_of_protection", "talisman_of_the_wyrm", "scroll_of_acquisition", "scroll_of_the_wyrm", "scroll_of_protection", "unknown"]:
        check(not journey.use_item(id), "passive or unavailable context never consumes: " + id)
    check(journey.snapshot() == before, "unavailable/passive use preserves all authoritative state")
    check(preload("res://scripts/domain/character_math.gd").dragon_damage(30, journey.character.combat_profile(journey.inventory.items).dragon_damage_shift) == 7, "wyrm talismans halve and stack with integer shifts")
    check(journey.use_item("scroll_of_haste") and journey.travel_allowance() == 192 and not journey.use_item("scroll_of_haste") and journey.inventory.items.scroll_of_haste == 1, "haste doubles the day's allowance once")
    var rewards: Dictionary = journey.lair_loot.duplicate(true)
    check(not journey.use_item("gem_of_seeing", "unknown") and journey.use_item("gem_of_seeing", "grassland_east") and journey.lair_loot == rewards and journey.character.experience == 0, "gem reveals real treasure without granting or changing it")
    check(not journey.use_item("scroll_of_the_hawk", Vector2i(-1, 0)) and not journey.use_item("scroll_of_the_hawk", journey.world.position), "invalid/unchanged teleports keep the scroll")
    check(journey.use_item("scroll_of_the_hawk", Vector2i(120, 70)) and journey.world.position == Vector2i(120, 70) and not journey.inventory.items.has("scroll_of_the_hawk"), "successful teleport consumes exactly once")
    journey.character.health = 12
    check(journey.rest() and not journey.haste and journey.day == 2 and journey.travel_remaining() == 96 and journey.character.health == 25, "rest resets haste/travel and uses original quarter-missing OR-one regeneration")
    journey.begin_turn()
    journey.world.position = Vector2i(250, 160)
    journey.travel_spent = journey.travel_allowance() - 1
    for step in range(4): journey.travel(Vector2i.LEFT)
    check(journey.turn_pending and journey.day==3 and journey.world.position == Vector2i(249, 160), "exhaustion ends exactly one turn and freezes movement at its last point")
    journey.begin_turn()
    enter(journey)
    check(journey.combat.simulation.actors[1].damage_bonus == 5, "sharpness reaches combat")
    journey.combat.simulation.actors[1].health = 0
    journey.return_to_map()
    check(journey.character.lives == 4 and journey.character.health == 60 and journey.character.experience == 0, "defeat costs one life and never XP-rewards")
    # Actual native contacts in both facings; practice remains unmodified.
    for facing in [1, -1]:
        for move in ["swing", "heavy"]:
            var session: RefCounted = Session.new(rules)
            session.knight_profile = {"health": 20, "maximum": 20, "daggers": 4, "damage_bonus": 6}
            session.start(&"competitive", &"duel")
            var model: RefCounted = session.simulation
            model.actors[1].x = 160
            model.actors[1].facing = facing
            model.actors[2].x = 160 + facing * (80 if move == "heavy" else 25)
            model.actors[1].action = move
            model.actors[1].remaining = rules.moves[move].active + rules.moves[move].recovery + 1
            for step in range(rules.moves[move].active + 1): model.advance()
            check(model.actors[2].health == maxi(0, 20 - int(rules.moves[move].damage) - (12 if move == "heavy" else 6)), "real sword contact applies upgrade/weapon bonus exactly once: " + move)
            check(model.actors[1].health <= 20 and model.actors[2].damage_bonus == 0, "loadout never leaks to hostile knight")
    var copied: Dictionary = journey.snapshot()
    copied.character.stats.clear()
    copied.revealed_lairs.clear()
    check(journey.character.stats.size() == 3 and journey.revealed_lairs.size() == 1, "progression snapshots do not alias authoritative state")
    journey.restart()
    check(journey.character.experience == 0 and journey.character.health == 20 and journey.awarded_lairs.is_empty() and journey.inventory.items.is_empty(), "new journey resets character and reward ownership")
    if failures == 0: print("PASS: equipment prices/caps, native damage/loadout, persistent kit, single victory XP, player costs/stat caps, passive stacking, healing, reveal, teleport, haste/endurance/rest and snapshot isolation")
    quit(1 if failures else 0)
