extends SceneTree

const Journey = preload("res://scripts/session/journey_session.gd")
const Store = preload("res://scripts/session/journey_store.gd")
var failures: int = 0
var definition: Resource = preload("res://scripts/content/world_definition.gd").new()
var rules: Resource = preload("res://content/foundation_rules.tres")
var path: String = "user://unit-journey.json"

func check(condition: bool, label: String) -> void:
    if not condition:
        failures += 1
        push_error(label)

func fresh() -> RefCounted:
    return Journey.new(definition, rules, 0x4d4f4f4e)

func enter(journey: RefCounted) -> void:
    for tick in range(100):
        if journey.travel(Vector2i.RIGHT): return
    check(false, "Save fixture reaches West")

func text_file(file_path: String, value: String) -> void:
    var file := FileAccess.open(file_path, FileAccess.WRITE)
    file.store_string(value)
    file.close()

func _initialize() -> void:
    for suffix in ["", ".bak", ".tmp"]:
        if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
    var journey: RefCounted = fresh()
    var store: RefCounted = Store.new(path, journey.validate_checkpoint)
    journey.store = store
    check(not journey.validate_checkpoint(journey.checkpoint()).is_empty(), "fresh expanded checkpoint validates")
    check(journey.persist() and store.load_checkpoint() == journey.checkpoint(), "JSON disk roundtrip of full fresh state")
    var source_loot: Dictionary = journey.lair_loot.duplicate(true)
    enter(journey)
    journey.combat.simulation.actors[1].health = 7
    journey.combat.simulation.actors[1].daggers = 6
    check(journey.persist(), "ongoing fight has a safe entrance checkpoint")
    var interrupted: RefCounted = fresh()
    check(interrupted.restore_checkpoint(store.load_checkpoint()) and interrupted.combat == null and interrupted.character.health == 20 and interrupted.world.entry_lock == "grassland_west", "live fight resumes at entrance with entry kit")
    check(interrupted.character.experience == 0 and interrupted.lair_loot == source_loot, "interrupted fight cannot earn XP or reroll treasure")
    journey.combat.simulation.spawn_remaining = 0
    for actor in journey.combat.simulation.actors.values():
        if actor.team == 2: actor.health = 0
    check(journey.persist() and journey.loot_open and journey.character.experience == 1, "finished battle autosaves before loot animations")
    var resumed: RefCounted = fresh()
    check(resumed.restore_checkpoint(store.load_checkpoint()) and resumed.loot_open and resumed.combat.simulation.outcome() == "victory", "won encounter resumes as loot")
    check(resumed.character.health == 7 and resumed.character.daggers == 6 and resumed.character.experience == 1, "won kit and XP survive roundtrip")
    journey.take_loot("gold")
    check(resumed.restore_checkpoint(store.load_checkpoint()) and resumed.inventory.gold == 35 and resumed.available_loot().gold == 0, "partial gold transfer is saved exactly once")
    check(not resumed.take_loot("gold") and resumed.character.experience == 1, "continued loot cannot repeat gold or XP")
    journey.take_loot("scroll_of_the_hawk")
    check(resumed.restore_checkpoint(store.load_checkpoint()) and resumed.inventory.items.scroll_of_the_hawk == 1 and not resumed.available_loot().items.has("scroll_of_the_hawk"), "individual item is persisted with reduced chest")
    journey.return_to_map()
    check(resumed.restore_checkpoint(store.load_checkpoint()) and resumed.world.cleared.size() == 1 and resumed.character.experience == 1 and resumed.inventory.items == journey.inventory.items, "cleared map and unclaimed remainder roundtrip")
    check(resumed.lair_loot == journey.lair_loot and resumed.reward_seed == journey.reward_seed, "all twenty-four exact chest rolls survive")
    var stable: Dictionary = resumed.checkpoint()
    var bads: Array = []
    var bad: Dictionary = stable.duplicate(true)
    bad.schema = 99
    bads.append(bad)
    bad = stable.duplicate(true)
    bad.character.stats.strength = 999
    bads.append(bad)
    bad = stable.duplicate(true)
    bad.inventory.items["res://scripts/untrusted.gd"] = 1
    bads.append(bad)
    bad = stable.duplicate(true)
    bad.inventory.gold = -1
    bads.append(bad)
    bad = stable.duplicate(true)
    bad.world.position.x = 99.25
    bads.append(bad)
    bad = stable.duplicate(true)
    bad.town_id = "highwood"
    bad.service = "temple"
    bads.append(bad)
    bad = stable.duplicate(true)
    bad.lair_loot.erase("grassland_east")
    bads.append(bad)
    bad = stable.duplicate(true)
    bad.world.cleared["unknown"] = true
    bads.append(bad)
    for invalid in bads:
        check(not resumed.restore_checkpoint(invalid) and resumed.checkpoint() == stable, "invalid save rejected before any live-state mutation")
    check(not store.save_checkpoint(bads[0]) and store.load_checkpoint() == stable, "invalid write cannot replace valid primary")
    # A checksum-invalid primary falls back; a semantically bad but rehashed one does too.
    var backup: Dictionary = store.read_file(path + ".bak")
    text_file(path, "{interrupted write")
    check(store.load_checkpoint() == backup and store.last_source.ends_with(".bak"), "corrupt primary recovers last good backup")
    var backup_text: String = FileAccess.get_file_as_string(path + ".bak")
    check(store.save_checkpoint(stable) and FileAccess.get_file_as_string(path + ".bak") == backup_text, "recovery write cannot promote corruption over backup")
    var body: String = JSON.stringify(bads[1])
    text_file(path, JSON.stringify({"format": "moonstone.journey", "version": 1, "data": body, "sha256": body.sha256_text()}))
    check(store.load_checkpoint() == backup, "rehashed invalid stats rejected with backup recovery")
    text_file(path, " ".repeat(Store.MAX_BYTES + 1))
    check(store.load_checkpoint() == backup, "oversized file is bounded and recovers backup")
    # Defeat is committed once even when quitting before death animation finishes.
    journey = fresh()
    journey.store = Store.new(path, journey.validate_checkpoint)
    enter(journey)
    journey.combat.simulation.actors[1].health = 0
    journey.persist()
    journey.persist()
    check(journey.character.lives == 4 and journey.character.experience == 0, "lost battle saves exactly one lost life")
    check(resumed.restore_checkpoint(journey.store.load_checkpoint()) and resumed.character.lives == 4 and resumed.character.health == 20, "defeat resumes map with recovery kit")
    # Real town purchases, rest, spells and upgrades are autosaved through their domain API.
    journey.return_to_map()
    journey.world.position = journey.town("highwood").position
    journey.enter_town("highwood")
    journey.open_service("smith")
    journey.inventory.gold = 80
    journey.buy_equipment("chainmail")
    check(resumed.restore_checkpoint(journey.store.load_checkpoint()) and resumed.character.armour == "chainmail" and resumed.town_id == "highwood" and resumed.service == "smith", "town and purchase roundtrip")
    journey.open_service("temple")
    journey.character.experience = 3
    journey.upgrade_stat("strength")
    check(resumed.restore_checkpoint(journey.store.load_checkpoint()) and resumed.character.stats.strength == 2 and resumed.character.experience == 0, "paid upgrade autosaves")
    journey.inventory.items.scroll_of_haste = 1
    journey.use_item("scroll_of_haste")
    check(resumed.restore_checkpoint(journey.store.load_checkpoint()) and resumed.haste and not resumed.inventory.items.has("scroll_of_haste"), "spell consumption and effect autosave together")
    journey.leave_town()
    journey.begin_turn()
    check(resumed.restore_checkpoint(journey.store.load_checkpoint()) and not resumed.haste and resumed.day == 2 and resumed.town_lock == "highwood", "day/rest and town departure autosave")
    # More lairs can exceed the original gold cap: leave surplus and recover it
    # after shopping, without fighting or receiving experience a second time.
    journey = fresh()
    journey.store = Store.new(path, journey.validate_checkpoint)
    journey.inventory.gold = 145
    enter(journey)
    journey.combat.simulation.spawn_remaining = 0
    for actor in journey.combat.simulation.actors.values():
        if actor.team == 2: actor.health = 0
    journey.return_to_map()
    check(journey.inventory.gold == 150 and journey.lair_loot.grassland_west.gold == 20, "surplus gold remains in cleared chest at carrying cap")
    journey.world.position = journey.town("highwood").position
    journey.enter_town("highwood")
    journey.open_service("smith")
    journey.buy_equipment("chainmail")
    journey.leave_town()
    journey.begin_turn()
    journey.world.position = Vector2i(57,63)
    enter(journey)
    check(journey.loot_open and journey.combat.simulation.outcome() == "victory" and journey.character.experience == 1, "cleared treasure can be revisited without combat or extra XP")
    check(resumed.restore_checkpoint(journey.store.load_checkpoint()) and resumed.loot_open, "revisited chest also resumes from disk")
    journey.return_to_map()
    check(journey.inventory.gold == 140 and not journey.has_treasure("grassland_west") and journey.character.experience == 1, "stored gold is recovered once after town spending")
    var broken_store: RefCounted = Store.new("user://missing-block/../", journey.validate_checkpoint)
    check(not broken_store.save_checkpoint(journey.checkpoint()), "failed storage reports failure instead of claiming saved")
    if failures == 0: print("PASS: full JSON/checksum roundtrip, entrance/defeat/partial-loot continuation, single rewards, exact 24 chests, atomic primary/backup, invalid/oversized saves, and town/item/upgrade/rest autosaves")
    quit(1 if failures else 0)
