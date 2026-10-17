extends "res://scripts/presentation/classic_panel_view.gd"

const MOONSTONES=preload("res://content/generated/moonstone_quest.tres")

# Logical source coordinates are doubled once, keeping art and hit regions aligned.
const GROUPS = {
    "healing_potion": [31,165,13,4], "gem_of_seeing": [87,164,16,4],
    "ring_of_protection": [33,149,12,3], "talisman_of_the_wyrm": [69,133,20,4],
    "scroll_of_haste": [30,183,11,2], "scroll_of_acquisition": [80,183,11,2],
    "scroll_of_the_hawk": [55,183,11,2], "scroll_of_the_wyrm": [105,183,11,2],
    "scroll_of_protection": [130,183,11,2], "sword_of_sharpness": [43,95,0,1],
    "key_moors": [76,111,0,1], "key_wetlands": [94,111,0,1],
    "key_wastes": [112,111,0,1], "key_forest": [130,111,0,1]
}
var mouse_active: bool = false
var pointer := Vector2.ZERO
var old_mouse_mode: int = Input.MOUSE_MODE_VISIBLE
var help_visible: bool = false

func _ready() -> void:
    super._ready()
    old_mouse_mode = Input.mouse_mode
    Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
    texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    pointer = cursor_position()
    var controls: Node=get_node_or_null("/root/MoonstoneInput")
    if controls!=null:controls.cursor_moved.connect(queue_redraw)

func _exit_tree() -> void:
    Input.mouse_mode = old_mouse_mode

func pixel_text(value: String, point: Vector2, centered: bool = false, colour: Color = Color.WHITE) -> void:
    var x: float = roundf(point.x - value.length()*5 if centered else point.x)
    for ch in value:
        var glyph: Array = art.glyphs.get(ch, art.glyphs[" "])
        draw_texture_rect_region(art.pixel_font, Rect2(x,point.y,glyph[2]*2,glyph[3]*2), Rect2(glyph[0],glyph[1],glyph[2],glyph[3]),colour)
        x += 10

func original_icon(id: String, point: Vector2) -> Rect2:
    var texture: Texture2D = art.icon_for(id)
    if texture == null: return Rect2()
    var rect := Rect2(point*2,texture.get_size()*2)
    draw_texture_rect(texture,rect,false)
    return rect

func icon_region(id: String, point: Vector2) -> Rect2:
    var texture: Texture2D = art.icon_for(id)
    return Rect2(point*2,texture.get_size()*2) if texture != null else Rect2()

func panel_columns(single: bool) -> Array[Rect2]:
    var result: Array[Rect2] = []
    for x in ([74,222] if single else [0,148,296]):
        result.append(Rect2(x*2,166,50,234))
    return result

func on_column(point: Vector2, single: bool) -> bool:
    for rect in panel_columns(single):
        if rect.has_point(point): return true
    return false

func draw_sheet(journey: RefCounted, shift: int, label: String="SIR KNIGHT", life_icon: Texture2D=null) -> void:
    var knight: RefCounted = journey.character
    if label=="SIR KNIGHT":
        label=journey.identity.name
        if journey.identity.kind!=0:life_icon=preload("res://assets/classic/knight_selection/art.tres").life_icons[journey.identity.kind]
    pixel_text(label,Vector2(60+shift,24)*2)
    for index in range(3):
        var stat: String = ["strength","constitution","endurance"][index]
        original_icon(stat,Vector2(41+shift,35+index*7))
        pixel_text(str(knight.stats[stat]),Vector2(63+shift,35+index*7)*2)
    for index in range(3):
        original_icon(["xp_label","gold_label","hit_label"][index],Vector2(89+shift,35+index*7))
    pixel_text(str(knight.experience),Vector2(112+shift,35)*2)
    pixel_text(str(journey.inventory.gold),Vector2(112+shift,42)*2)
    pixel_text("%d/%d" % [knight.health,knight.maximum(journey.inventory.items)],Vector2(112+shift,49)*2)
    for index in range(knight.lives):
        var point:=Vector2(41+shift+index*19,59)
        if life_icon==null:original_icon("knight",point)
        else:draw_texture_rect(life_icon,Rect2(point*2,life_icon.get_size()*2),false)
    for index in range(knight.daggers): original_icon("dagger",Vector2(38+shift+index*10,78))
    original_icon(knight.effective_weapon(journey.inventory.items),Vector2(43+shift,95))
    original_icon(knight.armour,Vector2(29+shift,112))

