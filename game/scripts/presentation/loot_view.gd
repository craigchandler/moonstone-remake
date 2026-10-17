extends "res://scripts/presentation/original_panel_view.gd"

signal finished

const InventoryView=preload("res://scripts/presentation/inventory_view.gd")
const STATS=["strength","constitution","endurance"]
var journey: RefCounted
var character_view: Node2D
var feedback: String=""
var feedback_ticks: int=0
var health: int = 0
var maximum: int = 10
var daggers: int = 0
var selected: int = 0
var page: int = 0
var pack_page: int = 0
var hovered: String = ""
var continue_rect := Rect2(296,166,50,234)
var page_rect := Rect2(384,46,196,16)
var pack_page_rect := Rect2(76,46,206,16)

func _process(_delta: float) -> void:
    if feedback_ticks>0:
        feedback_ticks-=1
        if feedback_ticks==0: feedback=""; queue_redraw()

func stat_rect(index: int) -> Rect2:
    return Rect2(82,70+index*14,80,14)

func show_feedback() -> void:
    feedback=journey.message
    feedback_ticks=180
    queue_redraw()

func open_character(tab: int=0, item: String="") -> void:
    if character_view!=null or not journey.looting(): return
    character_view=InventoryView.new()
    character_view.journey=journey
    character_view.loot_context=true
    add_child(character_view)
    character_view.set_tab(tab)
    character_view.finished.connect(close_character)
    if not item.is_empty():
        character_view.selected=character_view.rows().find(item)
        character_view.activate()

func close_character() -> void:
    remove_child(character_view)
    character_view.queue_free()
    character_view=null
    # A successful Hawk scroll already settled and left the lair.
    if not journey.loot_open: finished.emit(); return
    pack_page=mini(pack_page,pack_pages(journey.inventory.items)-1)
    hovered=hover_at(pointer)
    queue_redraw()

func use_carried(id: String) -> void:
    if journey.REGIONAL_KEYS.has(id):
        journey.message="Keep all four regional keys to enter the Valley of the Gods."
    elif id in MOONSTONES.stone_ids:
        journey.message="Offer moonstones at Stonehenge during the matching moon phase."
    elif journey.character_rules.items[id].effect in ["reveal","teleport","rival","dragon_target"]:
        open_character(0,id)
        return
    else: journey.use_item(id)
    pack_page=mini(pack_page,pack_pages(journey.inventory.items)-1)
    show_feedback()

func rows() -> Array[String]:
    var result: Array[String] = []
    var pile: Dictionary = journey.available_loot()
    if int(pile.get("gold",0))>0: result.append("gold")
    for id in journey.loot_rules.items:
        if int(pile.get("items",{}).get(id,0))>0: result.append(id)
    for id in journey.REGIONAL_KEYS:
        if int(pile.get("keys",0)) & int(journey.REGIONAL_KEYS[id].bit): result.append(id)
    for bit in range(4):
        if int(pile.get("stones",0))&(1<<bit):result.append(MOONSTONES.stone_ids[bit])
    return result

func loot_slots() -> Array[Dictionary]:
    var pile: Dictionary = journey.available_loot()
    var result: Array[Dictionary] = pack_slots(pile.get("items",{}),int(pile.get("keys",0)),150,page,int(pile.get("stones",0)))
    if int(pile.get("gold",0))>0:
        result.push_front({"id":"gold","display":"gold","rect":icon_region("gold",Vector2(237,64))})
    return result

func row_rect(index: int) -> Rect2:
    var list: Array[String] = rows()
    if index<0 or index>=list.size(): return Rect2()
    for slot in loot_slots():
        if slot.id==list[index]: return slot.rect
    return Rect2()

func ensure_selected_visible() -> void:
    if rows().is_empty(): return
    if row_rect(selected).size==Vector2.ZERO: page=0

func take_selected() -> void:
    var list: Array[String] = rows()
    if list.is_empty(): return
    selected=clampi(selected,0,list.size()-1)
    journey.take_loot(list[selected])
    var audio: Node = get_node_or_null("/root/MoonstoneAudio")
    if audio != null:
        for cue in audio.Pack.cues.get("loot_click",[]): audio.play_cue(cue,"loot")
    selected=clampi(selected,0,maxi(0,rows().size()-1))
    page=mini(page,pack_pages(journey.available_loot().get("items",{}))-1)
    queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
    if character_view!=null: return
    if not event is InputEventKey or not event.pressed or event.echo: return
    get_viewport().set_input_as_handled()
    if help_visible and event.keycode != KEY_F1:
        help_visible=false; queue_redraw(); return
    mouse_active=false
    var count: int=rows().size()
    if event.keycode in [KEY_ENTER,KEY_KP_ENTER,KEY_ESCAPE]: finished.emit()
    elif event.keycode in [KEY_I,KEY_TAB,KEY_1]: open_character()
    elif event.keycode==KEY_3: open_character(2)
    elif event.keycode in [KEY_DOWN,KEY_RIGHT] and count: selected=(selected+1)%count; ensure_selected_visible()
    elif event.keycode in [KEY_UP,KEY_LEFT] and count: selected=posmod(selected-1,count); ensure_selected_visible()
    elif event.keycode in [KEY_SPACE,KEY_Z]: take_selected()
    elif event.keycode==KEY_F1: help_visible=not help_visible
    elif event.keycode in [KEY_PAGEUP,KEY_PAGEDOWN]:
        page=posmod(page+(1 if event.keycode==KEY_PAGEDOWN else -1),pack_pages(journey.available_loot().get("items",{})))
        pack_page=posmod(pack_page+(1 if event.keycode==KEY_PAGEDOWN else -1),pack_pages(journey.inventory.items))
    queue_redraw()

