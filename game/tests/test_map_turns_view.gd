extends SceneTree
const Store=preload("res://scripts/session/journey_store.gd")
var failures: int=0
func check(ok: bool,label: String) -> void:
    if not ok:
        failures+=1;push_error(label)
func key(code: Key,down: bool,echo: bool=false) -> void:
    var e:=InputEventKey.new();e.keycode=code;e.physical_keycode=code;e.pressed=down;e.echo=echo
    Input.parse_input_event(e);Input.flush_buffered_events()
func press(code: Key) -> void:
    key(code,true);key(code,false)
func _initialize() -> void:run.call_deferred()
func run() -> void:
    var view: Node=load("res://scenes/main.tscn").instantiate()
    view.definition=load("res://scripts/content/world_definition.gd").new()
    view.saving_enabled=false
    root.add_child(view);view.set_physics_process(false)
    await process_frame
    view.save_store=Store.new("user://unit-map-turns-view.json",view.journey.validate_checkpoint)
    view.journey.store=view.save_store
    var j: RefCounted=view.journey
    j.world.position=Vector2i(250,160);j.travel_spent=j.travel_allowance()-1;j.character.health=12
    key(KEY_LEFT,true)
    for t in range(2):view._physics_process(0.02)
    check(j.turn_pending and j.day==2 and j.world.position==Vector2i(249,160),"Physical held direction exhausts exactly one player turn")
    var boundary: Dictionary=j.checkpoint()
    for t in range(80):view._physics_process(0.02)
    check(j.checkpoint()==boundary,"Held direction freezes at turn-end message")
    press(KEY_I);press(KEY_P);press(KEY_F1)
    check(view.inventory_view==null and view.practice_view==null and view.arena==null,"Turn message guards inventory/practice shortcuts")
    key(KEY_E,true,true);key(KEY_E,false)
    check(j.checkpoint()==boundary,"Key-repeat E cannot skip the message or spend another round")
    view.show_menu(view.save_store.load_checkpoint());press(KEY_C)
    check(view.menu_view==null and j.checkpoint()==boundary,"Real saved menu Continue restores pending turn and exact health/clock")
    press(KEY_ENTER)
    check(not j.turn_pending and j.day==2 and j.character.health==15,"Enter begins without another advance or heal")
    for t in range(20):view._physics_process(0.02)
    check(j.world.position==Vector2i(249,160) and j.travel_spent==0,"Arrow held through Enter must be released before new movement")
    key(KEY_LEFT,false);view._physics_process(0.02)
    key(KEY_LEFT,true)
    for t in range(2):view._physics_process(0.02)
    key(KEY_LEFT,false)
    check(j.world.position==Vector2i(248,160) and j.travel_spent==1,"Released/repressed direction moves in the new turn")
    press(KEY_E)
    check(j.turn_pending and j.day==3 and j.turn_reason=="rest","E uses the same single-turn boundary")
    var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true;click.position=Vector2(320,250)
    Input.parse_input_event(click);Input.flush_buffered_events();click=click.duplicate();click.pressed=false;Input.parse_input_event(click);Input.flush_buffered_events()
    check(not j.turn_pending and j.day==3,"Click acknowledges without another turn")
    j.world.position=j.town("highwood").position;j.enter_town("highwood");view.show_town()
    press(KEY_ESCAPE)
    check(view.town_view==null and j.turn_pending and j.turn_reason=="town" and j.day==4,"Town Exit uses the same visible transition")
    press(KEY_SPACE);press(KEY_E);press(KEY_ENTER)
    check(j.day==5 and j.calendar().moon_phase==1 and view.art.moon_frames.size()==8 and view.art.knight_active!=null,"Four completed player rounds advance recovered moon art once")
    view.queue_free();await process_frame
    if failures==0:print("PASS: actual key/mouse turn boundary, no held-input round burning, guarded overlays, disk/menu paused Continue, release-before-move, rest/town transitions and original lunar art")
    quit(1 if failures else 0)
