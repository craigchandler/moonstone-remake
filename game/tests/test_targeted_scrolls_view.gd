extends SceneTree
var failures: int=0
var checks: int=0
func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failures+=1;push_error(label)
func press(key: Key) -> void:
    var e:=InputEventKey.new();e.keycode=key;e.physical_keycode=key;e.pressed=true
    root.push_input(e,true);e=e.duplicate();e.pressed=false;root.push_input(e,true)
func click(point: Vector2) -> void:
    var e:=InputEventMouseButton.new();e.position=point;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=true
    root.push_input(e,true);e=e.duplicate();e.pressed=false;root.push_input(e,true)
func open_item(host: Node,id: String) -> void:
    if host.inventory_view==null:host.show_inventory()
    var view: Node=host.inventory_view
    view.selected=view.rows().find(id);click(view.row_rect(view.selected).get_center())
func _initialize() -> void:run.call_deferred()
func run() -> void:
    var host: Node=load("res://scenes/main.tscn").instantiate();host.saving_enabled=false
    root.add_child(host);host.set_physics_process(false);await process_frame
    var j: RefCounted=host.journey
    j.inventory.items={"scroll_of_acquisition":3,"scroll_of_the_wyrm":2}
    j.rivals.records[1].inventory.items={"ring_of_protection":1,"healing_potion":2}
    j.rivals.records[1].character.health=40
    j.rivals.records[2].inventory.items.scroll_of_haste=1
    open_item(host,"scroll_of_acquisition")
    var panel: Node=host.inventory_view
    check(panel.target_view!=null and panel.target_view.current().id==j.rivals.records[0].id,"actual carried scroll opens first rival in two-column sheet")
    var before: Dictionary=j.checkpoint()
    click(panel.target_view.next_rect.get_center())
    check(panel.target_view.current().id==j.rivals.records[1].id and panel.target_view.rows().has("ring_of_protection"),"next arrow selects actual second rival possessions")
    press(KEY_RIGHT);check(panel.target_view.current().id==j.rivals.records[2].id,"keyboard cycles to third rival")
    press(KEY_ESCAPE)
    check(panel.target_view==null and host.inventory_view==panel and j.checkpoint()==before,"Escape cancels child without closing pack or spending scroll")
    open_item(host,"scroll_of_acquisition");click(Vector2(12,190))
    check(panel.target_view==null and j.checkpoint()==before,"arch column cancels without transfer")
    open_item(host,"scroll_of_acquisition");press(KEY_RIGHT)
    var target: Node=panel.target_view
    click(target.row_rect(target.rows().find("ring_of_protection")).get_center())
    check(panel.target_view==null and j.inventory.items.scroll_of_acquisition==2 and j.inventory.items.ring_of_protection==1 and j.character.health==40,"one sword click acquires ring and consumes once")
    check(not j.rivals.records[1].inventory.items.has("ring_of_protection") and j.rivals.records[1].character.health==20 and host.inventory_view==panel,"transfer updates rival health and leaves parent open")
    # If the same mouse event leaked to the parent, this could use another item.
    check(j.inventory.items.scroll_of_the_wyrm==2 and j.day==1 and j.character.experience==0,"confirm does not trigger parent item or spend a turn")
    open_item(host,"scroll_of_the_wyrm");press(KEY_RIGHT);press(KEY_ENTER)
    check(panel.target_view!=null and j.inventory.items.scroll_of_the_wyrm==2 and j.dragon_order==-1,"early Wyrm rejection leaves picker open and scroll carried")
    press(KEY_ESCAPE);j.day=9
    open_item(host,"scroll_of_the_wyrm");press(KEY_RIGHT);press(KEY_RIGHT)
    check(panel.target_view.caption().contains("III"),"Wyrm caption identifies third knight")
    j.rivals.records[2].inventory.items.ring_of_protection=3
    j.rivals.records[2].character.health=80
    var clear_button: bool=true
    for slot in panel.target_view.slots():
        if slot.rect.intersects(panel.target_view.confirm_rect):clear_button=false
    check(clear_button,"Wyrm Send button stays clear of a full ring row")
    before=j.checkpoint();press(KEY_ESCAPE)
    check(j.checkpoint()==before,"Wyrm cancel before confirmation keeps scroll and target")
    open_item(host,"scroll_of_the_wyrm");press(KEY_RIGHT)
    click(panel.target_view.confirm_rect.get_center())
    check(panel.target_view==null and j.dragon_order==2 and j.inventory.items.scroll_of_the_wyrm==1,"explicit Wyrm button targets selected rival exactly once")
    # Pack modal pauses map/Dragon and remains safe on load/quit.
    before=j.checkpoint()
    for tick in range(30):host._physics_process(0.02)
    check(j.checkpoint()==before,"inventory modal pauses Dragon and map state")
    host.close_inventory()
    # Nested looting screen uses the very same selector.
    j.world.active_lair="grassland_east";j.start_site_combat();host.show_lair();host.arena.set_physics_process(false)
    for a in j.combat.simulation.actors.values():
        if a.team==2:a.health=0;a.down_remaining=0
    j.combat.simulation.spawn_remaining=0;host.show_loot()
    var loot: Node=host.loot_view
    var xp: int=j.character.experience
    loot.use_carried("scroll_of_acquisition")
    check(loot.character_view!=null and loot.character_view.target_view!=null,"looting opens same targeted character sheet")
    target=loot.character_view.target_view
    press(KEY_RIGHT);click(target.row_rect(target.rows().find("healing_potion")).get_center())
    check(j.inventory.items.healing_potion==1 and j.inventory.items.scroll_of_acquisition==1 and j.character.experience==xp and j.looting(),"Acquisition during loot keeps reward, XP and combat settlement")
    press(KEY_ESCAPE)
    check(loot.character_view==null and host.loot_view==loot and j.looting(),"nested exit returns to loot sheet")
    host.queue_free();await process_frame
    if failures==0:print("PASS: ",checks," production sword-cursor/keyboard target, cancel, modal and loot checks")
    quit(1 if failures else 0)
