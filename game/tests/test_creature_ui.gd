extends SceneTree

var failures: int=0

func check(ok: bool,label: String) -> void:
    if not ok:
        failures+=1
        push_error(label)

func press(key: Key) -> void:
    var event:=InputEventKey.new()
    event.keycode=key
    event.physical_keycode=key
    event.pressed=true
    Input.parse_input_event(event)
    Input.flush_buffered_events()
    event=event.duplicate()
    event.pressed=false
    Input.parse_input_event(event)
    Input.flush_buffered_events()

func click(point: Vector2) -> void:
    var event:=InputEventMouseButton.new()
    event.position=point
    event.button_index=MOUSE_BUTTON_LEFT
    event.button_mask=MOUSE_BUTTON_MASK_LEFT
    event.pressed=true
    root.push_input(event,true)
    event=event.duplicate()
    event.pressed=false
    event.button_mask=0
    root.push_input(event,true)

func ambush(view: Node) -> void:
    view.journey.inventory.items.scroll_of_protection=2
    var site: Dictionary=view.journey.world.lair("roaming_black_knight")
    view.journey.world.position=site.position # Explicit contact fixture; terrain wait must not move the routed knight out of a boundary-only setup.
    if not view.journey.rivals.records.is_empty():
        view.journey.begin_rival_encounter("roaming_black_knight",true)
        return
    for step in range(8):
        view.travel(Vector2i.RIGHT)
        if not view.journey.pending_attack.is_empty(): break

func _initialize() -> void:
    run_checks.call_deferred()

func run_checks() -> void:
    var view: Node=load("res://scenes/main.tscn").instantiate()
    view.debug_mode=true
    view.saving_enabled=false
    root.add_child(view)
    view.set_physics_process(false)
    await process_frame
    var initial: Dictionary=view.journey.snapshot()
    press(KEY_P)
    check(view.practice_view!=null and view.practice_view.choices.size()==12,"P exposes all creatures with pictures")
    var choices: Array=view.practice_view.choices.duplicate()
    click(view.practice_view.row_rect(10).get_center())
    check(view.practice_view==null and view.arena!=null and view.arena.encounter==&"guardian_fight","pictured Guardian selection starts the actual encounter")
    view.arena.set_physics_process(false)
    press(KEY_F3)
    check(view.arena==null and view.journey.snapshot()==initial,"practice cannot alter journey/rewards")
    ambush(view)
    check(view.journey.attack_notice and view.arena==null and view.inventory_view==null,"message precedes inventory and combat")
    click(Vector2(320,220))
    check(view.inventory_view!=null and not view.journey.attack_notice and view.arena==null,"clicking warning opens the inventory")
    check(view.inventory_view.rows()[view.inventory_view.selected]=="scroll_of_protection","protection scroll is selected for the decision")
    click(view.inventory_view.row_rect(view.inventory_view.selected).get_center())
    check(view.inventory_view==null and view.arena==null and view.journey.inventory.items.scroll_of_protection==1 and view.journey.world.cleared.is_empty(),"click scroll avoids fight and spends exactly one")
    view.journey.world.entry_lock=""
    ambush(view)
    press(KEY_SPACE)
    check(view.inventory_view!=null,"keyboard acknowledges warning")
    press(KEY_ESCAPE)
    check(view.inventory_view==null and view.arena!=null and view.arena.encounter==&"black_knight_fight" and view.journey.inventory.items.scroll_of_protection==2,"leaving inventory starts fight and preserves scroll")
    view.arena.set_physics_process(false)
    press(KEY_F3)
    var before: Dictionary=view.journey.snapshot()
    for choice in choices:
        view.show_training(StringName(choice))
        view.arena.set_physics_process(false)
        check(view.arena.encounter==StringName(choice),"every practice entry is reachable: "+choice)
        press(KEY_F3)
    check(view.journey.snapshot()==before,"all practice entries preserve authoritative journey state")
    # Quest keys share the pack and loot controls without entering random magic bands.
    var key_site: Dictionary=view.definition.lairs[0]
    view.journey.world.active_lair=key_site.id
    view.journey.start_site_combat()
    view.journey.combat.simulation.spawn_remaining=0
    for actor in view.journey.combat.simulation.actors.values():
        if actor.team==2:actor.health=0
    view.journey.prepare_loot()
    view.journey.lair_loot[key_site.id].keys=8
    view.show_lair()
    view.arena.set_physics_process(false)
    view.show_loot()
    view.loot_view.selected=view.loot_view.rows().find("key_forest")
    click(view.loot_view.row_rect(view.loot_view.selected).get_center())
    check(view.journey.owned_keys==8 and view.journey.available_loot().keys==0,"actual loot click transfers a regional key")
    view.return_to_map()
    await process_frame
    view.journey.owned_keys=15
    for id in view.journey.loot_rules.items:view.journey.inventory.items[id]=1
    view.show_inventory()
    check(view.inventory_view.rows().size()==14 and view.inventory_view.row_rect(13).end.y<366,"full ten-item pack and four keys fit above footer")
    view.inventory_view.selected=view.inventory_view.rows().find("key_wastes")
    click(view.inventory_view.row_rect(view.inventory_view.selected).get_center())
    check(view.journey.owned_keys==15,"inspecting carried key never consumes it")
    view.queue_free()
    await process_frame
    for encounter in ["hammer_lair","beast_lair","rat_lair","mud_lair","dragon_fight","guardian_fight","black_knight_fight"]:
        for mirrored in [false,true]:
            var arena: Node=load("res://scenes/arena.tscn").instantiate()
            arena.encounter=StringName(encounter)
            arena.pack_showcase=true
            arena.mirror_demo=mirrored
            root.add_child(arena)
            arena.set_physics_process(false)
            for step in range(arena.demo_length()):
                arena.advance_pack_showcase()
                arena.animator.update(arena.session.simulation.actors,arena.rule_set,arena.art)
            check(arena.session.simulation.outcome()=="victory","presentation fixture completes via ordinary lunge in both facings: "+encounter)
            check(arena.session.simulation.actors[10].down_remaining==0,"original defeat reaches final corpse: "+encounter)
            arena.queue_free()
    await process_frame
    if failures==0: print("PASS: pictured twelve-fight practice picker, actual mouse/key choices, practice isolation, incoming-knight warning -> pack -> explicit scroll avoidance or battle-on-close")
    quit(1 if failures else 0)
