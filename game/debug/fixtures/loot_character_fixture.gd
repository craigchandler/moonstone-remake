extends RefCounted

# Staged victory and kit; all subsequent clicks/keys use the real UI and rules.
var results: Dictionary={}
var checks: Dictionary={}
var frozen: Dictionary={}
var destination:=Vector2i.ZERO

func check(id: String, condition: bool) -> void:
    checks[id]=condition

func press(host: Node, key: Key) -> void:
    var event:=InputEventKey.new()
    event.keycode=key; event.physical_keycode=key; event.pressed=true
    host.get_viewport().push_input(event,true)
    event=event.duplicate();event.pressed=false
    host.get_viewport().push_input(event,true)

func click(host: Node, point: Vector2) -> void:
    var event:=InputEventMouseButton.new()
    event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true
    host.get_viewport().push_input(event,true)
    event=event.duplicate();event.pressed=false
    host.get_viewport().push_input(event,true)

func carried(host: Node, id: String) -> Vector2:
    var v: Node=host.loot_view
    for slot in v.pack_slots(host.journey.inventory.items,host.journey.owned_keys,0):
        if slot.id==id:return slot.rect.get_center()
    return Vector2(-1,-1)

func advance(host: Node) -> void:
    var j: RefCounted=host.journey
    var site: Dictionary=host.definition.lairs[0]
    match host.elapsed:
        1:
            j.character.experience=2
            j.character.health=5
            j.inventory.items={"healing_potion":2,"scroll_of_haste":1,"scroll_of_the_hawk":1,"gem_of_seeing":1,"ring_of_protection":1}
            j.world.position=site.position
            j.lair_loot[site.id]={"kind":3,"gold":12,"keys":0,"items":{"healing_potion":1}}
            host.enter_location(site.id)
            host.arena.set_physics_process(false)
            j.combat.simulation.spawn_remaining=0
            for actor in j.combat.simulation.actors.values():
                if actor.team==2:actor.health=0;actor.down_remaining=0
            host.show_loot()
            frozen=j.combat.simulation.snapshot()
            results.initial=j.checkpoint()
            check("victory XP available immediately",j.character.experience==3 and j.looting())
        20:
            click(host,host.loot_view.stat_rect(1).get_center())
            check("click Constitution spends XP and adds health",j.character.stats.constitution==2 and j.character.experience==0 and j.character.health==15)
        45:
            click(host,carried(host,"healing_potion"))
            check("carried potion heals once",j.character.health==50 and j.inventory.items.healing_potion==1)
        65:
            click(host,carried(host,"scroll_of_haste"))
            check("carried Haste scroll",j.haste and not j.inventory.items.has("scroll_of_haste"))
            var copy: RefCounted=load("res://scripts/session/journey_session.gd").new(host.definition,host.rules,2)
            var saved: Dictionary=j.checkpoint()
            check("Continue retains loot actions",copy.restore_checkpoint(JSON.parse_string(JSON.stringify(saved))) and copy.checkpoint()==saved)
            copy.prepare_loot();copy.settle_battle()
            check("Continue never reawards spent XP",copy.character.experience==0 and copy.character.health==50)
            results.changed=saved
        80:
            click(host,carried(host,"healing_potion"))
            check("full potion kept",j.inventory.items.healing_potion==1)
        95:
            press(host,KEY_3);press(host,KEY_SPACE)
            check("keyboard stats reject unaffordable purchase",host.loot_view.character_view.tab==2 and j.character.stats.strength==1 and j.character.experience==0)
        110:
            press(host,KEY_2)
            check("no shops opened from loot",host.loot_view.character_view.tab==2 and j.service.is_empty())
            press(host,KEY_ESCAPE)
            check("character exit returns to loot",host.loot_view.character_view==null and j.looting())
        125:
            click(host,carried(host,"gem_of_seeing"))
            check("gem target without consumption",host.loot_view.character_view.target_item=="gem_of_seeing" and j.inventory.items.gem_of_seeing==1)
        130:press(host,KEY_ESCAPE)
        135:
            press(host,KEY_ESCAPE)
            check("target cancellation keeps gem and loot",host.loot_view.character_view==null and j.inventory.items.gem_of_seeing==1 and j.looting())
        145:
            press(host,KEY_TAB)
            check("keyboard pack access",host.loot_view.character_view.tab==0)
        160:press(host,KEY_ESCAPE)
        175:click(host,carried(host,"scroll_of_the_hawk"))
        185:
            click(host,host.loot_view.character_view.target_rect.position+Vector2(300,200))
        195:
            press(host,KEY_ESCAPE);press(host,KEY_ESCAPE)
            check("Hawk cancellation keeps scroll",j.inventory.items.scroll_of_the_hawk==1 and j.looting())
        205:click(host,carried(host,"scroll_of_the_hawk"))
        215:
            click(host,host.loot_view.character_view.target_rect.position+Vector2(300,200))
            destination=host.loot_view.character_view.cursor
            check("combat stays frozen",j.combat.simulation.snapshot()==frozen)
        225:
            press(host,KEY_SPACE)
            check("Hawk closes loot and arena",host.loot_view==null and host.arena==null and j.combat==null and not j.loot_open)
            check("Hawk moves and consumes once",j.world.position==destination and not j.inventory.items.has("scroll_of_the_hawk"))
            check("remaining chest and settled character retained",j.lair_loot[site.id]==results.initial.lair_loot[site.id] and j.character.health==50 and j.character.stats.constitution==2 and j.character.experience==0)
            results.final=j.checkpoint()
            host.set_physics_process(true)
    host.queue_redraw()

func valid() -> bool:
    return checks.size()==18 and not checks.values().has(false)

func finish(host: Node) -> void:
    results.checks=checks
    print("LOOT_CHARACTER_STATE=",JSON.stringify(results))
    if not valid():push_error("Loot character fixture failed");host.get_tree().quit(1);return
    print("PASS: loot XP/item mouse and keyboard actions, Continue, cancellation, frozen combat and safe Hawk exit")
    host.get_tree().quit()
