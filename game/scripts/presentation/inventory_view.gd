extends "res://scripts/presentation/original_panel_view.gd"

signal finished

const ServiceScreen=preload("res://scripts/presentation/town_service_screen.gd")
const TargetedScrollView=preload("res://scripts/presentation/targeted_scroll_view.gd")
var target_view: Node2D
var service_screen: RefCounted

var journey: RefCounted
var loot_context: bool = false
var world_art: Resource = preload("res://assets/classic/world/art.tres")
var tab: int = 0
var selected: int = 0
var target_item: String = ""
var cursor: Vector2i
var inspection: String = ""
var page: int = 0
var hovered: String = ""
var target_rect := Rect2(120,65,400,250)
var teleport_button_rect := Rect2(266,330,108,20)
var page_rect := Rect2(502,268,134,18)
var last_message: String = ""
var message_ticks: int = 0

func _process(_delta: float) -> void:
    if service_screen!=null:service_screen.sync_audio(self)
    if journey.message!=last_message:
        last_message=journey.message
        message_ticks=180
        queue_redraw()
    if message_ticks>0:
        message_ticks-=1
        if message_ticks==0: queue_redraw()

func advance_visit() -> void:
    if service_screen!=null:service_screen.advance(self)

func single_panel() -> bool:
    return tab in [0,2] and inspection.is_empty()

func panel_shift() -> int:
    return 74 if single_panel() else 0

func rows() -> Array[String]:
    if service_screen!=null: return service_screen.rows()
    var result: Array[String]=[]
    if target_item=="gem_of_seeing":
        for site in journey.world.definition.lairs:
            if not journey.world.cleared.has(site.id): result.append(site.id)
    elif tab==0:
        for id in journey.loot_rules.items:
            if int(journey.inventory.items.get(id,0))>0: result.append(id)
        for id in journey.REGIONAL_KEYS:
            if journey.owned_keys & int(journey.REGIONAL_KEYS[id].bit): result.append(id)
        for bit in range(4):
            if journey.quest.stones & (1<<bit):result.append(MOONSTONES.stone_ids[bit])
    elif tab==3: result.assign(["heal_health","heal_life"])
    elif tab==1: result.assign(["broad_sword","claymore","chainmail","platemail","battleplate","dagger"])
    else: result.assign(["strength","constitution","endurance"])
    return result

func inventory_slots() -> Array[Dictionary]:
    return pack_slots(journey.inventory.items,journey.owned_keys,panel_shift(),page,journey.quest.stones)

func row_rect(index: int) -> Rect2:
    if service_screen!=null: return service_screen.row_rect(index)
    var list: Array[String]=rows()
    if index<0 or index>=list.size(): return Rect2()
    var id: String=list[index]
    if target_item=="gem_of_seeing":
        var point: Vector2=target_rect.position+Vector2(journey.world.lair(id).position)/Vector2(320,200)*target_rect.size
        return Rect2(point-Vector2(9,9),Vector2(18,18))
    if tab==0:
        for slot in inventory_slots():
            if slot.id==id: return slot.rect
        return Rect2()
    if tab==2: return Rect2((41+74)*2,70+index*14,80,14)
    if tab==3: return icon_region("healing_potion" if index==0 else "knight",Vector2(211+index*48,80)).grow(8)
    return icon_region(id,[Vector2(200,107),Vector2(197,125),Vector2(173,145),Vector2(214,145),Vector2(256,144),Vector2(182,89)][index])

func tab_rect(index: int) -> Rect2:
    return [Rect2(4,2,72,16),Rect2(560,2,76,16),Rect2(550,24,86,16)][index]

func set_tab(index: int) -> void:
    if loot_context and index not in [0,2]: return
    tab=clampi(index,0,5)
    service_screen=ServiceScreen.new({3:"healer",4:"tavern",5:"mystic"}[tab]) if tab>=3 else null
    if service_screen!=null:service_screen.journey=journey
    if loot_context: pass
    elif tab==1: journey.open_service("smith")
    elif tab==2: journey.open_service("temple")
    elif tab>=3: journey.open_service({3:"healer",4:"tavern",5:"mystic"}[tab])
    else: journey.service=""
    selected=0; target_item=""; inspection=""; page=0
    journey.message=""; hovered=""
    queue_redraw()

