extends SceneTree

const Journey=preload("res://scripts/session/journey_session.gd")
const Identity=preload("res://scripts/domain/knight_identity.gd")
const Definition=preload("res://content/first_journey.tres")
const Rules=preload("res://content/foundation_rules.tres")
const Starts: Array[Vector2i]=[Vector2i(18,11),Vector2i(286,11),Vector2i(12,187),Vector2i(303,192)]
var failures: int=0
var checks: int=0

func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failures+=1;push_error(label)

func key(code: Key) -> void:
    var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=true
    root.push_input(event,true);event=event.duplicate();event.pressed=false;root.push_input(event,true)

func mouse(point: Vector2) -> void:
    var event:=InputEventMouseButton.new();event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true
    root.push_input(event,true);event=event.duplicate();event.pressed=false;root.push_input(event,true)

func button(code: int,pressed: bool=true) -> void:
    var event:=InputEventJoypadButton.new();event.device=42;event.button_index=code;event.pressed=pressed
    Input.parse_input_event(event);Input.flush_buffered_events()

func _initialize() -> void:run.call_deferred()

func run() -> void:
    var seeded: Dictionary={}
    for kind in range(4):
        var j: RefCounted=Journey.new(Definition,Rules,991)
        j.restart(991,false,{"kind":kind,"name":Identity.DEFAULT_NAMES[kind]})
        check(j.world.position==Starts[kind],"Selected knight starts at its own reachable village: "+str(kind))
        check(j.arrivals().any(func(row: Dictionary) -> bool:return row.id=="home"),"Own village is immediately enterable: "+str(kind))
        check(j.arrivals().size()==1 and j.combat==null and j.day==1 and j.travel_spent==0,"Starting village does not overlap a forced fight or spend a turn")
        var state: Dictionary=j.checkpoint()
        var normalized: Dictionary=state.duplicate(true)
        normalized.identity=Identity.initial();normalized.world.position={"x":0,"y":0}
        if seeded.is_empty():seeded=normalized
        check(normalized==seeded,"Changing home cannot change seeded loot, rivals, quest, kit or clocks")
        var copy: RefCounted=Journey.new(Definition,Rules,2)
        check(copy.restore_checkpoint(JSON.parse_string(JSON.stringify(state))) and copy.checkpoint()==state,"New village start survives exact Continue")
        var legacy: Dictionary=state.duplicate(true);legacy.world.position={"x":15,"y":100}
        check(copy.restore_checkpoint(legacy) and copy.checkpoint()==legacy,"Existing campaigns retain their saved location and stats")
    var controls: Node=root.get_node("MoonstoneInput")
    controls.allow_write=false
    for kind in range(4):
        for method in ["enter","z","mouse","controller"]:
            var host: Node=load("res://scenes/main.tscn").instantiate()
            # Entry/exit input is real; omit AI scheduling only to measure a
            # single completed recovery round independently of incoming fights.
            host.definition=Definition.duplicate();host.definition.rival_turns=false
            host.saving_enabled=false;host.parse_launch_arguments=false
            root.add_child(host);host.set_physics_process(false)
            await process_frame
            host.show_menu({});host.show_selection()
            host.start_selected({"kind":kind,"name":Identity.DEFAULT_NAMES[kind]})
            var j: RefCounted=host.journey
            check(j.world.position==Starts[kind] and host.selection_view==null and host.menu_view==null,"Picker confirms one new home start")
            # Deliberately stage the reachable home independently of the spawn
            # assertion so a failure there does not hide entry/message failures.
            j.world.position=Starts[kind];j.character.health=5;j.character.lives=2
            var home: Dictionary=j.town("home")
            var texture: Texture2D=host.art.map_icons[str(home.sprite)]
            var drawn: Rect2=host.icon_rect(home.position,texture)
            var scale: Vector2=host.map_rect.size/Vector2(320,200)
            check(drawn==Rect2(host.map_point(home.position),Vector2(home.size)*scale),"Drawn village and entry box share the same logical bounds")
            host.elapsed=0
            check(host.outline_visible("home"),"Own village flashes when the knight overlaps it")
            host.elapsed=20
            check(not host.outline_visible("home"),"Classic village outline retains its off phase")
            host.elapsed=0
            j.world.position=Vector2i(150,80)
            check(not host.outline_visible("home"),"Home cue does not suggest distant entry")
            j.world.position=Starts[kind]
            var treasure: Dictionary=j.lair_loot.duplicate(true)
            var quest: Dictionary=j.quest.duplicate(true)
            controls.clear_input();controls.refresh_context()
            if method=="enter":key(KEY_ENTER)
            elif method=="z":key(KEY_Z)
            elif method=="mouse":mouse(host.map_point(j.world.position)+Vector2(4,4))
            else:button(JOY_BUTTON_A);button(JOY_BUTTON_A,false)
            check(j.town_id=="home" and host.inventory_view!=null,"Own village opens through "+method+" for knight "+str(kind))
            check(j.character.lives==3 and j.character.health==5 and j.day==1,"Entry grants only the capped home blessing; health waits for a completed round")
            check(not j.message.is_empty() and "rest" in j.message.to_lower(),"Home/rest notice survives opening the stats sheet")
            var inside: Dictionary=j.checkpoint()
            var copy: RefCounted=Journey.new(host.definition,Rules,3)
            check(copy.restore_checkpoint(JSON.parse_string(JSON.stringify(inside))) and copy.checkpoint()==inside and copy.character.lives==3,"Continue inside any home cannot repeat the life grant")
            key(KEY_ESCAPE)
            check(host.inventory_view==null and j.town_id=="" and j.day==2 and j.turn_pending and j.character.health==8,"Leaving home ends one turn and applies ordinary recovery once")
            var after: Dictionary=j.checkpoint()
            host.close_inventory()
            check(j.checkpoint()==after and not j.leave_town(),"Repeated close cannot advance or heal twice")
            check(j.lair_loot==treasure and j.quest==quest,"Home rest does not consume reward or quest RNG")
            host.show_menu(inside);host.menu_choice("continue")
            check(host.inventory_view!=null and j.town_id=="home" and j.message==j.HOME_VISIT_MESSAGE,"Continue rebuilds the home/rest cue on the actual character screen")
            check(j.checkpoint()==inside and j.character.lives==3,"Reopening a saved home cannot relocate, heal or grant another life")
            host.queue_free();await process_frame
    if failures==0:print("PASS: ",checks," home-village checks: four starts, keyboard/mouse/controller entry, visible rest notice, one-turn recovery, seeded state and legacy/new Continue")
    quit(0 if failures==0 else 1)
