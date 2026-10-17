extends "res://scripts/presentation/original_panel_view.gd"

var reason: String="Paused"
var selected: int=0
var options: Node2D
var controls: Node

func _ready() -> void:
    process_mode=Node.PROCESS_MODE_ALWAYS
    z_index=100
    super._ready();controls=get_node("/root/MoonstoneInput")

func activate() -> void:
    if selected==0:controls.close_pause();return
    options=preload("res://scripts/presentation/controller_options.gd").new()
    set_process_unhandled_key_input(false);set_process_unhandled_input(false)
    options.finished.connect(func() -> void:
        options.set_process_unhandled_key_input(false);options.set_process_unhandled_input(false)
        options.queue_free();options=null
        set_process_unhandled_key_input(true);set_process_unhandled_input(true)
        controls.block_held();queue_redraw())
    add_child(options)

func _unhandled_key_input(event: InputEvent) -> void:
    if not event is InputEventKey or not event.pressed or event.echo:return
    get_viewport().set_input_as_handled()
    if event.keycode==KEY_ESCAPE:controls.close_pause()
    elif event.keycode in [KEY_SPACE,KEY_ENTER,KEY_KP_ENTER,KEY_Z]:activate()
    elif event.keycode in [KEY_UP,KEY_DOWN]:selected=1-selected;queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
    if not event is InputEventMouseButton or not event.pressed or event.button_index!=MOUSE_BUTTON_LEFT:return
    get_viewport().set_input_as_handled()
    for index in range(2):
        if Rect2(80,180+index*55,480,45).has_point(event.position):selected=index;activate();break

func _draw() -> void:
    draw_rect(Rect2(0,0,640,400),Color(0.01,0.015,0.025,0.94))
    pixel_text(reason.to_upper(),Vector2(320,95),true,Color("ddc68c"))
    for index in range(2):
        if index==selected:draw_rect(Rect2(80,180+index*55,480,45),Color(0.22,0.19,0.09))
        pixel_text(["RESUME","CONTROLLER SETUP"][index],Vector2(320,195+index*55),true)
