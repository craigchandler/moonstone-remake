extends RefCounted
# Explicit production-export fixture. Setup locations/items/earned outcome are
# staged; picker, actual campaign entry, save validation, combat and views run.
const Identity=preload("res://scripts/domain/knight_identity.gd")
var kind: int=0
var context: String="map"
var initial: Dictionary={}
var selected: Dictionary={}
var result: Dictionary={}
func setup(host: Node,value: String) -> void:
    var parts: PackedStringArray=value.split("-")
    kind=maxi(0,["blue","yellow","green","red"].find(parts[0]))
    context=parts[1] if parts.size()>1 else "map"
    host.journey.character.experience=7
    initial=host.journey.checkpoint()
    host.show_menu(initial)
func key(host: Node,code: Key) -> void:
    var e:=InputEventKey.new();e.keycode=code;e.physical_keycode=code;e.pressed=true
    host.get_viewport().push_input(e,true);e=e.duplicate();e.pressed=false;host.get_viewport().push_input(e,true)
func advance(host: Node) -> void:
    var t: int=host.elapsed
    if t==10:host.menu_view.activate("new")
    if t==30:
        for i in range(kind):key(host,KEY_RIGHT)
    if t==60:key(host,KEY_ENTER)
    if context=="select":return
    if context=="cancel":
        if t==100:key(host,KEY_ESCAPE);key(host,KEY_ESCAPE)
        return
    if t==100:key(host,KEY_ENTER);selected=host.journey.checkpoint()
    if t==120:
        var j: RefCounted=host.journey
        if context=="sheet":host.show_inventory()
        elif context=="home":
            key(host,KEY_ENTER) # Enter the real selected start, without teleporting.
        elif context=="combat":
            j.world.position=host.definition.lairs[-2].position;host.enter_location(host.definition.lairs[-2].id)
        elif context in ["wizard","gift"]:j.world.position=j.Locations.place("wizard").position;host.enter_location("wizard")
        elif context=="tavern":
            j.world.position=j.town("highwood").position;host.enter_location("highwood");host.open_town_service("tavern")
        elif context=="ritual":
            j.world.position=j.Henge.POSITION;j.inventory.items.healing_potion=1;host.enter_location("stonehenge")
            j.advance_henge();j.offer_henge_item("healing_potion");j.advance_henge()
        elif context=="ending":
            # Stage the earned Guardian result and matching day, then use the
            # actual settlement, Stonehenge gate and confirmation. Do not run
            # a whole rival campaign inside a visual fixture's setup loop.
            host.setup_quest_demo();host.quest_view.activate()
            j.day=17
            host.demo_walk_henge()
            for i in range(20):host.quest_view.advance()
            host.quest_view.activate()
    if host.henge_view!=null:host.henge_view.advance()
    if host.quest_view!=null:host.quest_view.advance()
    if t==140 and context=="gift":host.inventory_view.activate()
    if t==160:result.mid=host.journey.checkpoint()
func finish(host: Node) -> void:
    var j: RefCounted=host.journey
    var valid: bool=true
    if context in ["cancel","select"]:
        valid=j.checkpoint()==initial and host.menu_view!=null
        valid=valid and (host.selection_view!=null if context=="select" else host.selection_view==null)
    else:
        valid=j.identity=={"kind":kind,"name":Identity.DEFAULT_NAMES[kind]} and selected.identity==j.identity
        valid=valid and host.menu_view==null and host.selection_view==null
        var home_start: Vector2i=j.Locations.home(kind).position.clamp(host.definition.bounds.position,host.definition.bounds.end-Vector2i.ONE)
        valid=valid and selected.world.position=={"x":home_start.x,"y":home_start.y}
        if context=="home":valid=valid and j.town_id=="home" and host.inventory_view!=null and j.message==j.HOME_VISIT_MESSAGE
        if context=="ending":valid=valid and j.quest.ending.knight_kind==kind
    if not valid:push_error("Knight selection fixture failed: "+context);host.get_tree().quit(1);return
    result.initial=initial;result.selected=selected;result.final=j.checkpoint()
    if context=="combat":result.battle=j.combat.simulation.snapshot()
    if not j.validate_checkpoint(j.checkpoint()).is_empty():result.valid_save=true
    else:push_error("Selected campaign checkpoint rejected");host.get_tree().quit(1);return
    print("KNIGHT_STATE=",JSON.stringify(result))
    print("PASS: original knight picker, selected identity/home/presentation, guarded cancel and compatible saved campaign")
    host.get_tree().quit()
