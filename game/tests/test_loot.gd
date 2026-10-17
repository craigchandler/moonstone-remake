extends SceneTree

const Roller = preload("res://scripts/domain/loot_roller.gd")
const Journey = preload("res://scripts/session/journey_session.gd")
var failures: int = 0

func check(condition: bool, message: String) -> void:
    if not condition:
        failures += 1
        push_error(message)

func enter_first(journey: RefCounted) -> void:
    for step in range(100):
        if journey.travel(Vector2i.RIGHT): return
    check(false, "Test travel must reach the first lair")

func win_fixture(journey: RefCounted) -> void:
    # Explicit outcome fixture; combat damage and wave completion have separate suites.
    journey.combat.simulation.spawn_remaining = 0
    for actor in journey.combat.simulation.actors.values():
        if actor.team == 2: actor.health = 0

func _initialize() -> void:
    var rules: Resource = load("res://content/generated/classic_loot.tres")
    check(rules.lair_bands == [[50,1],[70,2],[90,3],[100,4]], "Imported retail lair thresholds and kinds remain intact")
    var first: RefCounted = Roller.new(rules, 0x4d4f4f4e)
    var replay: RefCounted = Roller.new(rules, 0x4d4f4f4e)
    var observed: Dictionary = {}
    for roll in range(500):
        var pile: Dictionary = first.roll_lair()
        check(pile == replay.roll_lair(), "Seeded loot and duplicate suppression replay identically")
        observed[pile.kind] = true
        var count: int = 0
        for id in pile.items:
            check(rules.items.has(id) and pile.items[id] > 0, "Every rolled item has a valid catalog entry and positive count")
            count += int(pile.items[id])
        check((pile.gold >= 10 and pile.gold <= 31) if pile.kind in [1,3] else pile.gold == 0, "Gold belongs only to gold/mixed rewards and stays within the original mapping")
        check(count == (3 if pile.kind == 2 else (2 if pile.kind == 3 else 0)), "Gold, three-item, mixed and empty chests contain the correct roll counts")
        check(int(pile.items.get("sword_of_sharpness", 0)) <= 1, "One chest cannot contain duplicate Swords of Sharpness")
    check(observed.size() == 4, "Seeded exercise reaches all four reward kinds, including empty")
    var item_roller: RefCounted = Roller.new(rules, 0x12345678)
    var previous: String = ""
    for roll in range(200):
        var fresh: Dictionary = {}
        var id: String = item_roller.item(fresh)
        check(not id.is_empty() and id != previous and fresh[id] == 1, "Successive item draws into fresh chests suppress the previous item")
        previous = id
    for seed_value in [0,1,2]:
        var safe: RefCounted = Roller.new(rules, seed_value)
        var safe_first: Dictionary = safe.roll_lair()
        check(safe.state != 0 and not safe_first.is_empty(), "Degenerate RNG seeds are normalised safely")

    var definition: Resource = load("res://scripts/content/world_definition.gd").new()
    var combat_rules: Resource = load("res://content/foundation_rules.tres")
    var journey: RefCounted = Journey.new(definition, combat_rules, 0x4d4f4f4e)
    var rolled: Dictionary = journey.lair_loot.duplicate(true)
    var expected: Dictionary = rolled.grassland_west
    check(expected == {"gold":25,"items":{"scroll_of_the_hawk":1,"scroll_of_acquisition":1},"kind":3,"keys":0}, "Fixed visual seed has a stable mixed chest")
    check(not journey.prepare_loot() and not journey.take_loot("gold"), "Map state cannot open or claim loot")
    enter_first(journey)
    check(not journey.prepare_loot() and not journey.take_loot("gold"), "An unfinished encounter cannot claim loot")
    journey.combat.start(journey.mode, &"spear_lair")
    check(journey.lair_loot == rolled, "Retrying a battle cannot reroll its rewards")
    journey.return_to_map()
    check(journey.inventory == {"gold":10,"items":{}} and journey.lair_loot == rolled, "Retreat grants nothing and leaves pre-rolled loot intact")
    journey.restart(0x4d4f4f4e)
    enter_first(journey)
    journey.combat.simulation.actors[1].health = 0
    journey.return_to_map()
    check(journey.inventory == {"gold":10,"items":{}} and journey.lair_loot == rolled, "Defeat cannot collect or reroll rewards")
    journey.restart(0x4d4f4f4e)
    enter_first(journey)
    win_fixture(journey)
    check(journey.prepare_loot() and journey.prepare_loot(), "Real victory opens loot idempotently")
    var copied: Dictionary = journey.available_loot()
    copied.items.clear()
    check(journey.available_loot() == expected, "Loot display copies cannot mutate authoritative rewards")
    check(not journey.take_loot("invented_item"), "Unknown item IDs are rejected")
    check(journey.take_loot("gold") and not journey.take_loot("gold") and journey.inventory.gold == 25 + 10, "Gold transfers once, with no duplicate claim")
    check(journey.take_loot("scroll_of_the_hawk") and not journey.take_loot("scroll_of_the_hawk"), "An individual item transfers exactly once")
    check(journey.prepare_loot() and journey.available_loot().gold == 0, "Reopening the same loot cannot restore collected rewards")
    journey.return_to_map()
    check(journey.world.cleared.size() == 1 and journey.inventory.gold == expected.gold + 10 and journey.inventory.items == expected.items, "Returning collects only the remainder, preserves inventory and clears one lair")
    var settled: Dictionary = journey.snapshot()
    journey.collect_all_loot()
    check(not journey.return_to_map() and not journey.take_loot("gold") and journey.snapshot() == settled, "Completed encounters cannot be claimed again")
    var copy: Dictionary = journey.snapshot()
    copy.inventory.items.clear()
    copy.lair_loot.clear()
    check(journey.snapshot() == settled, "Journey snapshots isolate inventory and per-lair reward state")
    journey.restart(0x12345678)
    check(journey.inventory == {"gold":10,"items":{}} and journey.lair_loot != rolled, "A new journey resets the pack and can roll different loot")
    enter_first(journey)
    win_fixture(journey)
    journey.prepare_loot()
    journey.combat.start(journey.mode, &"spear_lair") # Explicit invalidated combat state.
    journey.collect_all_loot()
    check(journey.inventory == {"gold":10,"items":{}}, "Invalidated victory refuses collection without looping")
    var art: Resource = load("res://assets/classic/loot/art.tres")
    check(art.background.get_size() == Vector2(320,200), "Classic loot panels preserve their logical size")
    for id in rules.items:
        check(art.icon_for(id) != null, "Every reward has separate native artwork")
    if failures == 0:
        print("PASS: seeded retail reward shapes/replay, safe seeds, item restrictions, victory authority, retry stability, single claims, conserved inventory and reset")
    quit(1 if failures else 0)
