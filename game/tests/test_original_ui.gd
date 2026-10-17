extends SceneTree

const Journey=preload("res://scripts/session/journey_session.gd")
var failures: int=0

func check(condition: bool, label: String) -> void:
    if not condition: failures+=1; push_error(label)

func click(point: Vector2) -> void:
    var event:=InputEventMouseButton.new()
    event.position=point; event.button_index=MOUSE_BUTTON_LEFT; event.pressed=true
    root.push_input(event,true)
    event=event.duplicate(); event.pressed=false
    root.push_input(event,true)

func motion(point: Vector2) -> void:
    var event:=InputEventMouseMotion.new()
    event.position=point
    root.push_input(event,true)

func press(key: Key) -> void:
    var event:=InputEventKey.new()
    event.keycode=key; event.physical_keycode=key; event.pressed=true
    Input.parse_input_event(event); Input.flush_buffered_events()
    event=event.duplicate(); event.pressed=false
    Input.parse_input_event(event); Input.flush_buffered_events()

func _initialize() -> void:
    run.call_deferred()

func run() -> void:
    var original_mode: int=Input.mouse_mode
    var view: Node=load("res://scenes/main.tscn").instantiate()
    view.saving_enabled=false
    root.add_child(view)
    view.set_physics_process(false)
    await process_frame
    for x in [172,468]:
        view.show_inventory()
        check((DisplayServer.get_name()=="headless" or Input.mouse_mode==Input.MOUSE_MODE_HIDDEN),"original sword pointer owns cursor only while panel open")
        motion(Vector2(x,260))
        check(view.inventory_view.hovered=="EXIT","hovering either single arch column labels EXIT")
        click(Vector2(x,260))
        check(view.inventory_view==null and Input.mouse_mode==original_mode,"either character column closes and restores system pointer")
    view.journey.inventory.items={"gem_of_seeing":1}
    view.show_inventory()
    press(KEY_SPACE)
    var target: String=view.inventory_view.rows()[0]
    var treasure: Dictionary=view.journey.lair_loot[target].duplicate(true)
    click(view.inventory_view.row_rect(0).get_center())
    check(view.inventory_view.inspection==target and not view.inventory_view.single_panel() and view.journey.lair_loot[target]==treasure and view.journey.inventory.items.is_empty(),"Gem selection consumes one and opens the actual chest preview without taking treasure")
    press(KEY_ESCAPE)
    check(view.inventory_view!=null and view.inventory_view.single_panel() and view.inventory_view.inspection.is_empty(),"Escape returns from revealed chest to centred character sheet")
    view.close_inventory()
    view.journey.inventory.items={"healing_potion":7,"ring_of_protection":3,"scroll_of_protection":5}
    view.show_inventory()
    var pack: Node=view.inventory_view
    check(pack.inventory_slots().filter(func(slot):return slot.id=="ring_of_protection").size()==3,"carried rings draw individually")
    check(pack.pack_pages(view.journey.inventory.items)==3,"overflow remains reachable without dropping or capping possessions")
    pack.page=2
    var slot: Dictionary=pack.inventory_slots().filter(func(item):return item.id=="scroll_of_protection")[0]
    check(slot.ordinal==4,"third page exposes fifth scroll rather than duplicating first two")
    var before: Dictionary=view.journey.inventory.duplicate(true)
    click(slot.rect.get_center())
    check(view.journey.inventory==before,"scroll outside its ambush context stays owned")
    pack.page=0
    pack.help_visible=true
    click(pack.row_rect(pack.rows().find("healing_potion")).get_center())
    check(not pack.help_visible and view.journey.inventory==before,"clicking help dismisses it without using an underlying item")
    pack.selected=pack.rows().find("ring_of_protection")
    click(pack.row_rect(pack.selected).get_center())
    check(view.journey.inventory==before,"passive ring inspection has no use or equip transaction")
    motion(Vector2(30,350))
    check(pack.hovered.is_empty(),"empty black space clears action caption")
    view.close_inventory()
    view.journey.inventory={"gold":10,"items":{}}
    var site: String=view.definition.lairs[0].id
    view.journey.world.active_lair=site
    view.journey.start_site_combat()
    view.journey.combat.simulation.spawn_remaining=0
    for actor in view.journey.combat.simulation.actors.values():
        if actor.team==2: actor.health=0
    view.show_lair()
    view.arena.set_physics_process(false)
    view.show_loot()
    view.journey.lair_loot[site]={"kind":3,"gold":28,"keys":8,"items":{"healing_potion":2}}
    var loot: Node=view.loot_view
    var potions: Array=loot.loot_slots().filter(func(item):return item.id=="healing_potion")
    check(potions.size()==2,"loot has separate clickable icons for repeated objects")
    click(potions[1].rect.get_center())
    check(view.journey.inventory.items.healing_potion==1 and view.journey.available_loot().items.healing_potion==1,"clicking duplicate transfers exactly one real object")
    view.journey.lair_loot[site].items.ring_of_protection=1
    var ring: Dictionary=loot.loot_slots().filter(func(item):return item.id=="ring_of_protection")[0]
    var hp: int=view.journey.character.health
    click(ring.rect.get_center())
    check(view.journey.character.health==hp+20 and view.journey.inventory.items.ring_of_protection==1,"click-to-loot applies carried ring health immediately")
    motion(Vector2(316,260))
    check(loot.hovered=="EXIT","shared central loot column labels EXIT")
    click(Vector2(316,260))
    check(view.loot_view==null and view.arena==null,"central loot column returns to map")
    check(view.journey.inventory.gold==10 and view.journey.owned_keys==0 and view.journey.has_treasure(site),"exit does not auto-collect gold, keys or unselected items")
    var saved: Dictionary=view.journey.checkpoint()
    var resumed: RefCounted=Journey.new(view.definition,view.rules,7)
    check(resumed.restore_checkpoint(saved) and resumed.lair_loot==view.journey.lair_loot and resumed.inventory==view.journey.inventory,"partly looted column exit survives save/continue")
    # Walk back into the cleared site: no enemies, extra XP or reroll.
    var xp: int=resumed.character.experience
    var pile: Dictionary=resumed.lair_loot[site].duplicate(true)
    resumed.world.position=resumed.world.lair(site).position+Vector2i(12,0)
    resumed.world.entry_lock=""
    for tick in range(50):
        resumed.travel(Vector2i.LEFT)
        if resumed.confirm_location(site):break
    check(resumed.loot_open and resumed.combat.simulation.outcome()=="victory" and resumed.character.experience==xp and resumed.available_loot()==pile,"untaken objects reopen as the same chest without another battle or XP")
    check(Input.mouse_mode==original_mode,"loot column restores system pointer")
    view.queue_free()
    await process_frame
    if failures==0: print("PASS: original icon transfers/duplicates, passive carried benefits, overflow pages, help input, hover captions, single/shared column exits, cursor restoration and saved untaken chest revisit")
    quit(1 if failures else 0)
