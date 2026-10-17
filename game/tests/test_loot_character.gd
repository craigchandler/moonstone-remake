extends SceneTree

const Journey=preload("res://scripts/session/journey_session.gd")
const Fixture=preload("res://debug/fixtures/loot_character_fixture.gd")
var failures: int=0

func check(condition: bool, label: String) -> void:
    if not condition:failures+=1;push_error(label)

func _initialize() -> void:
    run_checks.call_deferred()

func run_checks() -> void:
    var host: Node=load("res://scenes/main.tscn").instantiate()
    host.saving_enabled=false
    root.add_child(host)
    host.set_physics_process(false)
    host.journey.restart(0x4d4f4f4e)
    var fixture: RefCounted=Fixture.new()
    for tick in range(1,241):
        host.elapsed=tick
        fixture.advance(host)
        host.set_physics_process(false)
        await process_frame
    for id in fixture.checks:check(fixture.checks[id],id)
    check(fixture.valid(),"complete UI exercise")
    # The map result is a real save checkpoint, without changed save versions.
    var j: RefCounted=host.journey
    var final: Dictionary=j.checkpoint()
    check(not j.validate_checkpoint(final).is_empty(),"Hawk result is saveable")
    check(j.restore_checkpoint(JSON.parse_string(JSON.stringify(final))) and j.checkpoint()==final,"Hawk map Continue preserves kit and chest")
    # Replay the actual saved loot result to cover level caps, life healing,
    # unsupported contexts, newly collected consumables and normal column exit.
    check(j.restore_checkpoint(JSON.parse_string(JSON.stringify(fixture.results.changed))),"restore changed loot")
    var before_reveal: Dictionary=j.lair_loot.duplicate(true)
    var reveal_id: String=j.world.definition.lairs[1].id
    check(j.use_item("gem_of_seeing",reveal_id) and j.revealed_lairs.has(reveal_id) and not j.inventory.items.has("gem_of_seeing") and j.lair_loot==before_reveal and j.looting(),"gem reveals another lair from loot without collecting or leaving")
    var held: Dictionary=j.snapshot()
    for id in ["ring_of_protection","talisman_of_the_wyrm","scroll_of_acquisition","scroll_of_the_wyrm","scroll_of_protection","unknown"]:
        j.inventory.items[id]=1
        var before: Dictionary=j.snapshot()
        check(not j.use_item(id) and j.snapshot()==before,"no consumption for passive/missing target: "+id)
    j.inventory.items=held.inventory.items.duplicate(true)
    j.store=load("res://scripts/session/journey_store.gd").new("user://loot-character-actions-test.json",j.validate_checkpoint)
    j.character.lives=4
    check(j.use_item("healing_potion") and j.character.lives==5 and not j.inventory.items.has("healing_potion"),"loot potion restores life at full health")
    check(j.store.load_checkpoint()==j.checkpoint(),"item action autosaves exact loot checkpoint to disk")
    check(j.take_loot("healing_potion"),"collect new potion")
    j.character.health=7
    check(j.use_item("healing_potion") and j.character.health==50,"newly looted potion usable immediately")
    j.character.experience=15
    check(j.upgrade_stat("strength") and j.upgrade_stat("endurance"),"other stats upgrade while looting")
    check(j.upgrade_stat("constitution") and j.upgrade_stat("constitution") and j.upgrade_stat("constitution"),"Constitution reaches original five cap")
    check(j.store.load_checkpoint()==j.checkpoint(),"stat action autosaves updated kit and remaining chest")
    j.character.experience=3
    check(not j.upgrade_stat("constitution") and not j.upgrade_stat("invented") and j.character.experience==3,"cap and invalid stat do not spend XP")
    var character: Dictionary=j.character.snapshot()
    var chest: Dictionary=j.available_loot()
    j.prepare_loot();j.settle_battle()
    check(j.character.snapshot()==character,"settlement cannot overwrite healed/upgraded kit")
    check(j.return_to_map(false) and j.character.snapshot()==character and j.lair_loot[j.world.definition.lairs[0].id]==chest,"ordinary exit retains kit and remaining loot")
    # An apparent victory is not enough: it must have reached the loot phase.
    j=Journey.new(host.definition,host.rules,2)
    j.inventory.items={"healing_potion":1,"scroll_of_haste":1};j.character.experience=3
    j.world.position=host.definition.lairs[0].position
    j.confirm_location(host.definition.lairs[0].id)
    check(not j.use_item("healing_potion") and not j.upgrade_stat("strength"),"live combat character actions blocked")
    j.combat.simulation.spawn_remaining=0
    for actor in j.combat.simulation.actors.values():
        if actor.team==2:actor.health=0
    check(not j.use_item("scroll_of_haste") and not j.upgrade_stat("strength"),"unopened/unsettled victory cannot use character actions")
    j.prepare_loot();j.quest.notice=true
    check(not j.use_item("scroll_of_haste") and not j.upgrade_stat("strength"),"quest acknowledgement cannot be bypassed")
    j.quest.notice=false;j.combat.simulation.actors[1].health=0
    check(not j.looting() and not j.use_item("scroll_of_haste") and not j.upgrade_stat("strength"),"defeat cannot use loot character actions")
    host.queue_free()
    await process_frame
    if failures==0:print("PASS: loot XP/items, actual mouse/keyboard routing, Continue, frozen battle, stat caps, immediate consumables, life healing, passive/context guards and safe normal/Hawk exits")
    quit(1 if failures else 0)
