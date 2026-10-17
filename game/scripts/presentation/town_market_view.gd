extends "res://scripts/presentation/original_panel_view.gd"
signal finished
const Places=preload("res://scripts/domain/town_locations.gd")
var journey: RefCounted
var service_screen: RefCounted
var tab: int=2
var selected: int=0
var page: int=0
var pack_page: int=0
var hovered: String=""
func rows() -> Array[String]:return ["strength","constitution","endurance"]
func row_rect(index: int) -> Rect2:return Rect2(82,70+index*14,80,14)
func activate() -> void:
    journey.upgrade_stat(rows()[clampi(selected,0,2)]);queue_redraw()
func buy_slots() -> Array[Dictionary]:
    var stock: Dictionary=journey.places.market
    return pack_slots(stock.items,stock.keys,150,page,stock.stones)
func own_slots() -> Array[Dictionary]:return pack_slots(journey.inventory.items,journey.owned_keys,0,pack_page,journey.quest.stones)
func name_for(id: String) -> String:
    if journey.REGIONAL_KEYS.has(id):return journey.REGIONAL_KEYS[id].name
    if id in MOONSTONES.stone_ids:return MOONSTONES.stone_names[MOONSTONES.stone_ids.find(id)]
    return journey.loot_rules.items[id].name
func caption_at(point: Vector2) -> String:
    if on_column(point,false):return "EXIT"
    for i in range(3):
        if row_rect(i).has_point(point):return "IMPROVE %s - %d XP"%[rows()[i],journey.upgrade_cost()]
    for slot in buy_slots():
        if slot.rect.has_point(point):return "BUY %s - %d GP"%[name_for(slot.id),Places.price(journey,slot.id)]
    for slot in own_slots():
        if slot.rect.has_point(point):return "SELL %s - %d GP"%[name_for(slot.id),Places.price(journey,slot.id)>>1]
    return "HIGH TEMPLE - BUY / SELL"
func _unhandled_key_input(event: InputEvent) -> void:
    if not event is InputEventKey or not event.pressed or event.echo:return
    get_viewport().set_input_as_handled();mouse_active=false
    if event.keycode==KEY_F1:help_visible=not help_visible;queue_redraw();return
    if help_visible:help_visible=false;queue_redraw();return
    if event.keycode in [KEY_ESCAPE,KEY_I,KEY_ENTER,KEY_KP_ENTER]:finished.emit()
    elif event.keycode in [KEY_UP,KEY_DOWN]:selected=posmod(selected+(1 if event.keycode==KEY_DOWN else -1),3)
    elif event.keycode in [KEY_SPACE,KEY_Z]:activate()
    elif event.keycode in [KEY_PAGEUP,KEY_PAGEDOWN]:
        if event.shift_pressed:pack_page=posmod(pack_page+(1 if event.keycode==KEY_PAGEDOWN else -1),pack_pages(journey.inventory.items))
        else:page=posmod(page+(1 if event.keycode==KEY_PAGEDOWN else -1),pack_pages(journey.places.market.items))
    queue_redraw()
func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion:mouse_active=true;pointer=event.position;hovered=caption_at(pointer);queue_redraw();return
    if not event is InputEventMouseButton or not event.pressed or event.button_index!=MOUSE_BUTTON_LEFT:return
    get_viewport().set_input_as_handled();mouse_active=true;pointer=event.position
    if help_visible:help_visible=false;queue_redraw();return
    if on_column(pointer,false):finished.emit();return
    for i in range(3):
        if row_rect(i).has_point(pointer):selected=i;activate();return
    for slot in buy_slots():
        if slot.rect.has_point(pointer):Places.trade(journey,slot.id,true);queue_redraw();return
    for slot in own_slots():
        if slot.rect.has_point(pointer):Places.trade(journey,slot.id,false);queue_redraw();return
func _draw() -> void:
    if journey==null:return
    draw_classic_background(false);draw_sheet(journey,0);draw_slots(own_slots())
    pixel_text("HIGH TEMPLE",Vector2(470,48),true)
    draw_slots(buy_slots())
    draw_caption(hovered if mouse_active and not hovered.is_empty() else "HIGH TEMPLE - BUY / SELL")
    if not journey.message.is_empty():pixel_text(journey.message.left(52),Vector2(320,30),true,Color("ddc68c"))
    draw_help("CLICK LEFT OBJECT: SELL FOR HALF PRICE\nCLICK RIGHT OBJECT: BUY FROM STOCK\nCLICK LEFT ABILITIES: SPEND XP\nPGUP / PGDN: STOCK PAGES\nSHIFT + PGUP / PGDN: YOUR PACK PAGES\nESC / I / ARCH COLUMN: RETURN TO TOWN\nSTOCK AND TRADED QUEST OBJECTS ARE SAVED")
    draw_pointer(row_rect(selected).get_center())