func open_targeted_scroll(id: String) -> void:
    if target_view!=null:return
    if preload("res://scripts/domain/targeted_scrolls.gd").targets(journey).is_empty():
        journey.message="There are no living rival knights. Scroll kept."
        return
    journey.message=""
    target_view=TargetedScrollView.new()
    target_view.journey=journey;target_view.item=id
    add_child(target_view)
    target_view.finished.connect(close_targeted_scroll)

func close_targeted_scroll(_used: bool) -> void:
    remove_child(target_view);target_view.queue_free();target_view=null
    selected=clampi(selected,0,maxi(0,rows().size()-1))
    page=mini(page,pack_pages(journey.inventory.items)-1)
    hovered="";queue_redraw()

func activate() -> void:
    if target_view!=null:return
    if service_screen!=null: service_screen.activate(self); return
    if target_item == "scroll_of_the_hawk":
        if journey.use_item(target_item, cursor):
            target_item = ""
            if loot_context: finished.emit(); return
        queue_redraw()
        return
    var list: Array[String] = rows()
    if list.is_empty(): return
    selected = clampi(selected, 0, list.size() - 1)
    var id: String = list[selected]
    if target_item == "gem_of_seeing":
        if journey.use_item(target_item, id):
            inspection = id
            target_item = ""
    elif tab == 0:
        inspection = ""
        if id in MOONSTONES.stone_ids:
            journey.message="Carried moonstones respond to the moon. Visit Stonehenge in the matching phase."
            queue_redraw();return
        if journey.REGIONAL_KEYS.has(id):
            journey.message = "Keep all four regional keys to enter the Valley of the Gods."
            queue_redraw()
            return
        var effect: String = journey.character_rules.items[id].effect
        if effect in ["rival","dragon_target"] and journey.pending_attack.is_empty():
            open_targeted_scroll(id)
        elif effect in ["reveal", "teleport"]:
            target_item = id
            cursor = journey.world.position
            selected = 0
            journey.message = "Choose a lair." if effect == "reveal" else "Choose a destination; Space confirms."
        else:
            var pending: bool = not journey.pending_attack.is_empty()
            if journey.use_item(id) and pending:
                finished.emit()
                return
    elif tab == 3: journey.buy_healing(id)
    elif tab == 1: journey.buy_equipment(id)
    else: journey.upgrade_stat(id)
    selected = clampi(selected, 0, maxi(0, rows().size() - 1))
    queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
    if target_view!=null:return
    if not event is InputEventKey or not event.pressed: return
    if event.echo and not (target_item=="scroll_of_the_hawk" and event.keycode in [KEY_UP,KEY_DOWN,KEY_LEFT,KEY_RIGHT]): return
    get_viewport().set_input_as_handled()
    if service_screen!=null: service_screen.key(event,self); return
    if help_visible and event.keycode != KEY_F1:
        help_visible=false; queue_redraw(); return
    mouse_active=false
    if event.keycode==KEY_ESCAPE:
        if not inspection.is_empty(): inspection=""; selected=0
        elif target_item.is_empty(): finished.emit()
        else: target_item=""; selected=0; journey.message="Cancelled. Item kept."
    elif event.keycode==KEY_I or (event.keycode in [KEY_ENTER,KEY_KP_ENTER] and target_item.is_empty()): finished.emit()
    elif event.keycode in [KEY_SPACE,KEY_Z,KEY_ENTER,KEY_KP_ENTER]: activate()
    elif event.keycode==KEY_F1: help_visible=not help_visible
    elif target_item=="scroll_of_the_hawk":
        var direction:=Vector2i(int(event.keycode==KEY_RIGHT)-int(event.keycode==KEY_LEFT),int(event.keycode==KEY_DOWN)-int(event.keycode==KEY_UP))
        var bounds: Rect2i=journey.world.definition.bounds
        cursor=Vector2i(clampi(cursor.x+direction.x,bounds.position.x,bounds.end.x-1),clampi(cursor.y+direction.y,bounds.position.y,bounds.end.y-1))
    elif event.keycode in [KEY_UP,KEY_DOWN]:
        selected=posmod(selected+(1 if event.keycode==KEY_DOWN else -1),maxi(1,rows().size()))
        if target_item.is_empty() and tab==0 and row_rect(selected).size==Vector2.ZERO: page=0
    elif event.keycode in [KEY_PAGEUP,KEY_PAGEDOWN]:
        page=posmod(page+(1 if event.keycode==KEY_PAGEDOWN else -1),pack_pages(journey.inventory.items))
    elif target_item.is_empty():
        if loot_context and event.keycode in [KEY_TAB,KEY_RIGHT,KEY_LEFT]: set_tab(2 if tab==0 else 0)
        elif event.keycode in [KEY_TAB,KEY_RIGHT]: set_tab((tab+1)%3)
        elif event.keycode==KEY_LEFT: set_tab((tab+2)%3)
        elif event.keycode in [KEY_1,KEY_2,KEY_3]: set_tab(int(event.keycode)-int(KEY_1))
    queue_redraw()

