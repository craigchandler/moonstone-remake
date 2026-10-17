extends SceneTree
const Places=preload("res://scripts/domain/town_locations.gd")
var checks: int=0
var failures: int=0
func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failures+=1;push_error(label)
func press(code: Key) -> void:
    var e:=InputEventKey.new();e.keycode=code;e.physical_keycode=code;e.pressed=true
    root.push_input(e,true);e=e.duplicate();e.pressed=false;root.push_input(e,true)
func click(point: Vector2) -> void:
    var e:=InputEventMouseButton.new();e.position=point;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=true
    root.push_input(e,true);e=e.duplicate();e.pressed=false;root.push_input(e,true)
func host() -> Node:
    var view: Node=load("res://scenes/main.tscn").instantiate();view.saving_enabled=false
    root.add_child(view);view.set_physics_process(false);return view
func _initialize() -> void:run.call_deferred()
func run() -> void:
    var view: Node=host();await process_frame
    var j: RefCounted=view.journey;j.world.position=j.town("wizard").position
    view.enter_location("wizard")
    check(view.inventory_view!=null and j.places.visit.phase=="greeting","tower icon opens original animated wizard greeting")
    var before: Dictionary=j.checkpoint();press(KEY_E);press(KEY_TAB)
    check(j.checkpoint()==before,"ordinary map shortcuts cannot bypass Math")
    press(KEY_F1);press(KEY_SPACE)
    check(j.places.visit.phase=="greeting","help dismissal does not advance wizard reward")
    press(KEY_SPACE)
    check(j.places.visit.phase=="gift" and not j.places.visit.result.is_empty(),"Space applies one actual wizard outcome")
    var gift: Dictionary=j.checkpoint();view.queue_free();await process_frame
    view=host();await process_frame;j=view.journey
    check(j.restore_checkpoint(gift),"saved animated gift restores")
    view.show_town()
    check(view.inventory_view!=null and j.checkpoint()==gift,"Continue reopens same wizard scene without reroll")
    press(KEY_SPACE);press(KEY_SPACE)
    check(j.places.visit.phase=="sheet" and view.inventory_view.tab==2 and j.inventory==gift.inventory,"wizard omen leads to character sheet once")
    press(KEY_TAB)
    check(view.inventory_view.tab==0 and not j.validate_checkpoint(j.checkpoint()).is_empty(),"Math pack tab keeps a valid save context")
    press(KEY_ESCAPE)
    check(j.town_id=="" and j.rivals.active==1,"leaving wizard sheet spends the human turn")
    view.queue_free();await process_frame
    view=host();await process_frame;j=view.journey
    j.world.position=j.town("highwood").position;j.enter_town("highwood");view.show_town()
    j.inventory.gold=100;j.character.experience=3;j.places.market.items={"ring_of_protection":1}
    click(view.town_view.button_rect(3).get_center())
    var market: Node=view.inventory_view
    check(market!=null and market.tab==2 and not view.town_view.visible,"printed High Temple opens original trade/stat panel")
    click(market.row_rect(0).get_center())
    check(j.character.stats.strength==2 and j.character.experience==0,"left ability icons still spend XP")
    click(market.buy_slots()[0].rect.get_center())
    check(j.inventory.items.ring_of_protection==1 and j.inventory.gold==60 and j.character.health==40,"right stock sword click buys a real ring")
    click(market.own_slots()[0].rect.get_center())
    check(j.inventory.items.is_empty() and j.inventory.gold==80 and j.character.health==20,"left object sword click sells at half price and removes passive")
    click(Vector2(12,190))
    check(view.inventory_view==null and view.town_view.visible and j.day==1,"trade arch column returns to town without spending day")
    click(view.town_view.button_rect(1).get_center())
    var service: Node=view.inventory_view
    click(service.service_screen.row_rect(2).get_center())
    check(j.places.visit.phase=="rolling" and j.places.visit.bet==3,"printed3gold button commits a wager")
    before=j.checkpoint();press(KEY_SPACE);press(KEY_ESCAPE)
    check(j.checkpoint()==before and view.inventory_view==service,"roll cannot be cancelled/rerolled after paying")
    for tick in range(69):service.service_screen.advance(service)
    check(j.places.visit.phase=="dice" and j.inventory==before.inventory,"original69tick throw reveals same stored result")
    press(KEY_SPACE);press(KEY_ESCAPE)
    check(view.inventory_view==null and view.town_view.visible,"result acknowledgement returns through tavern to town")
    # Original donation controls remain previews until accepted.
    j.inventory.gold=50;j.character.health=4;j.character.lives=4
    click(view.town_view.button_rect(2).get_center());press(KEY_SPACE);press(KEY_1)
    before=j.checkpoint();press(KEY_ESCAPE)
    check(j.inventory==before.inventory and j.character.snapshot()==before.character,"cancelled healer offer does not charge or heal")
    click(view.town_view.button_rect(2).get_center());press(KEY_SPACE);press(KEY_2);press(KEY_SPACE)
    check(j.inventory.gold==35 and j.character.health==20 and j.character.lives==4 and j.places.visit.phase=="reply","accepted15gp offer commits full donation and heals wounds only")
    before=j.checkpoint();press(KEY_SPACE)
    check(view.inventory_view==null and j.inventory==before.inventory,"reply returns to town without charging again")
    view.queue_free();await process_frame
    if failures==0:print("PASS: ",checks," production wizard/Continue/modal, temple trade/XP, committed animated dice and donation input checks")
    quit(1 if failures else 0)
