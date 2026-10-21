extends "res://scripts/presentation/original_panel_view.gd"
var debug_mode: bool=false

signal chosen(action: String)
signal options_changed(revisit_battles: bool)
const OPENING=preload("res://assets/classic/intro_menu/art.tres")
var saved: Dictionary = {}
var notice: String = ""
var selected: int = 0
var options_open: bool = false
var revisit_battles: bool = false
var start_music: bool=true
var controller_view: Node2D

func _ready() -> void:
    super._ready()
    var audio: Node=get_node_or_null("/root/MoonstoneAudio")
    if audio!=null and start_music:audio.menu_music()

func rows() -> Array:
    if options_open:return ["revisit","controller","back"]
    return ["continue", "new", "network", "practice", "intro", "options", "exit"] if not saved.is_empty() else ["new", "network", "practice", "intro", "options", "exit"]

func button_rect(index: int) -> Rect2:
    if rows().size()>6:return Rect2(96,132+index*36,480,34)
    return Rect2(96,(142+index*38) if rows().size()>5 else (152+index*46),480,38)

func activate(action: String) -> void:
    if action in ["options","back"]:
        options_open=action=="options"
        selected=0
    elif action=="controller":
        controller_view=preload("res://scripts/presentation/controller_options.gd").new()
        set_process_unhandled_key_input(false);set_process_unhandled_input(false)
        controller_view.finished.connect(func() -> void:
            controller_view.set_process_unhandled_key_input(false);controller_view.set_process_unhandled_input(false)
            controller_view.queue_free();controller_view=null
            set_process_unhandled_key_input(true);set_process_unhandled_input(true)
            get_node("/root/MoonstoneInput").block_held();queue_redraw())
        add_child(controller_view)
    elif action=="revisit":
        revisit_battles=not revisit_battles
        options_changed.emit(revisit_battles)
    else:chosen.emit(action)
    queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
    if not event is InputEventKey or not event.pressed or event.echo: return
    get_viewport().set_input_as_handled()
    if event.keycode==KEY_F1:help_visible=not help_visible
    elif help_visible:help_visible=false
    elif event.keycode == KEY_C and not saved.is_empty() and not options_open: activate("continue")
    elif event.keycode == KEY_N and not options_open: activate("new")
    elif event.keycode == KEY_M and not options_open: activate("network")
    elif event.keycode == KEY_P and not options_open: activate("practice")
    elif event.keycode == KEY_O: activate("back" if options_open else "options")
    elif event.keycode == KEY_ESCAPE: activate("back" if options_open else "exit")
    elif event.keycode in [KEY_ENTER, KEY_KP_ENTER,KEY_SPACE,KEY_Z]: activate(rows()[selected])
    elif event.keycode in [KEY_UP, KEY_DOWN]: selected = posmod(selected + (1 if event.keycode == KEY_DOWN else -1), rows().size())
    queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion:
        for index in range(rows().size()):
            if button_rect(index).has_point(event.position):selected=index;queue_redraw();break
        return
    if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT: return
    if help_visible:
        help_visible=false;get_viewport().set_input_as_handled();queue_redraw();return
    for index in range(rows().size()):
        if button_rect(index).has_point(event.position):
            get_viewport().set_input_as_handled()
            selected=index
            activate(rows()[index])
            return

func small_lines(value: String,y: int) -> void:
    var line: String=""
    for word in value.split(" "):
        if (line+" "+word).length()>58:
            pixel_text(line.to_upper(),Vector2(320,y),true,Color("ddc68c"));y+=16;line=""
        line=word if line.is_empty() else line+" "+word
    if not line.is_empty():pixel_text(line.to_upper(),Vector2(320,y),true,Color("ddc68c"))

func _draw() -> void:
    draw_texture_rect(OPENING.background,Rect2(0,0,640,400),false)
    draw_texture_rect(OPENING.title,Rect2(10,20,610,108),false)
    if debug_mode:pixel_text("DEBUG - PROGRESS IS NOT SAVED",Vector2(320,130),true,Color("ddc68c"))
    var labels: Dictionary = {"continue":"Continue", "new":"New journey", "network":"Network journey", "practice":"Practice", "intro":"Watch intro", "options":"Options", "exit":"Exit", "controller":"Controller", "revisit":"Revisit: "+("On" if revisit_battles else "Off"), "back":"Back"}
    for index in range(rows().size()):
        var rect: Rect2=button_rect(index)
        OPENING.draw_text(self,labels[rows()[index]],Vector2(336,rect.position.y))
    var cursor: Rect2=button_rect(clampi(selected,0,rows().size()-1))
    draw_texture_rect(OPENING.arrow,Rect2(100,cursor.position.y,76,38),false)
    if options_open:
        small_lines("Leave treasure to revisit a lair.",302)
        small_lines("On: fight again and earn 1 XP." if revisit_battles else "Off: return straight to its treasure.",324)
        small_lines("Treasure stays the same. Empty lairs disappear.",346)
    if not notice.is_empty():small_lines(notice,382)
    elif get_node("/root/MoonstoneInput").using_controller:
        var pad: Node=get_node("/root/MoonstoneInput")
        pixel_text((pad.binding_name("accept")+" CHOOSE / "+pad.binding_name("cancel")+" BACK / OPTIONS: CONTROLLER").to_upper(),Vector2(320,382),true,Color("aaaeb8"))
    draw_help("ARROWS SELECT / ENTER / SPACE / Z CHOOSES\nCLICK A ROW TO CHOOSE\nC: CONTINUE / N: NEW / P: PRACTICE / O: OPTIONS\nESC: BACK OR EXIT\nWATCH INTRO REPLAYS THE OPENING\nF8: SOUND / F9-F10: VOLUME")