func caption_for(id: String) -> String:
    if target_item=="gem_of_seeing": return "SEE "+String(journey.world.lair(id).name)
    if tab==0:
        if id in MOONSTONES.stone_ids:return MOONSTONES.stone_names[MOONSTONES.stone_ids.find(id)]+" - CARRIED"
        if journey.REGIONAL_KEYS.has(id): return journey.REGIONAL_KEYS[id].name+" - HELD"
        var name: String=journey.loot_rules.items[id].name
        var passive: bool=journey.character_rules.items[id].effect in ["passive","dragon_passive"]
        return name+" - CARRIED" if passive else "USE "+name
    if tab==2: return "IMPROVE %s - %d XP" % [id,journey.upgrade_cost()]
    if tab==3:
        return "HEAL WOUNDS - %d GP" % journey.character_rules.healer_health_price if id=="heal_health" else "RESTORE LIFE - %d GP" % journey.character_rules.healer_life_price
    if id=="dagger": return "BUY DAGGER - %d GP" % journey.character_rules.dagger_price
    var entry: Dictionary=journey.character_rules.weapons.get(id,journey.character_rules.armours.get(id,{}))
    return "BUY %s - %d GP" % [entry.name,entry.price]

func hover_at(point: Vector2) -> String:
    if target_item=="scroll_of_the_hawk":
        if target_rect.has_point(point): return "CHOOSE DESTINATION"
        if teleport_button_rect.has_point(point): return "TRAVEL"
        return "CANCEL" if on_column(point,single_panel()) else ""
    if target_item.is_empty() and on_column(point,single_panel()): return "EXIT"
    for index in visible_indices():
        if row_rect(index).has_point(point): return caption_for(rows()[index])
    return ""

func _unhandled_input(event: InputEvent) -> void:
    if target_view!=null:return
    if service_screen!=null: service_screen.input(event,self); return
    if event is InputEventMouseMotion:
        mouse_active=true; pointer=event.position; hovered=hover_at(pointer); queue_redraw()
        return
    if not event is InputEventMouseButton or not event.pressed or event.button_index!=MOUSE_BUTTON_LEFT: return
    get_viewport().set_input_as_handled()
    if help_visible: help_visible=false; queue_redraw(); return
    mouse_active=true; pointer=event.position
    if on_column(pointer,single_panel()) and (target_item.is_empty() or not target_rect.has_point(pointer)):
        if target_item.is_empty(): finished.emit()
        else: target_item=""; selected=0; journey.message="Cancelled. Item kept."
        return
    if target_item=="scroll_of_the_hawk":
        if target_rect.has_point(pointer):
            var point: Vector2=(pointer-target_rect.position)/target_rect.size*Vector2(320,200)
            var bounds: Rect2i=journey.world.definition.bounds
            cursor=Vector2i(clampi(int(point.x),bounds.position.x,bounds.end.x-1),clampi(int(point.y),bounds.position.y,bounds.end.y-1))
        elif teleport_button_rect.has_point(pointer): activate()
    else:
        if target_item.is_empty():
            for index in range(3):
                if tab_rect(index).has_point(pointer): set_tab(index); return
            if page_rect.has_point(pointer) and pack_pages(journey.inventory.items)>1:
                page=(page+1)%pack_pages(journey.inventory.items); queue_redraw(); return
        if tab==0 and target_item.is_empty():
            for slot in inventory_slots():
                if slot.rect.has_point(pointer):
                    selected=rows().find(slot.id); activate(); break
        else:
            for index in visible_indices():
                var hit: Rect2=row_rect(index)
                if tab==1 and index==5: hit=Rect2(364,178,172,24)
                if hit.has_point(pointer): selected=index; activate(); break
    page=mini(page,pack_pages(journey.inventory.items)-1)
    hovered=hover_at(pointer)
    queue_redraw()

func visible_indices() -> Array:
    return range(rows().size())

