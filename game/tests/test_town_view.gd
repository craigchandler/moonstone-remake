extends SceneTree

var failures: int=0
func check(condition: bool,label: String) -> void:
    if not condition: failures+=1; push_error(label)
func press(key: Key) -> void:
    var event:=InputEventKey.new()
    event.keycode=key; event.physical_keycode=key; event.pressed=true
    Input.parse_input_event(event); Input.flush_buffered_events()
    event=event.duplicate(); event.pressed=false
    Input.parse_input_event(event); Input.flush_buffered_events()
func click(point: Vector2) -> void:
    var event:=InputEventMouseButton.new()
    event.position=point; event.button_index=MOUSE_BUTTON_LEFT; event.pressed=true
    root.push_input(event,true)
    event=event.duplicate(); event.pressed=false
    root.push_input(event,true)
func motion(point: Vector2) -> void:
    var event:=InputEventMouseMotion.new()
    event.position=point
    root.push_input(event,true)
func _initialize() -> void:
    run.call_deferred()
func run() -> void:
    var mouse_mode: int=Input.mouse_mode
    var view: Node=load("res://scenes/main.tscn").instantiate()
    view.saving_enabled=false
    view.definition=view.definition.duplicate();view.definition.rival_turns=false
    root.add_child(view)
    view.set_physics_process(false)
    await process_frame
    for town_id in ["highwood","waterdeep"]:
        view.journey.world.position=view.journey.town(town_id).position
        view.journey.enter_town(town_id)
        view.show_town()
        var town: Node=view.town_view
        check(town.rows()==["smith","tavern","healer",("temple" if town_id=="highwood" else "mystic"),"leave"],"original five-entry order and town-specific fourth entry")
        var menu_x: int=576 if town_id=="highwood" else 64
        check(town.button_rect(0).position.x==(512 if town_id=="highwood" else 0) and town.button_rect(4).end.y<=400,"click areas align with the correct parchment side and screen bounds")
        if DisplayServer.get_name()!="headless": check(Input.mouse_mode==Input.MOUSE_MODE_HIDDEN,"town owns sword cursor")
        var before: Dictionary=view.journey.checkpoint()
        click(Vector2(300,180))
        check(view.inventory_view==null and view.journey.checkpoint()==before,"town illustration is not an invisible service or exit button")
        click(Vector2(menu_x,144))
        check(view.inventory_view!=null and view.inventory_view.tab==4 and not town.visible and view.journey.inventory==before.inventory and view.journey.day==before.day,"original Tavern entry opens its interior without a transaction")
        click(Vector2(576,208))
        check(view.inventory_view.service_screen.phase=="rolling" and view.inventory_view.service_screen.bet==3,"third printed Tavern bet starts committed dice throw")
        var paid: Dictionary=view.journey.checkpoint()
        for tick in range(69):view.inventory_view.service_screen.advance(view.inventory_view)
        check(view.inventory_view.service_screen.phase=="dice" and view.journey.inventory==paid.inventory,"dice reveal cannot debit or pay twice")
        press(KEY_SPACE)
        check(view.inventory_view.service_screen.phase=="tavern","acknowledging result returns to Tavern")
        press(KEY_ESCAPE)
        check(view.town_view==town and town.visible and view.journey.day==before.day,"Escape returns from Tavern without spending a day")
        view.journey.inventory.gold=100
        click(Vector2(menu_x,76))
        check(view.inventory_view!=null and view.inventory_view.tab==1 and not town.visible,"printed Merchant opens working smith")
        var entry_day: int=view.journey.day
        click(view.inventory_view.row_rect(0).get_center())
        check(view.journey.character.weapon=="broad_sword" and view.journey.inventory.gold==90,"Merchant purchase still pays actual price")
        press(KEY_ENTER)
        check(town.visible and view.journey.day==entry_day,"returning from service restores complete town without ending the visit")
        if DisplayServer.get_name()!="headless": check(Input.mouse_mode==Input.MOUSE_MODE_HIDDEN,"closing a nested service retains town sword cursor")
        motion(Vector2(menu_x,222))
        check(town.selected==2,"hover printed Healer selects the actual third menu entry")
        view.journey.character.health=4
        press(KEY_ENTER)
        check(view.inventory_view.tab==3,"hover then keyboard activation opens Healer")
        press(KEY_SPACE) # Acknowledge original greeting.
        press(KEY_1)
        click(view.inventory_view.row_rect(2).get_center())
        check(view.journey.character.health==view.journey.character.maximum(view.journey.inventory.items) and view.journey.inventory.gold==80,"Healer retains health and gold rules")
        view.journey.character.lives=4
        press(KEY_SPACE) # Finished reply returns to town.
        click(Vector2(menu_x,222));press(KEY_SPACE)
        press(KEY_2)
        for step in range(10):press(KEY_RIGHT)
        press(KEY_SPACE)
        check(view.journey.character.lives==5 and view.journey.inventory.gold==55,"accepted25gold donation spends the whole offer and restores life")
        press(KEY_SPACE)
        click(Vector2(menu_x,222));press(KEY_SPACE);press(KEY_1)
        check(view.journey.inventory.gold==55 and view.inventory_view.service_screen.donation==10,"staged donation leaves purse unchanged")
        press(KEY_ESCAPE)
        check(view.journey.inventory.gold==55,"unconfirmed offer keeps the full purse")
        if town_id=="highwood":
            view.journey.character.experience=3
            click(Vector2(menu_x,300))
            check(view.inventory_view!=null and view.inventory_view.tab==2,"printed High Temple opens upgrades")
            click(view.inventory_view.row_rect(0).get_center())
            check(view.journey.character.stats.strength==2 and view.journey.character.experience==0,"temple spends XP once")
            press(KEY_ESCAPE)
        else:
            before=view.journey.checkpoint()
            click(Vector2(menu_x,300))
            check(view.inventory_view!=null and view.inventory_view.tab==5 and view.journey.inventory==before.inventory,"Mythral greeting does not charge")
            press(KEY_SPACE)
            press(KEY_2)
            press(KEY_SPACE)
            check(view.journey.inventory.gold==before.inventory.gold-15 and view.inventory_view.service_screen.phase=="reply","Mythral donation commits one paid reading")
            press(KEY_ESCAPE)
            check(view.town_view==town and town.visible,"Mythral Exit restores town")
        press(KEY_I)
        check(view.inventory_view!=null and view.inventory_view.tab==0,"I retains personal inventory without adding a sixth parchment entry")
        press(KEY_I)
        press(KEY_F1)
        check(town.help_visible,"F1 exposes optional controls and character summary")
        click(Vector2(menu_x,380))
        check(view.town_view==town and not town.help_visible,"help click cannot activate underlying town Exit")
        var day: int=view.journey.day
        click(Vector2(menu_x,380))
        check(view.town_view==null and view.journey.town_id.is_empty() and view.journey.day==day+1,"printed Exit leaves either town and spends exactly one day")
        view.set_physics_process(false)
        check(Input.mouse_mode==mouse_mode,"town exit restores the previous system cursor")
        view.journey.restart(12)
    view.queue_free()
    await process_frame
    if failures==0: print("PASS: full original town/menu alignment, both sides, real Merchant/Healer/Temple clicks, hover/keyboard, inventory/return cursor ownership, Healer full donation/cancel, Tavern committed dice, Mythral reading, guarded overlays and exact single-day Exit")
    quit(1 if failures else 0)
