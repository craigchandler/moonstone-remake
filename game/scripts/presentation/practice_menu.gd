extends "res://scripts/presentation/original_panel_view.gd"

signal chosen(encounter: StringName)
signal network_requested
const Practice = preload("res://scripts/session/practice_session.gd")
const Identity = preload("res://scripts/domain/knight_identity.gd")
var rules: Resource = preload("res://content/foundation_rules.tres")
var creature_art: Resource = preload("res://content/generated/classic_layered_art.tres")
var creature_renderer: RefCounted = preload("res://scripts/presentation/graphics/classic_combat_renderer.gd").new()
var choices: Array[String] = Practice.CHOICES.duplicate()
var selected: int = 0
var knight_kind: int = 0
var begin_rect := Rect2(76,292,206,26)
var network_rect := Rect2(76,318,206,26)
var back_rect := Rect2(76,344,206,24)

func row_rect(index: int) -> Rect2:
    return Rect2(356,86+index*22,226,22)

func colour_rect(step: int) -> Rect2:
    return Rect2(66 if step < 0 else 256,244,36,32)

func choose() -> void:
    chosen.emit(StringName(choices[selected]))

func _unhandled_key_input(event: InputEvent) -> void:
    if not event is InputEventKey or not event.pressed or event.echo: return
    get_viewport().set_input_as_handled()
    mouse_active = false
    if event.keycode == KEY_F1: help_visible = not help_visible
    elif help_visible: help_visible = false
    elif event.keycode == KEY_ESCAPE: chosen.emit(&"")
    elif event.keycode in [KEY_N,KEY_PAGEDOWN]: network_requested.emit()
    elif event.keycode in [KEY_UP,KEY_DOWN]: selected = posmod(selected + (1 if event.keycode == KEY_DOWN else -1), choices.size())
    elif event.keycode in [KEY_LEFT,KEY_RIGHT]: knight_kind = posmod(knight_kind + (1 if event.keycode == KEY_RIGHT else -1), 4)
    elif event.keycode in [KEY_ENTER,KEY_KP_ENTER,KEY_SPACE,KEY_Z]: choose()
    queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion:
        mouse_active = true; pointer = event.position; queue_redraw()
        return
    if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT: return
    get_viewport().set_input_as_handled()
    mouse_active = true; pointer = event.position
    if help_visible: help_visible = false
    elif back_rect.has_point(pointer) or on_column(pointer,false): chosen.emit(&"")
    elif begin_rect.has_point(pointer): choose()
    elif network_rect.has_point(pointer): network_requested.emit()
    elif colour_rect(-1).has_point(pointer): knight_kind = posmod(knight_kind-1,4)
    elif colour_rect(1).has_point(pointer): knight_kind = (knight_kind+1)%4
    else:
        for index in range(choices.size()):
            if row_rect(index).has_point(pointer): selected = index; break
    queue_redraw()

func preview_parts(kind: String) -> Array[Dictionary]:
    var animation: Resource = creature_art.animation_for(kind)
    if animation == null: return []
    var result: Array[Dictionary] = []
    if kind == "dragon":
        for depth in [-20,10]: result.append({"animation":animation,"pose":animation.sample("feet_idle",0),"point":Vector2(-65,depth)})
    if kind == "guardian":
        var body: Resource = creature_art.animation_for("guardian_finishes")
        result.append({"animation":body,"pose":body.sample("body",0),"point":Vector2.ZERO})
    result.append({"animation":animation,"pose":animation.sample("idle",0),"point":Vector2(0,-30) if kind == "dragon" else Vector2.ZERO})
    return result

func preview_bounds(parts: Array[Dictionary]) -> Rect2:
    var bounds := Rect2()
    for part in parts:
        var pose: Dictionary = part.pose
        var rect := Rect2(pose.offset+part.point,pose.logical_size)
        # Layer cels retain a transparent source canvas. Fit actual pieces, using
        # only presentation metadata; arena positions/collision stay untouched.
        if part.animation.layers != null:
            var pieces: Array = part.animation.layers.pieces(pose.index,false)
            if not pieces.is_empty():
                rect = Rect2(pose.offset+part.point+pieces[0].offset,pieces[0].size)
                for piece in pieces: rect = rect.merge(Rect2(pose.offset+part.point+piece.offset,piece.size))
        bounds = rect if bounds.size == Vector2.ZERO else bounds.merge(rect)
    return bounds