func _draw() -> void:
    if journey==null: return
    if service_screen!=null: service_screen.draw(self); return
    if single_panel(): draw_texture_rect(art.single_background,Rect2(0,0,640,400),false)
    else: draw_classic_background(not inspection.is_empty())
    draw_sheet(journey,panel_shift())
    draw_slots(inventory_slots())
    if not inspection.is_empty():
        var pile: Dictionary=journey.lair_loot[inspection]
        draw_slots(pack_slots(pile.items,int(pile.get("keys",0)),150))
        if int(pile.gold)>0:
            original_icon("gold",Vector2(237,64))
            pixel_text("%d gp." % pile.gold,Vector2(484,182))
    elif tab==1:
        pixel_text("THE MERCHANT",Vector2(470,48),true)
        for index in range(6): draw_icon(rows()[index],row_rect(index))
        for index in range(1,10): original_icon("dagger",Vector2(182+index*9,89))
    elif tab==3:
        pixel_text("THE HEALER",Vector2(470,48),true)
        draw_icon("healing_potion",row_rect(0))
        draw_icon("knight",row_rect(1))
        pixel_text("%d GP" % journey.character_rules.healer_health_price,Vector2(430,206),true)
        pixel_text("%d GP" % journey.character_rules.healer_life_price,Vector2(532,206),true)
    for index in range(3):
        if loot_context and index==1: continue
        pixel_text(["1 PACK","2 ARMS","3 STATS"][index],tab_rect(index).position, false,Color("cccccc"))
    if pack_pages(journey.inventory.items)>1:
        pixel_text("PACK %d/%d >" % [page+1,pack_pages(journey.inventory.items)],page_rect.position)
    var list: Array[String]=rows()
    selected=clampi(selected,0,maxi(0,list.size()-1))
    var caption: String="YOUR INVENTORY" if list.is_empty() else caption_for(list[selected])
    if not inspection.is_empty(): caption=String(journey.world.lair(inspection).name)+" TREASURE"
    if target_item in ["scroll_of_the_hawk","gem_of_seeing"]:
        draw_rect(Rect2(108,52,424,310),Color.BLACK)
        draw_texture_rect(world_art.background,target_rect,false)
        if target_item=="gem_of_seeing":
            for index in range(list.size()):
                var rect: Rect2=row_rect(index)
                draw_rect(rect,Color("e5cb89"),false,2)
                pixel_text(str(index+1),rect.position)
            caption="CHOOSE A LAIR TO SEE"
        else:
            var point: Vector2=target_rect.position+Vector2(cursor)/Vector2(320,200)*target_rect.size
            draw_arc(point,9,0,TAU,24,Color.WHITE,2)
            pixel_text("TRAVEL",teleport_button_rect.position+Vector2(24,2))
            caption="CHOOSE DESTINATION"
    if mouse_active: caption=hovered
    draw_caption(caption)
    # Context feedback stays outside the artwork; F1 explains controls/effects on demand.
    if message_ticks>0 and not journey.message.is_empty():
        var words: PackedStringArray=journey.message.split(" ")
        var line: String=""
        var lines: Array[String]=[]
        for word in words:
            if (line+" "+word).length()>45: lines.append(line); line=""
            line=word if line.is_empty() else line+" "+word
        if not line.is_empty(): lines.append(line)
        var y: int=16
        for text in lines:
            draw_rect(Rect2(80,y,468,14),Color.BLACK)
            pixel_text(text,Vector2(320,y),true,Color("ddc68c")); y+=14
    var fallback: Vector2=Vector2(450,220)
    if not list.is_empty(): fallback=row_rect(selected).get_center()
    if target_item=="scroll_of_the_hawk": fallback=teleport_button_rect.get_center()
    var help: String="CLICK AN OBJECT / SPACE TO ACT\nARCH COLUMN / ENTER / I / ESC: CLOSE\nARROWS SELECT / TAB CHANGES SCREEN\n1 PACK / 2 ARMS / 3 STATS\nPGUP / PGDN: EXTRA PACK PAGES"
    if loot_context: help="CLICK AN OBJECT / SPACE TO ACT\nARCH COLUMN / ENTER / I / ESC: BACK TO LOOT\nARROWS SELECT / TAB: PACK OR STATS\n1 PACK / 3 STATS\nHAWK TRAVEL LEAVES UNTAKEN LOOT BEHIND\nPGUP / PGDN: EXTRA PACK PAGES"
    if tab==0 and not list.is_empty() and journey.character_rules.items.has(list[selected]):
        help+="\n\n"+String(journey.character_rules.items[list[selected]].description)
    draw_help(help)
    draw_pointer(fallback)