func hover_at(point: Vector2) -> String:
    if on_column(point,false): return "EXIT"
    for index in range(3):
        if stat_rect(index).has_point(point): return "IMPROVE %s - %d XP" % [STATS[index],journey.upgrade_cost()]
    for slot in loot_slots():
        if slot.rect.has_point(point):
            return "TAKE "+item_name(slot.id)
    for slot in pack_slots(journey.inventory.items,journey.owned_keys,0,pack_page,journey.quest.stones):
        if slot.rect.has_point(point):
            var carried: bool=journey.REGIONAL_KEYS.has(slot.id) or slot.id in MOONSTONES.stone_ids or journey.character_rules.items[slot.id].effect in ["passive","dragon_passive"]
            return item_name(slot.id)+" - CARRIED" if carried else "USE "+item_name(slot.id)
    return ""

func item_name(id: String) -> String:
    if id=="gold": return "GOLD"
    if id in MOONSTONES.stone_ids:return MOONSTONES.stone_names[MOONSTONES.stone_ids.find(id)]
    return journey.REGIONAL_KEYS[id].name if journey.REGIONAL_KEYS.has(id) else journey.loot_rules.items[id].name

func _unhandled_input(event: InputEvent) -> void:
    if character_view!=null: return
    if event is InputEventMouseMotion:
        mouse_active=true; pointer=event.position; hovered=hover_at(pointer); queue_redraw()
        return
    if not event is InputEventMouseButton or not event.pressed or event.button_index!=MOUSE_BUTTON_LEFT: return
    get_viewport().set_input_as_handled()
    if help_visible: help_visible=false; queue_redraw(); return
    mouse_active=true; pointer=event.position
    if on_column(pointer,false): finished.emit(); return
    for index in range(3):
        if stat_rect(index).has_point(pointer):
            journey.upgrade_stat(STATS[index]); show_feedback(); return
    if page_rect.has_point(pointer) and pack_pages(journey.available_loot().get("items",{}))>1:
        page=(page+1)%pack_pages(journey.available_loot().get("items",{}))
    elif pack_page_rect.has_point(pointer) and pack_pages(journey.inventory.items)>1:
        pack_page=(pack_page+1)%pack_pages(journey.inventory.items)
    else:
        for slot in pack_slots(journey.inventory.items,journey.owned_keys,0,pack_page,journey.quest.stones):
            if slot.rect.has_point(pointer): use_carried(slot.id); hovered=hover_at(pointer); queue_redraw(); return
        for slot in loot_slots():
            if slot.rect.has_point(pointer):
                selected=rows().find(slot.id); take_selected(); break
    hovered=hover_at(pointer)
    queue_redraw()

func _draw() -> void:
    if journey==null: return
    draw_classic_background(true)
    draw_sheet(journey,0)
    draw_slots(pack_slots(journey.inventory.items,journey.owned_keys,0,pack_page,journey.quest.stones))
    draw_slots(loot_slots())
    var pile: Dictionary=journey.available_loot()
    if int(pile.get("gold",0))>0: pixel_text("%d gp." % pile.gold,Vector2(484,182))
    var pages: int=pack_pages(pile.get("items",{}))
    if pages>1: pixel_text("LOOT %d/%d >" % [page+1,pages],page_rect.position)
    var owned_pages: int=pack_pages(journey.inventory.items)
    if owned_pages>1:
        draw_rect(pack_page_rect,Color.BLACK)
        pixel_text("PACK %d/%d >" % [pack_page+1,owned_pages],pack_page_rect.position)
    var caption: String="THE CHEST IS EMPTY" if rows().is_empty() else "TAKE "+item_name(rows()[clampi(selected,0,rows().size()-1)])
    draw_caption(hovered if mouse_active else caption)
    if not feedback.is_empty():
        # Leave character values and original object positions unobstructed.
        var line: String=""
        var y: int=16
        for word in (feedback+" ").split(" "):
            if (line+" "+word).length()>45 or word.is_empty():
                draw_rect(Rect2(80,y,480,14),Color.BLACK)
                pixel_text(line,Vector2(320,y),true,Color("ddc68c")); y+=14; line=""
            line=word if line.is_empty() else line+" "+word
    var fallback: Vector2=continue_rect.position+Vector2(16,130) if rows().is_empty() else row_rect(selected).get_center()
    draw_help("RIGHT PANEL: CLICK TREASURE TO TAKE ONE\nLEFT PANEL: CLICK AN ITEM TO USE IT\nCLICK A STAT TO SPEND XP\nI / TAB: PACK   3: STAT UPGRADES\nARROWS SELECT LOOT / SPACE TAKES\nARCH COLUMN / ENTER / ESC: EXIT\nUNTAKEN TREASURE STAYS AT THE LAIR\nPGUP / PGDN: EXTRA PACK PAGES")
    draw_pointer(fallback)
