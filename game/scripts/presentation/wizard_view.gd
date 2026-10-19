extends "res://scripts/presentation/original_panel_view.gd"
signal finished
const Places=preload("res://scripts/domain/town_locations.gd")
const Scenes=preload("res://assets/classic/town_locations/art.tres")
const KnightArt=preload("res://assets/classic/knight_selection/art.tres")
var journey: RefCounted
var service_screen: RefCounted
var last_phase: String=""
var audio: Node
func _ready() -> void:
    super._ready();audio=get_node_or_null("/root/MoonstoneAudio");sync_audio()
func _exit_tree() -> void:
    if is_instance_valid(audio):audio.stop_scope("town:wizard:",false)
    super._exit_tree()
func sync_audio() -> void:
    var phase: String=journey.places.visit.phase
    if phase==last_phase:return
    if audio!=null:
        audio.stop_scope("town:wizard:",false)
        if phase=="greeting":
            for seq in range(128,132):audio.play_cue("town_%03d"%seq,"town:wizard:greeting",journey.places.visit.tick)
    last_phase=phase
func advance_visit() -> void:
    if help_visible:return
    journey.places.visit.tick=mini(1000000,int(journey.places.visit.tick)+1)
    if journey.places.visit.tick%50==0:journey.persist()
    sync_audio();queue_redraw()
func activate() -> void:
    if help_visible:help_visible=false;queue_redraw();return
    if Places.advance_wizard(journey):
        if journey.places.visit.phase=="sheet":finished.emit()
        else:sync_audio();queue_redraw()
func _unhandled_key_input(event: InputEvent) -> void:
    if not event is InputEventKey or not event.pressed or event.echo:return
    get_viewport().set_input_as_handled()
    if event.keycode==KEY_F1:help_visible=not help_visible;queue_redraw()
    elif event.keycode in [KEY_ESCAPE,KEY_I,KEY_ENTER,KEY_KP_ENTER,KEY_SPACE,KEY_Z]:activate()
func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:get_viewport().set_input_as_handled();activate()
func draw_track(key: String,tick: int) -> void:
    var track: Array=Scenes.data[key];var length: int=0
    for pose in track:length+=int(pose.ticks)
    var remaining: int=posmod(tick,length)
    for pose in track:
        if remaining<int(pose.ticks):
            for layer in pose.layers:
                var texture: Texture2D=KnightArt.coloured(Scenes.frames["wizard_"+str(layer.frame)],journey.identity.kind)
                draw_texture_rect(texture,Rect2(Vector2(layer.x,layer.y)*2,Images.size(texture)*2),false)
            return
        remaining-=int(pose.ticks)
func _draw() -> void:
    if journey==null or journey.places.visit.is_empty():return
    var v: Dictionary=journey.places.visit
    var gift: bool=v.phase=="gift"
    draw_texture_rect(KnightArt.coloured(Scenes.pictures["gift" if gift else "tower"],journey.identity.kind),Rect2(0,0,640,400),false)
    draw_track("gift_a" if gift else "tower",v.tick)
    if gift:
        draw_track("gift_b",v.tick)
        var lines: Array=Scenes.data[v.result+"_replies"][int(v.row)] if v.result in ["item","stat","gold"] else Scenes.data.curse
        for i in range(lines.size()):pixel_text(lines[i],Vector2(320,260+i*20),true)
    else:
        var key: String="intro" if v.phase=="greeting" else {"item":"item_speech","stat":"stat_speech","gold":"gold_speech","frog":"toad_speech"}.get(v.result,"omen_speech")
        var lines: Array=Scenes.data[key]
        for i in range(lines.size()):
            var line: String=lines[i]
            if v.phase=="omen" and v.result=="item" and line.strip_edges().is_empty():line=journey.loot_rules.items[v.subject].name
            if v.phase=="omen" and v.result=="gold" and line.begins_with("filled with"):line="filled with %d gold."%v.amount
            pixel_text(line,Vector2(300,10+i*20))
    draw_help("SPACE / ENTER / CLICK: CONTINUE\nESC / I: ADVANCE THE CURRENT SCENE\nGIFTS ARE APPLIED ONLY ONCE\nTHE CHARACTER SHEET FOLLOWS\nLEAVING THE TOWER SPENDS YOUR TURN")
