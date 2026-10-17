extends Node2D

signal finished
const ART=preload("res://assets/classic/intro_menu/art.tres")
var tick: int=0
var completed: bool=false
var film: Sprite2D
var region: AtlasTexture
var palette: ShaderMaterial
var help_visible: bool=false
var help_layer: Node2D
var old_mouse_mode: int=Input.MOUSE_MODE_VISIBLE

func _ready() -> void:
    add_to_group("moonstone_input_surfaces")
    old_mouse_mode=Input.mouse_mode;Input.mouse_mode=Input.MOUSE_MODE_HIDDEN
    texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
    film=Sprite2D.new();film.centered=false;film.scale=Vector2(2,2)
    region=AtlasTexture.new();region.atlas=ART.atlas;film.texture=region
    palette=ShaderMaterial.new();palette.shader=preload("res://scripts/presentation/ending_palette.gdshader")
    palette.set_shader_parameter("palette",ART.palette);film.material=palette
    add_child(film);show_tick()
    help_layer=preload("res://scripts/presentation/original_panel_view.gd").new()
    add_child(help_layer)
    help_layer.draw.connect(func():
        if help_visible:
            help_layer.help_visible=true
            help_layer.draw_help("ORIGINAL OPENING\nSPACE / ENTER / Z / ESC / CLICK: SKIP\nF1: CLOSE HELP\nF8: SOUND / F9-F10: VOLUME"))
    var audio: Node=get_node_or_null("/root/MoonstoneAudio")
    if audio!=null:audio.opening_music(0)

func show_tick() -> void:
    var at: int=clampi(tick,0,ART.total_ticks-1)
    var frame: int=ART.pose_at(at).frame
    region.region=Rect2((frame%ART.columns)*320,(frame/ART.columns)*200,320,200)
    palette.set_shader_parameter("row",at)

func advance() -> void:
    if completed:return
    tick+=1
    if tick==ART.music_tick:
        var audio: Node=get_node_or_null("/root/MoonstoneAudio")
        if audio!=null:audio.opening_music(tick)
    if tick>=ART.total_ticks:finish();return
    show_tick()

func finish() -> void:
    if completed:return
    completed=true
    var audio: Node=get_node_or_null("/root/MoonstoneAudio")
    if audio!=null:audio.stop_music()
    finished.emit()

func _unhandled_key_input(event: InputEvent) -> void:
    if not event is InputEventKey or not event.pressed or event.echo:return
    get_viewport().set_input_as_handled()
    if event.keycode in [KEY_SPACE,KEY_ENTER,KEY_KP_ENTER,KEY_ESCAPE,KEY_Z]:finish()
    elif event.keycode==KEY_F1:help_visible=not help_visible;help_layer.queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
    if not event is InputEventMouseButton or not event.pressed:return
    get_viewport().set_input_as_handled()
    if event.button_index==MOUSE_BUTTON_LEFT:finish()

func _exit_tree() -> void:
    Input.mouse_mode=old_mouse_mode