func pack_slots(items: Dictionary, keys: int, shift: int, page: int = 0, stones: int = 0) -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    for id in GROUPS:
        var group: Array = GROUPS[id]
        var count: int = int(items.get(id,0))
        if id.begins_with("key_"):
            var bit: int = {"key_moors":1,"key_wetlands":2,"key_wastes":4,"key_forest":8}[id]
            count = 1 if keys & bit else 0
        var first: int = 0 if id.begins_with("key_") else page*int(group[3])
        for index in range(mini(int(group[3]),maxi(0,count-first))):
            var point := Vector2(group[0]+shift+index*group[2],group[1])
            var display_id: String = "scroll_back" if id.begins_with("scroll_") and index>0 else id
            result.append({"id":id,"display":display_id,"rect":icon_region(display_id,point),"ordinal":first+index})
    var stone_index: int=0
    for bit in range(4):
        if not(stones&(1<<bit)):continue
        var id: String=MOONSTONES.stone_ids[bit]
        # First original moonstone at103,111. Multiple objects use a bounded
        # native row until an original multiple-stone sheet is compared.
        var point:=Vector2(103+shift-stone_index*17,111)
        result.append({"id":id,"display":id,"rect":icon_region(id,point),"ordinal":0})
        stone_index+=1
    return result

func pack_pages(items: Dictionary) -> int:
    var pages: int = 1
    for id in items:
        if GROUPS.has(id): pages = maxi(pages,ceili(float(items[id])/int(GROUPS[id][3])))
    return pages

func draw_slots(slots: Array[Dictionary]) -> void:
    for slot in slots: draw_icon(slot.display,slot.rect)

func cursor_position() -> Vector2:
    var controls: Node=get_node_or_null("/root/MoonstoneInput")
    var point: Vector2=controls.cursor_position() if controls!=null else get_viewport().get_mouse_position()
    return get_global_transform_with_canvas().affine_inverse()*point

func draw_pointer(selection: Vector2) -> void:
    # Selection and mouse position are independent. Drawing the sword at the
    # selected object made the first mouse click hit somewhere else entirely.
    if not mouse_active:
        draw_colored_polygon(PackedVector2Array([selection+Vector2(-12,-5),selection+Vector2(-12,5),selection+Vector2(-6,0)]),Color("ddc68c"))
    var controls: Node=get_node_or_null("/root/MoonstoneInput")
    if controls!=null and controls.using_controller and controls.pointer_active:return # Shared controller overlay owns the sword.
    draw_texture_rect(art.sword_cursor,Rect2(cursor_position().round(),art.sword_cursor.get_size()*2),false)

func draw_caption(value: String) -> void:
    pixel_text(value.to_upper(),Vector2(320,2),true)

func draw_help(value: String) -> void:
    if not help_visible: return
    var controls: Node=get_node_or_null("/root/MoonstoneInput")
    if controls!=null and controls.using_controller:
        value="CONTROLLER\nSTICK / D-PAD: MOVE OR SELECT\n"+controls.binding_name("accept")+": CHOOSE / USE / TAKE\n"+controls.binding_name("cancel")+": BACK / CLOSE\n"+controls.binding_name("inventory")+": INVENTORY\n"+controls.binding_name("previous_page")+" / "+controls.binding_name("next_page")+": PACK PAGES\n"+controls.binding_name("previous_tab")+" / "+controls.binding_name("next_tab")+": SHEETS\nREMAP IN OPTIONS / CONTROLLER"
        value+="\nRIGHT STICK: SWORD CURSOR / "+controls.binding_name("click")+": CLICK\nHOLD "+controls.binding_name("alternate")+" + PAGE: OWN PACK"
    var lines: Array[String]=[]
    for line in value.split("\n"):
        var current: String=""
        for word in line.split(" "):
            if (current+" "+word).length()>54:
                lines.append(current); current=""
            current=word if current.is_empty() else current+" "+word
        lines.append(current)
    var height: int=lines.size()*24+24
    var y: int=(400-height)/2
    draw_rect(Rect2(30,y,580,height),Color("080808"))
    draw_rect(Rect2(30,y,580,height),Color("888888"),false,2)
    y+=12
    for line in lines:
        pixel_text(line.to_upper(),Vector2(320,y),true)
        y += 24
