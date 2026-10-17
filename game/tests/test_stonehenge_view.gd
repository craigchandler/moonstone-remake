extends SceneTree
var failures: int=0
func check(ok: bool,label: String) -> void:
    if not ok:failures+=1;push_error(label)
func press(key: Key) -> void:
    var event:=InputEventKey.new();event.keycode=key;event.physical_keycode=key;event.pressed=true
    Input.parse_input_event(event);Input.flush_buffered_events()
    event=event.duplicate();event.pressed=false;Input.parse_input_event(event);Input.flush_buffered_events()
func click(point: Vector2) -> void:
    var event:=InputEventMouseButton.new();event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true
    root.push_input(event,true);event=event.duplicate();event.pressed=false;root.push_input(event,true)
func _initialize() -> void:run.call_deferred()
func run() -> void:
    var mode: int=Input.mouse_mode
    var host: Node=load("res://scenes/main.tscn").instantiate()
    host.saving_enabled=false;host.definition=host.definition.duplicate();host.definition.rival_turns=false;root.add_child(host);host.set_physics_process(false)
    await process_frame
    var j: RefCounted=host.journey
    var audio: Node=root.get_node("MoonstoneAudio")
    audio.trace_enabled=true;audio.trace_path="user://unit-henge-audio.json";audio.played.clear()
    j.inventory.items={"healing_potion":2,"ring_of_protection":1,"scroll_of_haste":9}
    j.owned_keys=15;j.character.health=7;j.character.lives=3;j.character.experience=3
    j.world.position=Vector2i(88,147)
    for step in range(64):
        host.travel(Vector2i.DOWN)
        host.enter_location("stonehenge")
        if host.henge_view!=null:break
    var view: Node=host.henge_view
    check(view!=null and host.arena==null and j.henge.phase=="greeting","real map entry routes Stonehenge screen")
    if view==null:host.queue_free();quit(1);return
    var before: Dictionary=j.checkpoint()
    for key in [KEY_F3,KEY_P,KEY_R,KEY_TAB,KEY_RIGHT]:press(key)
    host.show_inventory()
    check(j.checkpoint()==before and host.inventory_view==null and host.practice_view==null and host.menu_view==null,"map shortcuts cannot bypass Stonehenge")
    click(Vector2(300,180))
    check(j.henge.phase=="offering","original message advances to offering")
    check(view.rows().size()==3,"only carried magic items are actionable")
    click(Vector2(504,230))
    check(j.henge.phase=="offering" and j.owned_keys==15,"keys remain visible but cannot be offered")
    var slots: Array=view.slots()
    var potion: Rect2
    for slot in slots:
        if slot.id=="healing_potion":potion=slot.rect;break
    click(potion.get_center())
    check(j.henge.phase=="prelude" and j.inventory.items.healing_potion==1 and j.character.health==7,"sword cursor donates one item without using it")
    press(KEY_SPACE);check(j.henge.phase=="prelude","held continue cannot prematurely award blessing")
    for tick in range(50):view.advance()
    check(j.henge.phase=="ritual" and not host.dragon_clip.visible,"ritual begins with map flight hidden")
    var art: Resource=view.scene_art
    check(art.knight.size()==34 and art.druids.size()==3 and art.frames.size()>20,"both full native Hen drawing tracks retained")
    var total: int=0
    for pose in art.knight:
        check(view.pose_at(art.knight,total,false)==pose,"all knight drawing boundaries retained")
        check(view.pose_at(art.knight,total+int(pose.ticks)-1,false)==pose,"all knight drawing holds retained")
        total+=int(pose.ticks)
    check(total==528 and view.pose_at(art.druids,18,true)==art.druids[0],"exact bounded timeline and independent druid loop")
    before=j.checkpoint()
    for tick in range(200):view.advance()
    var saved: Dictionary=j.checkpoint()
    var replica: RefCounted=load("res://scripts/session/journey_session.gd").new(host.definition,host.rules,12)
    check(replica.restore_checkpoint(JSON.parse_string(JSON.stringify(saved))) and replica.checkpoint()==saved,"mid-ritual save restores exact native phase clock")
    for tick in range(52):view.advance()
    var cues: int=audio.played.size()
    press(KEY_SPACE);press(KEY_SPACE);view.sync_audio()
    check(audio.played.size()==cues and cues>=5,"ritual cue tick deduplicates input/explicit refresh")
    click(Vector2(300,200));check(j.henge.phase=="ritual","incidental ritual clicks cannot skip or duplicate")
    press(KEY_ESCAPE)
    check(j.henge.phase=="temple" and j.character.lives==4 and j.character.health==40,"explicit skip completes blessing once")
    press(KEY_SPACE)
    check(j.character.stats.strength==2 and j.character.experience==0 and j.character.lives==4,"temple panel spends XP independently of blessing")
    click(Vector2(160,240))
    check(host.henge_view==null and j.turn_pending and j.day==2 and j.owned_keys==15,"arch column exits temple with one turn spent")
    press(KEY_ENTER);check(not j.turn_pending,"standard next-turn controls retained")
    host.queue_free();await process_frame
    if DisplayServer.get_name()!="headless":check(Input.mouse_mode==mode,"sword cursor ownership restored")
    if failures==0:print("PASS: live map entry, original messages/panels/sword cursor, item/keys boundary, two full tracks/holds, saved ritual, explicit skip, temple XP, column exit and one spent turn")
    quit(1 if failures else 0)
