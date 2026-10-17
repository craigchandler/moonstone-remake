extends SceneTree
var failures: int=0
var checks: int=0
func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failures+=1;push_error(label)
func press(key: Key) -> void:
    var event:=InputEventKey.new();event.keycode=key;event.physical_keycode=key;event.pressed=true
    Input.parse_input_event(event);Input.flush_buffered_events();event=event.duplicate();event.pressed=false;Input.parse_input_event(event);Input.flush_buffered_events()
func click(point: Vector2) -> void:
    var event:=InputEventMouseButton.new();event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true
    root.push_input(event,true);event=event.duplicate();event.pressed=false;root.push_input(event,true)
func _initialize() -> void:run.call_deferred()
func run() -> void:
    var host: Node=load("res://scenes/main.tscn").instantiate();host.saving_enabled=false
    root.add_child(host);host.set_physics_process(false);await process_frame
    var j: RefCounted=host.journey
    check(host.definition.rival_turns and host.rival_markers().size()==3,"ordinary production scene enables three rivals")
    check(host.art.map_icons["4"].get_size()==Vector2(8,10) and host.art.map_icons["9"].get_size()==Vector2(8,10) and host.art.map_icons.has("33"),"original inactive/active/fallen knight icon assets")
    var before: Dictionary=j.checkpoint()
    press(KEY_E)
    check(j.rivals.active==1 and j.day==1 and not j.turn_pending,"E hands over to first rival")
    press(KEY_I);press(KEY_P);press(KEY_TAB);press(KEY_ENTER)
    check(host.inventory_view==null and host.practice_view==null and j.rivals.active==1 and j.mode==&"competitive","human shortcuts cannot bypass rival turn")
    for tick in range(50):host._physics_process(0.02)
    var halfway: Dictionary=j.checkpoint()
    check(host.rival_markers()[0]==j.rivals.records[0].position and j.rivals.records[0].position!=Vector2i(300,100),"icon follows actual rival movement")
    host.show_menu(halfway)
    for tick in range(80):host._physics_process(0.02)
    check(j.checkpoint()==halfway,"menu pauses rival animation and authoritative turn state")
    host.menu_choice("continue")
    check(host.menu_view==null and j.checkpoint()==halfway,"Continue resumes exact rival turn")
    var seen: Dictionary={}
    for tick in range(2600):
        seen[j.rivals.active]=true
        host._physics_process(0.02)
        if j.turn_pending:break
    check(seen.has(1) and seen.has(2) and seen.has(3) and j.day==2 and j.turn_pending,"ordinary scene plays all three slots before new-round prompt")
    var ended: Dictionary=j.checkpoint()
    for tick in range(50):host._physics_process(0.02)
    check(j.checkpoint()==ended,"new-round message cannot auto-spend another round")
    click(Vector2(300,240));check(not j.turn_pending and j.day==2,"mouse acknowledges once after rivals finish")
    # Stage a close pursuing rival, then let ordinary map stepping make contact.
    j.inventory.items.scroll_of_protection=1
    j.rest();var r: RefCounted=j.rivals
    r.records[0].position=j.world.position+Vector2i(12,0)
    r.target="player";r.goal=j.world.position;r.budget=96;r.walk.assign([12,0,-1,0,12,0])
    for tick in range(30):
        host._physics_process(0.02)
        if j.attack_notice:break
    check(j.pending_attack==r.records[0].id and j.attack_notice and host.arena==null,"actual rival movement produces incoming warning")
    press(KEY_SPACE)
    check(host.inventory_view!=null and not j.attack_notice,"warning input opens original inventory")
    if host.inventory_view!=null:
        var view: Node=host.inventory_view
        click(view.row_rect(view.selected).get_center())
    check(host.inventory_view==null and host.arena==null and j.pending_attack=="" and j.rivals.active==1 and r.spent==r.budget,"sword click avoids battle while finishing that rival's spent turn")
    # Actual icon entry, upgraded opponent and source-style duel loot sheet.
    r.active=0;r.clear_path();j.turn_reason=""
    var row: Dictionary=r.records[2];j.world.position=row.position
    row.character.armour="chainmail";row.character.health=30;row.inventory.items.healing_potion=1
    host.enter_location(row.id)
    check(host.arena!=null and j.combat.simulation.actors[10].maximum==30,"confirmed third icon starts that saved rival's duel")
    if host.arena!=null:
        host.arena.set_physics_process(false)
        for actor in j.combat.simulation.actors.values():
            if actor.team==2:actor.health=0;actor.down_remaining=0
        host.show_loot()
        check(host.loot_view!=null and j.available_loot().items=={"healing_potion":1} and row.character.lives==4,"duel loot shows actual defeated rival possession")
        var view: Node=host.loot_view
        view.selected=view.rows().find("healing_potion")
        click(view.row_rect(view.selected).get_center())
        check(j.inventory.items.get("healing_potion",0)==1 and not j.available_loot().items.has("healing_potion"),"original sword cursor takes actual rival item once")
        host.return_to_map(false)
    host.queue_free();await process_frame
    if failures==0:print("PASS: ",checks," production UI checks; E/all three slots/clock, correct moving icons, menu pause/Continue, guarded input, pursuing contact/Protection and actual third-rival duel/loot click")
    quit(1 if failures else 0)
