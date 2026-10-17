extends SceneTree

const World = preload("res://scripts/domain/world_simulation.gd")
const Journey = preload("res://scripts/session/journey_session.gd")
const Definition = preload("res://scripts/content/world_definition.gd")
var failures: int = 0

func check(condition: bool, message: String) -> void:
    if not condition:
        failures += 1
        push_error(message)

func enter_first(journey: RefCounted) -> void:
    for step in range(100):
        if journey.travel(Vector2i.RIGHT): return
    check(false, "Travel must reach the west lair")

func _initialize() -> void:
    var definition: Resource = Definition.new()
    var world: RefCounted = World.new(definition)
    var replay: RefCounted = World.new(definition)
    check(not world.finish_lair("victory"), "A result without an active lair is rejected")
    for step in range(100):
        var direction := Vector2i.RIGHT
        check(world.advance(direction) == replay.advance(direction), "Travel replays identical entry events")
        check(world.snapshot() == replay.snapshot(), "Travel snapshots replay deterministically")
    check(world.active_lair == "grassland_west", "Walking into an uncleared lair starts it")
    var frozen: Dictionary = world.snapshot()
    world.advance(Vector2i.DOWN)
    check(world.snapshot() == frozen, "Travel state freezes while combat is active")
    check(not world.finish_lair("invalid") and world.snapshot() == frozen, "Invalid results cannot mutate a journey")
    check(world.finish_lair("defeat") and world.cleared.is_empty(), "Defeat leaves the lair occupied")
    for step in range(8): world.advance(Vector2i.RIGHT)
    check(world.active_lair.is_empty(), "Returning inside a failed entrance does not immediately retrigger")
    for step in range(30): world.advance(Vector2i.RIGHT)
    for step in range(40):
        world.advance(Vector2i.LEFT)
        if not world.active_lair.is_empty(): break
    check(world.active_lair == "grassland_west", "Walking away and back can retry a failed lair")
    check(world.finish_lair("victory"), "Victory completes the active lair")
    check(world.cleared.size() == 1 and world.cleared.has("grassland_west"), "Only the winning lair is cleared")
    check(not world.finish_lair("victory"), "A duplicate result is rejected")
    var copy: Dictionary = world.snapshot()
    copy.cleared.clear()
    check(world.cleared.size() == 1, "Snapshot copies cannot erase progress")
    for step in range(15): world.advance(Vector2i.LEFT)
    for step in range(15): world.advance(Vector2i.RIGHT)
    check(world.active_lair.is_empty(), "Cleared lairs do not start further fights")
    world.restart()
    for step in range(900): world.advance(Vector2i(-1, -1))
    check(world.position == definition.bounds.position, "Travel is clamped to map bounds")
    world.restart()
    check(world.position == definition.start_position and world.cleared.is_empty() and world.entry_lock.is_empty(), "A new journey resets position, progress and entry lock")

    var rules: Resource = load("res://content/foundation_rules.tres")
    var journey: RefCounted = Journey.new(definition, rules)
    enter_first(journey)
    check(journey.combat.simulation.encounter == &"spear_lair", "Lair content selects the native encounter")
    check(journey.combat.simulation.spawn_remaining == 2 and journey.combat.simulation.actors[1].health == 20, "Map entry uses the normal four-enemy encounter")
    check(journey.return_to_map() and journey.world.last_result == "retreated" and journey.world.cleared.is_empty(), "Retreat reads ongoing combat and does not grant victory")
    journey.restart()
    journey.mode = &"cooperative"
    enter_first(journey)
    check(journey.combat.simulation.actors[2].team == 1, "Selected co-op mode reaches combat")
    # Explicit result fixtures isolate routing from combat damage tests.
    journey.combat.simulation.actors[1].health = 0
    journey.combat.simulation.actors[2].health = 0
    check(journey.return_to_map() and journey.world.last_result == "defeat" and journey.world.cleared.is_empty(), "Actual team defeat returns without clearing")
    journey.restart()
    enter_first(journey)
    journey.combat.simulation.spawn_remaining = 0
    for actor in journey.combat.simulation.actors.values():
        if actor.team == 2: actor.health = 0
    check(journey.return_to_map() and journey.world.cleared.size() == 1, "Actual combat victory marks exactly one site")
    check(not journey.return_to_map(), "A finished combat cannot be claimed twice")
    journey.world.position = Vector2i(100, 71) # Travel to a different site, no result mutation.
    for step in range(30):
        if journey.travel(Vector2i.RIGHT): break
    check(journey.world.active_lair == "grassland_east" and journey.world.cleared.size() == 1, "Previous progress survives entering another lair")
    check(journey.combat.simulation.actors[1].health == 20 and journey.combat.simulation.actors[1].daggers == 10, "Next lair retains the unchanged journey kit")
    journey.return_to_map()
    # Complete each remaining site in the pure model; all victories end the test journey.
    for site in definition.lairs:
        if journey.world.cleared.has(site.id): continue
        journey.world.active_lair = site.id
        journey.world.finish_lair("victory")
    check(journey.world.complete(), "Clearing all sites completes the journey")
    journey.restart()
    check(not journey.world.complete() and journey.combat == null, "Restart discards completed journey and combat")
    if failures == 0:
        print("PASS: deterministic travel/entry/bounds, frozen travel, result routing, retry lock, cleared lairs, co-op, retained kits and new journey")
    quit(1 if failures else 0)
