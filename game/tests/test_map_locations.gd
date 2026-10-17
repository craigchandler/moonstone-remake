extends SceneTree

const Locations=preload("res://scripts/domain/map_locations.gd")
const Journey=preload("res://scripts/session/journey_session.gd")
var definition: Resource=preload("res://content/first_journey.tres").duplicate()
var rules: Resource=preload("res://content/foundation_rules.tres")
var failures: int=0
func check(ok: bool,label: String) -> void:
    if not ok:failures+=1;push_error(label)
func press(key: Key) -> void:
    var event:=InputEventKey.new();event.keycode=key;event.physical_keycode=key;event.pressed=true
    Input.parse_input_event(event);Input.flush_buffered_events();event=event.duplicate();event.pressed=false;Input.parse_input_event(event);Input.flush_buffered_events()
func click(point: Vector2) -> void:
    var event:=InputEventMouseButton.new();event.position=point;event.pressed=true;event.button_index=MOUSE_BUTTON_LEFT
    root.push_input(event,true);event=event.duplicate();event.pressed=false;root.push_input(event,true)
func _init() -> void:
    definition.rival_turns=false # Isolated historical component fixture.

func _initialize() -> void:run.call_deferred()
func run() -> void:
    check(definition.confirm_entry,"production requires fire")
    var host: Node=load("res://scenes/main.tscn").instantiate();host.saving_enabled=false
    host.definition=definition
    root.add_child(host);host.set_physics_process(false);await process_frame
    var j: RefCounted=host.journey
    var chests: Dictionary=j.lair_loot.duplicate(true)
    check(host.art.map_icons.size()==21 and host.rival_markers().size()==3,"source icons and four knight records visible")
    for id in ["highwood","waterdeep","stonehenge","home","wizard"]:
        var place: Dictionary=Locations.place(id)
        j.world.position=place.position+place.size-Vector2i(1,1)
        for tick in range(8):host.travel(Vector2i.ZERO)
        check(j.town_id=="" and j.henge.is_empty() and host.arena==null,"overlap alone never enters: "+id)
        check(j.arrivals().any(func(row: Dictionary) -> bool:return row.id==id),"whole original picture overlaps: "+id)
        var before: Dictionary=j.checkpoint()
        host.elapsed=0;check(host.outline_visible(id),"outline on: "+id)
        host.elapsed=20;check(not host.outline_visible(id),"outline off: "+id)
        check(j.checkpoint()==before,"render phase never changes campaign")
    # Town far corner is outside the old five-pixel dot; fire enters the picture.
    j.world.position=Vector2i(100,52);press(KEY_ENTER)
    check(host.town_view!=null and j.town_id=="highwood","fire enters full Highwood picture")
    host.leave_town();check(j.day==2 and j.turn_pending,"town exit spends once")
    press(KEY_ENTER)
    j.world.position=Vector2i(300,165);click(Vector2(200,200))
    check(host.town_view!=null and j.town_id=="waterdeep","mouse fire enters Waterdeep")
    host.leave_town();j.begin_turn()
    j.world.position=Vector2i(100,161);press(KEY_Z)
    check(host.henge_view!=null and j.henge.phase=="greeting","fire enters full Stonehenge icon")
    press(KEY_SPACE);press(KEY_ESCAPE);press(KEY_ESCAPE);press(KEY_ENTER)
    # Own home only. Grant once, save inside it, no repeat on Continue.
    j.world.position=Vector2i(34,16);j.character.lives=1;j.character.experience=3
    host.enter_location("home")
    check(host.inventory_view!=null and j.town_id=="home" and j.character.lives==2,"home grants life up to3 and opens original character sheet")
    var saved: Dictionary=j.checkpoint();var resumed: RefCounted=Journey.new(definition,rules,2)
    check(resumed.restore_checkpoint(JSON.parse_string(JSON.stringify(saved))) and resumed.checkpoint()==saved and resumed.character.lives==2,"home Continue cannot repeat life grant")
    check(j.upgrade_stat("strength") and j.character.experience==0,"home temple spends earned XP")
    var day: int=j.day;host.close_inventory()
    check(j.turn_pending and j.day==day+1 and j.town_id=="","home exit spends one turn")
    host.close_inventory();check(j.day==day+1,"repeat close cannot spend again");j.begin_turn()
    j.world.position=Vector2i(219,19);press(KEY_ENTER)
    check(host.inventory_view!=null and j.town_id=="wizard","tower is enterable with labelled character preview")
    check(resumed.restore_checkpoint(j.checkpoint()) and resumed.town_id=="wizard","tower state Continue")
    day=j.day;host.close_inventory();check(j.day==day+1 and j.turn_pending,"tower exit spends once");j.begin_turn()
    for id in ["village_yellow","village_green","village_red"]:
        j.world.position=Locations.place(id).position
        check(not j.arrivals().any(func(row: Dictionary) -> bool:return row.id==id) and not j.confirm_location(id),"other homes unavailable to blue knight")
    # Source-sized lair overlap and fire; cleared treasure returns without a fight.
    var site: Dictionary=definition.lairs[0];j.world.position=site.position
    host.elapsed=0;check(host.outline_visible(site.id),"lair outline flashes too")
    for tick in range(8):host.travel(Vector2i.ZERO)
    check(host.arena==null,"lair requires confirmation")
    press(KEY_ENTER);check(host.arena!=null and j.world.active_lair==site.id,"fire enters correct lair")
    host.return_to_map(false)
    check(host.arena==null,"retreat returns to map")
    # Multiple overlapping original boxes need a choice, not an arbitrary entry.
    j.world.position=Vector2i(24,20);press(KEY_ENTER)
    check(host.arrival_choices.size()==2 and host.inventory_view==null and host.arena==null,"overlapping home/lair opens choice")
    var before: Dictionary=j.checkpoint();host.travel(Vector2i.RIGHT)
    check(j.checkpoint()==before,"arrival choice freezes travel")
    press(KEY_ESCAPE);check(host.arrival_choices.is_empty() and j.checkpoint()==before,"choice cancel has no effect")
    press(KEY_ENTER);press(KEY_1)
    check(j.town_id=="home" and host.inventory_view!=null,"number selects first source-order arrival")
    host.close_inventory();j.begin_turn()
    check(j.lair_loot==chests,"visits never reroll chests")
    # Inclusive edge geometry uses sprite extents, never a radius around a dot.
    check(Locations.touches(Vector2i(74,18),Vector2i(82,28),Vector2i(25,32)),"coincident knight/node edges touch")
    check(not Locations.touches(Vector2i(73,18),Vector2i(82,28),Vector2i(25,32)),"one pixel outside edge misses")
    var forced: RefCounted=Journey.new(definition,rules,12)
    forced.world.position=site.position;forced.travel_spent=forced.travel_allowance()-1
    for tick in range(8):
        forced.travel(Vector2i.RIGHT)
        if forced.combat!=null:break
    check(forced.combat!=null and forced.world.active_lair==site.id and not forced.turn_pending,"exhaustion on a lair retains original forced arrival before turn end")
    var invalid: Dictionary=resumed.checkpoint();invalid.world.position={"x":190,"y":100}
    var retained: Dictionary=resumed.checkpoint()
    check(not resumed.restore_checkpoint(invalid) and resumed.checkpoint()==retained,"distant visit save rejects atomically")
    host.queue_free();await process_frame
    if failures==0:print("PASS: source-sized map overlap/fire/multiple choice, flashing lairs/places, own home life/XP/turn/Continue, tower preview, four markers and immutable treasure")
    quit(1 if failures else 0)
