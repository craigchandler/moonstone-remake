extends Node2D

signal confirmed(identity: Dictionary)
signal cancelled
signal local_requested
const Identity=preload("res://scripts/domain/knight_identity.gd")
const ART=preload("res://assets/classic/knight_selection/art.tres")
var selected: int=0
var editing: bool=false
var name_value: String=""
var select_all: bool=false
var help_visible: bool=false
var tick: int=0
var old_mouse_mode: int=Input.MOUSE_MODE_VISIBLE

func _ready() -> void:
    add_to_group("moonstone_input_surfaces")
    old_mouse_mode=Input.mouse_mode;Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
    texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST

func _exit_tree() -> void:Input.mouse_mode=old_mouse_mode

func advance() -> void:tick+=1;queue_redraw()

func portrait_rect(index: int) -> Rect2:return Rect2(Vector2([12,88,164,240][index],80)*2,Vector2(128,152))

func choose() -> void:
    if not editing:
        editing=true;name_value=Identity.DEFAULT_NAMES[selected];select_all=false
    else:
        var identity: Dictionary={"kind":selected,"name":name_value.strip_edges()}
        if Identity.valid(identity):confirmed.emit(identity)
    queue_redraw()

func back() -> void:
    if help_visible:help_visible=false
    elif editing:editing=false;select_all=false
    else:cancelled.emit()
    queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
    if not event is InputEventKey or not event.pressed:return
    get_viewport().set_input_as_handled()
    if event.keycode==KEY_F1 and not event.echo:help_visible=not help_visible
    elif help_visible:help_visible=false
    elif event.keycode==KEY_ESCAPE and not event.echo:back()
    elif not editing and event.keycode in [KEY_P,KEY_I] and not event.echo:local_requested.emit()
    elif event.keycode in [KEY_ENTER,KEY_KP_ENTER] and not event.echo:choose()
    elif editing:
        if (event.ctrl_pressed or event.meta_pressed) and event.keycode==KEY_A:select_all=true
        elif event.keycode in [KEY_BACKSPACE,KEY_DELETE]:
            name_value="" if select_all else name_value.left(maxi(0,name_value.length()-1));select_all=false
        elif event.unicode>=32 and event.unicode<=126 and not event.ctrl_pressed and not event.meta_pressed:
            if select_all:name_value="";select_all=false
            if name_value.length()<Identity.NAME_MAX:name_value+=String.chr(event.unicode)
    elif not event.echo:
        if event.keycode in [KEY_SPACE,KEY_Z]:choose()
        elif event.keycode==KEY_LEFT:selected=maxi(0,selected-1)
        elif event.keycode==KEY_RIGHT:selected=mini(3,selected+1)
    queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
    if not event is InputEventMouseButton or not event.pressed or event.button_index!=MOUSE_BUTTON_LEFT:return
    get_viewport().set_input_as_handled()
    if help_visible:help_visible=false
    elif editing:
        if Rect2(420,330,200,50).has_point(event.position):choose()
    else:
        if Rect2(160,332,320,50).has_point(event.position):local_requested.emit();return
        for index in range(4):
            if portrait_rect(index).has_point(event.position):selected=index;choose();break
    queue_redraw()

func _draw() -> void:
    draw_rect(Rect2(0,0,640,400),Color.BLACK)
    ART.draw_text(self,"Select a Knight",Vector2(320,10))
    for index in range(4):draw_texture_rect(ART.portraits[index],portrait_rect(index),false)
    # Source highlight cel; native pulse cadence is provisional.
    draw_texture_rect(ART.highlight,portrait_rect(selected),false,Color(1,1,1,0.65+0.35*absf(sin(float(tick)*PI/40))))
    if editing:
        ART.draw_text(self,name_value+("_" if tick%40<20 else ""),Vector2(100,100),false)
        ART.draw_text(self,"Begin",Vector2(520,340))
    else:ART.draw_text(self,"Local players",Vector2(320,342))
    if help_visible:
        draw_rect(Rect2(30,20,580,360),Color(0.025,0.035,0.05,0.98))
        var lines: Array[String]=["Choose your knight","Left / Right: portrait","Enter / Space / click: choose","Type a name, then Enter or Begin","13 letters / Ctrl+A replaces name","Esc: back / cancel","F1: close help"]
        for i in range(lines.size()):ART.draw_text(self,lines[i],Vector2(320,40+i*42))
