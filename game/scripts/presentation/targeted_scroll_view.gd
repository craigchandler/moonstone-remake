extends "res://scripts/presentation/original_panel_view.gd"

signal finished(used: bool)
const Scrolls=preload("res://scripts/domain/targeted_scrolls.gd")
const BLACK_LIFE=preload("res://assets/classic/targeted_scrolls/black_life.png")
class Sheet extends RefCounted:
    var character: RefCounted
    var inventory: Dictionary
var journey: RefCounted
var item: String="scroll_of_acquisition"
var rival_index: int=0
var selected: int=0
var page: int=0
var hovered: String=""
var previous_rect:=Rect2(356,22,64,20)
var next_rect:=Rect2(556,22,68,20)
var confirm_rect:=Rect2(438,20,100,24)

func current() -> Dictionary:
    var list: Array[Dictionary]=Scrolls.targets(journey)
    return {} if list.is_empty() else list[posmod(rival_index,list.size())]

func rows() -> Array[String]:
    var row: Dictionary=current()
    var empty: Array[String]=[]
    return empty if row.is_empty() or item!="scroll_of_acquisition" else Scrolls.objects(journey,row)

func slots() -> Array[Dictionary]:
    var row: Dictionary=current()
    var empty: Array[Dictionary]=[]
    return empty if row.is_empty() else pack_slots(row.inventory.items,row.keys,150,page,row.stones)

func row_rect(index: int) -> Rect2:
    var list: Array[String]=rows()
    if index<0 or index>=list.size():return Rect2()
    for slot in slots():
        if slot.id==list[index]:return slot.rect
    return Rect2()

func cycle(direction: int) -> void:
    rival_index+=direction;selected=0;page=0;hovered="";journey.message="";queue_redraw()

func activate() -> void:
    var row: Dictionary=current()
    if row.is_empty():return
    var target: Variant=row.id
    if item=="scroll_of_acquisition":
        var list: Array[String]=rows()
        if list.is_empty():return
        selected=clampi(selected,0,list.size()-1)
        target={"rival":row.id,"item":list[selected]}
    if journey.use_item(item,target):finished.emit(true)
    queue_redraw()

func name_of(id: String) -> String:
    if journey.REGIONAL_KEYS.has(id):return journey.REGIONAL_KEYS[id].name
    if id in MOONSTONES.stone_ids:return MOONSTONES.stone_names[MOONSTONES.stone_ids.find(id)]
    return journey.loot_rules.items[id].name

func caption() -> String:
    var row: Dictionary=current()
    if row.is_empty():return "NO LIVING RIVAL KNIGHTS"
    if item=="scroll_of_the_wyrm":return "SEND THE WYRM AFTER "+String(journey.world.lair(row.id).name)
    var list: Array[String]=rows()
    return "NO OBJECTS TO TAKE" if list.is_empty() else "ACQUIRE "+name_of(list[clampi(selected,0,list.size()-1)])

func hover_at(point: Vector2) -> String:
    if on_column(point,false):return "CANCEL - SCROLL KEPT"
    if previous_rect.has_point(point):return "PREVIOUS KNIGHT"
    if next_rect.has_point(point):return "NEXT KNIGHT"
    if item=="scroll_of_the_wyrm" and confirm_rect.has_point(point):return caption()
    if item=="scroll_of_acquisition":
        for slot in slots():
            if slot.rect.has_point(point):return "ACQUIRE "+name_of(slot.id)
    return ""

func _unhandled_key_input(event: InputEvent) -> void:
    if not event is InputEventKey or not event.pressed or event.echo:return
    get_viewport().set_input_as_handled();mouse_active=false
    if help_visible and event.keycode!=KEY_F1:help_visible=false;queue_redraw();return
    if event.keycode in [KEY_ESCAPE,KEY_I]:finished.emit(false)
    elif event.keycode==KEY_F1:help_visible=not help_visible
    elif event.keycode in [KEY_LEFT,KEY_RIGHT,KEY_TAB]:cycle(-1 if event.keycode==KEY_LEFT else 1)
    elif event.keycode in [KEY_SPACE,KEY_ENTER,KEY_KP_ENTER,KEY_Z]:activate()
    elif event.keycode in [KEY_UP,KEY_DOWN]:
        selected=posmod(selected+(1 if event.keycode==KEY_DOWN else -1),maxi(1,rows().size()))
        if row_rect(selected).size==Vector2.ZERO:
            for candidate in range(pack_pages(current().inventory.items)):
                page=candidate
                if row_rect(selected).size!=Vector2.ZERO:break
    elif event.keycode in [KEY_PAGEUP,KEY_PAGEDOWN] and not current().is_empty():page=posmod(page+(1 if event.keycode==KEY_PAGEDOWN else -1),pack_pages(current().inventory.items))
    queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion:
        get_viewport().set_input_as_handled();mouse_active=true;pointer=event.position;hovered=hover_at(pointer);queue_redraw();return
    if not event is InputEventMouseButton or not event.pressed or event.button_index!=MOUSE_BUTTON_LEFT:return
    get_viewport().set_input_as_handled();mouse_active=true;pointer=event.position
    if help_visible:help_visible=false;queue_redraw();return
    if on_column(pointer,false):finished.emit(false);return
    if previous_rect.has_point(pointer):cycle(-1)
    elif next_rect.has_point(pointer):cycle(1)
    elif item=="scroll_of_the_wyrm" and confirm_rect.has_point(pointer):activate()
    elif item=="scroll_of_acquisition":
        for slot in slots():
            if slot.rect.has_point(pointer):selected=rows().find(slot.id);activate();break
    hovered=hover_at(pointer);queue_redraw()

func _draw() -> void:
    if journey==null:return
    draw_classic_background(false)
    draw_sheet(journey,0);draw_slots(pack_slots(journey.inventory.items,journey.owned_keys,0,0,journey.quest.stones))
    var row: Dictionary=current()
    if not row.is_empty():
        var sheet:=Sheet.new();sheet.character=journey.rivals.knight(row);sheet.inventory=row.inventory
        draw_sheet(sheet,150,String(journey.world.lair(row.id).name).to_upper(),BLACK_LIFE)
        draw_slots(slots())
        pixel_text("PREV",previous_rect.position);pixel_text("NEXT",next_rect.position)
        if item=="scroll_of_the_wyrm":pixel_text("SEND",confirm_rect.position+Vector2(30,4))
    var title: String=hovered if mouse_active and not hovered.is_empty() else caption()
    if not row.is_empty() and pack_pages(row.inventory.items)>1:title+="  %d/%d" % [page+1,pack_pages(row.inventory.items)]
    draw_caption(title)
    if not journey.message.is_empty():
        # Feedback stays above the arch artwork and outside object hit regions.
        var text: String=journey.message
        if text.length()>54:text=text.left(54)
        draw_rect(Rect2(42,382,556,16),Color.BLACK);pixel_text(text,Vector2(320,384),true,Color("ddc68c"))
    draw_help("LEFT / RIGHT / TAB: CHOOSE KNIGHT\nCLICK AN OBJECT TO ACQUIRE IT\nWYRM: CLICK SEND OR PRESS ENTER\nESC / I / ARCH COLUMN: CANCEL\nCANCEL KEEPS YOUR SCROLL\nPGUP / PGDN: RIVAL PACK PAGES")
    var fallback: Vector2=confirm_rect.get_center() if item=="scroll_of_the_wyrm" or rows().is_empty() else row_rect(clampi(selected,0,rows().size()-1)).get_center()
    draw_pointer(fallback)
