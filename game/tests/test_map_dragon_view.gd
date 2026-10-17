extends SceneTree

var failures: int = 0

func check(ok: bool, label: String) -> void:
    if not ok:
        failures+=1
        push_error(label)

func press(key: Key) -> void:
    var event := InputEventKey.new()
    event.keycode=key;event.physical_keycode=key;event.pressed=true
    Input.parse_input_event(event);Input.flush_buffered_events()
    event=event.duplicate();event.pressed=false
    Input.parse_input_event(event);Input.flush_buffered_events()

func _initialize() -> void:
    run.call_deferred()

func run() -> void:
    var view: Node=load("res://scenes/main.tscn").instantiate()
    view.saving_enabled=false
    view.definition=view.definition.duplicate();view.definition.rival_turns=false;root.add_child(view);view.set_physics_process(false)
    await process_frame
    view.update_dragon_sprite()
    check(not view.dragon_clip.visible,"New journey has no flying dragon")
    for i in range(8):
        press(KEY_E)
        press(KEY_ENTER)
    view.travel(Vector2i.ZERO);view.update_dragon_sprite()
    check(view.journey.day==9 and view.dragon_clip.visible,"Rest input reaches the original lunar trigger")
    check(view.dragon_clip.clip_contents and view.dragon_clip.position==view.map_rect.position and view.dragon_clip.size==view.map_rect.size,"Dragon is clipped to map, including edges and sidebar")
    check(view.dragon_sprite.texture==view.art.dragon_frames[0] and view.dragon_sprite.flip_h,"Edge entry uses original frame and rightward facing")
    var f: RefCounted=view.journey.world.dragon
    f.timer=60;f.position=Vector2i(351,40)
    view.update_dragon_sprite()
    check(view.dragon_sprite.texture==view.art.dragon_frames[3] and view.dragon_sprite.position.x>view.map_rect.size.x,"Glide uses original held wings, without moving sprite back inside map")
    f.facing=1;f.speed_x=-2
    view.update_dragon_sprite()
    check(not view.dragon_sprite.flip_h,"Return pass mirrors the dragon and its anchor")
    var paused: Dictionary=f.snapshot()
    press(KEY_I);view.update_dragon_sprite()
    check(view.inventory_view!=null and not view.dragon_clip.visible,"Flying art cannot cover character screen")
    view.travel(Vector2i.RIGHT)
    check(f.snapshot()==paused,"Opening inventory preserves and pauses the current flight")
    press(KEY_ESCAPE);view.update_dragon_sprite()
    check(view.inventory_view==null and view.dragon_clip.visible and f.snapshot()==paused,"Closing inventory resumes same pass")
    view.journey.world.position=Vector2i(190,100);f.position=Vector2i(200,100)
    view.travel(Vector2i.ZERO);view.update_dragon_sprite()
    check(view.arena!=null and view.arena.managed_by_world and view.arena.encounter==&"dragon_fight" and not view.dragon_clip.visible,"Actual map contact routes Dragon fight and hides flight sprite")
    view.arena.set_physics_process(false)
    press(KEY_ESCAPE);view.update_dragon_sprite()
    check(view.arena==null and not f.active,"Retreat ends the previous pass")
    view.travel(Vector2i.ZERO);view.update_dragon_sprite()
    check(f.active and f.position==Vector2i(10,100) and view.dragon_clip.visible,"Returning to map starts at edge, with no trapped immediate rematch")
    view.queue_free();await process_frame
    if failures==0:print("PASS: map Dragon input trigger, actual sprites/glide/mirroring, map clipping, inventory pause/resume and contact/retreat arena routing")
    quit(1 if failures else 0)
