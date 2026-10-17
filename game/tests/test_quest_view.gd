extends SceneTree
var failures: int=0
func check(ok: bool,label: String) -> void:
    if not ok:failures+=1;push_error(label)
func press(key: Key) -> void:
    var e:=InputEventKey.new();e.keycode=key;e.physical_keycode=key;e.pressed=true
    Input.parse_input_event(e);Input.flush_buffered_events();e=e.duplicate();e.pressed=false;Input.parse_input_event(e);Input.flush_buffered_events()
func click(point: Vector2) -> void:
    var e:=InputEventMouseButton.new();e.position=point;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=true
    root.push_input(e,true);e=e.duplicate();e.pressed=false;root.push_input(e,true)
func _initialize() -> void:run.call_deferred()
func walk_henge(host: Node) -> void:
    host.journey.world.position=Vector2i(88,147)
    for step in range(64):
        host.travel(Vector2i.DOWN)
        host.enter_location("stonehenge")
        if host.henge_view!=null or host.quest_view!=null:return
    check(false,"real Stonehenge routing")
func run() -> void:
    var old_mouse: int=Input.mouse_mode
    var host: Node=load("res://scenes/main.tscn").instantiate()
    host.saving_enabled=false;host.definition=host.definition.duplicate();host.definition.rival_turns=false;root.add_child(host);host.set_physics_process(false)
    await process_frame
    var j: RefCounted=host.journey
    j.owned_keys=15;j.world.position=Vector2i(152,89)
    for step in range(64):
        host.travel(Vector2i.DOWN)
        host.enter_location("valley_guardian")
        if host.arena!=null:break
    check(host.arena!=null and j.combat!=null,"walk into Valley with four actual carried keys")
    host.arena.set_physics_process(false);j.combat.simulation.spawn_remaining=0
    for actor in j.combat.simulation.actors.values():
        if actor.team==2:actor.health=0
    # Exercise first-call settlement as well as later already-settled routing.
    host.show_loot()
    check(host.quest_view!=null and host.loot_view==null and j.quest.notice and j.quest.stones!=0 and j.owned_keys==0,"source Guardian message replaces generic new loot on first settlement")
    var before: Dictionary=j.checkpoint()
    for key in [KEY_R,KEY_F3,KEY_P,KEY_TAB,KEY_RIGHT]:press(key)
    check(j.checkpoint()==before and host.menu_view==null and host.practice_view==null,"reward message guards map shortcuts")
    click(Vector2(300,250))
    check(host.quest_view==null and host.arena==null and j.world.cleared.has("valley_guardian") and not j.quest.notice,"acknowledging source message returns once")
    var stone: int=j.quest.stones
    press(KEY_I)
    var pack: Node=host.inventory_view
    check(pack!=null,"normal inventory remains available")
    var stone_slot: Dictionary={}
    for slot in pack.inventory_slots():
        if slot.id in j.quest_rules.stone_ids:stone_slot=slot;break
    check(not stone_slot.is_empty() and stone_slot.rect.size==Vector2(30,32),"recovered moonstone icon shown at original first-object position")
    before=j.checkpoint();click(stone_slot.rect.get_center());press(KEY_SPACE)
    check(j.checkpoint()==before and j.quest.stones==stone,"carried moonstone is not a consumable spell")
    press(KEY_I)
    while j.quest_rules.matches(stone,j.calendar().moon_phase):j.rest();j.begin_turn()
    walk_henge(host)
    check(host.henge_view!=null and host.quest_view==null and j.henge.phase=="greeting","wrong phase retains Danu's original offering")
    press(KEY_SPACE)
    var henge: Node=host.henge_view
    check(henge.rows().all(func(id):return not id in j.quest_rules.stone_ids),"moonstones cannot be offered to Danu")
    for slot in henge.slots():
        if slot.id in j.quest_rules.stone_ids:click(slot.rect.get_center())
    check(j.henge.phase=="offering" and j.quest.stones==stone,"clicking a quest object cannot donate it")
    press(KEY_ESCAPE);press(KEY_ESCAPE);press(KEY_ENTER)
    while not j.quest_rules.matches(stone,j.calendar().moon_phase):j.rest();j.begin_turn()
    walk_henge(host)
    check(host.quest_view!=null and host.henge_view==null and j.quest.ending.stage=="message","matching phase routes original quest text instead of item offer")
    press(KEY_SPACE);check(j.quest.ending.stage=="message","early confirmation respects source wait")
    for tick in range(20):host.quest_view.advance()
    var save: Dictionary=j.checkpoint()
    var clone: RefCounted=load("res://scripts/session/journey_session.gd").new(host.definition,host.rules,2)
    check(clone.restore_checkpoint(JSON.parse_string(JSON.stringify(save))) and clone.checkpoint()==save,"quest message is a compatible Continue checkpoint")
    press(KEY_SPACE)
    check(j.quest.ending.stage=="ready" and j.quest.stones==stone and j.character.experience==3,"one ending handoff; no extra stone/XP/blessing")
    before=j.checkpoint()
    for key in [KEY_F3,KEY_I,KEY_E,KEY_P,KEY_R]:press(key)
    check(j.checkpoint()==before and host.arena==null and host.inventory_view==null,"finished quest cannot resume map activity")
    click(Vector2(160,250))
    check(host.menu_view==null and j.quest.ending.stage=="ready","film ignores accidental mouse clicks")
    press(KEY_ESCAPE)
    check(j.quest.ending.stage=="complete" and host.menu_view!=null and host.quest_view==null,"explicit key skip completes the film and returns to menu")
    before=j.checkpoint()
    check(host.menu_view!=null and host.quest_view==null,"completed film leaves existing journey menu")
    press(KEY_C)
    check(host.menu_view==null and host.quest_view!=null and j.checkpoint()==before,"Continue resumes ready ending state without another reward")
    host.queue_free();await process_frame
    if DisplayServer.get_name()!="headless":check(Input.mouse_mode==old_mouse,"nested quest/menu sword cursor restores owner")
    if failures==0:print("PASS: actual Valley/Stonehenge key/mouse routes, first-settlement message, original carried icon, non-consumable/non-offerable moonstone, wrong-phase offering, guarded saved victory, column menu and exact completed Continue")
    quit(1 if failures else 0)