func draw_preview(kind: String, point: Vector2, colour: int, variant: String, facing: int = 0) -> void:
    var parts: Array[Dictionary] = preview_parts(kind)
    if parts.is_empty(): return
    var bounds: Rect2 = preview_bounds(parts)
    var scale: float = minf(2.0,minf(104.0/bounds.size.x,128.0/bounds.size.y))
    var origin := -Vector2(bounds.get_center().x,bounds.end.y)
    draw_set_transform(point,0.0,Vector2((1 if variant == "blue" else -1) if facing==0 else facing,1))
    for part in parts:
        creature_renderer.draw_pose(self,part.animation,part.pose,variant,false,colour,origin+part.point,scale)
    draw_set_transform(Vector2.ZERO)

func _draw() -> void:
    draw_classic_background()
    var gold := Color("ddc68c")
    pixel_text("PRACTICE",Vector2(320,8),true,gold)
    pixel_text("YOUR KNIGHT",Vector2(174,60),true,gold)
    pixel_text("OPPONENT",Vector2(470,60),true,gold)
    var kind: String = rules.encounters.get(choices[selected],{}).get("creature","knight")
    draw_preview("knight",Vector2(116,224),knight_kind,"blue")
    draw_preview(kind,Vector2(236,224),0,"purple")
    pixel_text(Identity.COLOURS[knight_kind].to_upper(),Vector2(174,252),true)
    draw_colored_polygon(PackedVector2Array([Vector2(82,252),Vector2(92,246),Vector2(92,258)]),gold)
    draw_colored_polygon(PackedVector2Array([Vector2(276,252),Vector2(266,246),Vector2(266,258)]),gold)
    pixel_text("LEFT / RIGHT",Vector2(174,276),true,Color("aaaeb8"))
    pixel_text("BEGIN",begin_rect.position+Vector2(begin_rect.size.x/2,8),true,gold)
    pixel_text("NETWORK DUEL",network_rect.position+Vector2(network_rect.size.x/2,8),true,gold)
    pixel_text("BACK",back_rect.position+Vector2(back_rect.size.x/2,8),true,gold)
    for index in range(choices.size()):
        var rect: Rect2 = row_rect(index)
        pixel_text(Practice.LABELS[choices[index]],rect.position+Vector2(18,5),false,gold if selected==index else Color.WHITE)
    var selected_point: Vector2 = row_rect(selected).position+Vector2(14,11)
    draw_pointer(selected_point)
    pixel_text("UP / DOWN OPPONENT",Vector2(174,372),true,gold)
    pixel_text("ENTER FIGHT",Vector2(470,372),true,gold)
    pixel_text("LEFT / RIGHT KNIGHT",Vector2(174,388),true,Color("aaaeb8"))
    pixel_text("N NETWORK / ESC BACK",Vector2(470,388),true,Color("aaaeb8"))
    draw_help("UP / DOWN: CHOOSE AN OPPONENT\nLEFT / RIGHT: CHOOSE YOUR KNIGHT\nENTER / SPACE / Z / BEGIN: FIGHT\nCLICK AN OPPONENT TO SELECT\nN / PAGEDOWN: NETWORK DUEL\nR: RETRY A PRACTICE FIGHT\nESC: RETURN TO OPPONENTS / TITLE\nEACH FIGHT STARTS WITH FRESH HEALTH AND DAGGERS\nJOURNEY EQUIPMENT AND PROGRESS STAY UNCHANGED", "STICK / D-PAD: CHOOSE OPPONENT / KNIGHT\nCONFIRM: BEGIN / BACK: TITLE\nRIGHT STICK: SWORD CURSOR / R3: CLICK\nNEXT PAGE BUTTON: NETWORK DUEL\nVIEW: LEAVE A PRACTICE FIGHT\nSTART: PAUSE / CONTROLLER SETUP\nJOURNEY PROGRESS STAYS UNCHANGED")
