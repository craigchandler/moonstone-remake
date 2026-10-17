extends "res://scripts/presentation/original_panel_view.gd"

signal service_requested(id: String)
signal finished
var journey: RefCounted
var selected: int = 0
var world_art: Resource = preload("res://assets/classic/world/art.tres")

func rows() -> Array:
    return world_art.town_layouts[journey.town_id].entries

func button_rect(index: int) -> Rect2:
    var values: Array=world_art.town_layouts[journey.town_id].rectangles[index]
    return Rect2(values[0]*2,values[1]*2,values[2]*2,values[3]*2)

func dismiss_overlay() -> void:
    help_visible=false
    queue_redraw()

func activate() -> void:
    if help_visible:
        dismiss_overlay()
        return
    selected=clampi(selected,0,rows().size()-1)
    var id: String=rows()[selected]
    if id=="leave": finished.emit()
    elif id in journey.town(journey.town_id).services or id in ["tavern","mystic"]: service_requested.emit(id)

func _unhandled_key_input(event: InputEvent) -> void:
    if not event is InputEventKey or not event.pressed or event.echo: return
    get_viewport().set_input_as_handled()
    if help_visible:
        dismiss_overlay()
        return
    mouse_active=false
    if event.keycode==KEY_ESCAPE: finished.emit()
    elif event.keycode==KEY_I: service_requested.emit("pack")
    elif event.keycode==KEY_F1: help_visible=true
    elif event.keycode in [KEY_ENTER,KEY_KP_ENTER,KEY_SPACE,KEY_Z]: activate()
    elif event.keycode in [KEY_UP,KEY_DOWN]: selected=posmod(selected+(1 if event.keycode==KEY_DOWN else -1),rows().size())
    queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion:
        mouse_active=true
        pointer=event.position
        if not help_visible:
            for index in range(rows().size()):
                if button_rect(index).has_point(pointer): selected=index; break
        queue_redraw()
        return
    if not event is InputEventMouseButton or not event.pressed or event.button_index!=MOUSE_BUTTON_LEFT: return
    get_viewport().set_input_as_handled()
    mouse_active=true
    pointer=event.position
    if help_visible:
        dismiss_overlay()
        return
    for index in range(rows().size()):
        if button_rect(index).has_point(pointer):
            selected=index
            activate()
            return
    queue_redraw()

func _draw() -> void:
    if journey==null or journey.town_id.is_empty(): return
    # The original picture contains its own menu: Highwood right, Waterdeep left.
    draw_texture_rect(world_art.get(journey.town_id),Rect2(0,0,640,400),false)
    if help_visible:
        var help: String="ARROWS SELECT / SPACE OR CLICK ENTERS\nI: INVENTORY / ESC: LEAVE TOWN\nEXIT ENDS THE TURN\nHEALTH %d/%d  LIVES %d  GOLD %d  XP %d  ROUND %d" % [journey.character.health,journey.character.maximum(journey.inventory.items),journey.character.lives,journey.inventory.gold,journey.character.experience,journey.day]
        draw_help(help)
    draw_pointer(button_rect(selected).get_center())
