extends "res://scripts/presentation/original_panel_view.gd"

signal chosen(action: String)
var journey: RefCounted
var picture: Texture2D=preload("res://assets/classic/recovered/A/message.piv/image.png")
var ending_view: Node2D

func _ready() -> void:
    super._ready()
    ending_view=preload("res://scripts/presentation/ending_view.gd").new()
    ending_view.show_behind_parent=true
    add_child(ending_view)
    sync_ending()

func sync_ending() -> void:
    if not is_inside_tree() or not is_instance_valid(ending_view):return
    var playing: bool=journey.quest.ending.get("stage","")=="ready"
    var complete: bool=journey.quest.ending.get("stage","")=="complete"
    ending_view.visible=playing or complete
    var audio: Node=get_node_or_null("/root/MoonstoneAudio")
    if playing:
        ending_view.show_tick(journey.quest.ending.tick,journey.quest.ending.code)
        if audio!=null:audio.ending_music(journey.quest.ending.tick)
    else:
        if complete:ending_view.show_tick(ending_view.ART.total_ticks-62,journey.quest.ending.code)
        if audio!=null:audio.stop_music()

func _exit_tree() -> void:
    var audio: Node=get_node_or_null("/root/MoonstoneAudio")
    if audio!=null:audio.stop_music()
    super._exit_tree()

func advance() -> void:
    var was_playing: bool=journey.quest.ending.get("stage","")=="ready"
    if journey.quest.ending.get("stage","")=="ready":journey.tick_ending()
    else:journey.tick_quest()
    sync_ending()
    queue_redraw()
    if was_playing and journey.quest.ending.get("stage","")=="complete":chosen.emit("menu")

func activate() -> void:
    if journey.quest.notice:
        journey.acknowledge_moonstone()
        chosen.emit("reward")
    elif journey.quest.ending.get("stage","")=="message":journey.enter_ending()
    elif journey.quest.ending.get("stage","")=="ready":
        journey.finish_ending()
        chosen.emit("menu")
    elif journey.quest.ending.get("stage","")=="complete":chosen.emit("menu")
    sync_ending()
    queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
    if not event is InputEventKey or not event.pressed or event.echo:return
    get_viewport().set_input_as_handled()
    if event.keycode==KEY_F1:help_visible=not help_visible
    elif help_visible:help_visible=false
    elif event.keycode in [KEY_SPACE,KEY_ENTER,KEY_KP_ENTER,KEY_Z,KEY_ESCAPE]:activate()
    queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion:
        mouse_active=true;pointer=event.position;queue_redraw();return
    if not event is InputEventMouseButton or not event.pressed or event.button_index!=MOUSE_BUTTON_LEFT:return
    get_viewport().set_input_as_handled()
    if help_visible:help_visible=false;queue_redraw();return
    if journey.quest.ending.get("stage","")=="ready":return
    activate()

func _draw() -> void:
    if journey==null:return
    if journey.quest.ending.get("stage","")=="ready":
        if journey.quest.ending.tick<36:
            var fading:=Color(1,1,1,1.0-float(journey.quest.ending.tick)/36.0)
            draw_texture_rect(picture,Rect2(0,0,640,400),false,fading)
            for line in MOONSTONES.victory_message:pixel_text(line.text,Vector2(320,line.y*2),true,fading)
        # Help is outside the film's palette shader and has no clock effect.
        draw_help("ENDING\nSPACE / ENTER / Z / ESC: SKIP TO MENU\nF8: SOUND ON / OFF\nF9 / F10: SOUND VOLUME\nCLOSE AND CONTINUE: RESUME THIS POINT")
        return
    if journey.quest.ending.get("stage","")=="complete":
        draw_help("THE QUEST IS COMPLETE\nSPACE / ENTER / ESC / CLICK: MENU\nNEW JOURNEY STARTS A NEW CAMPAIGN")
        return
    else:
        draw_texture_rect(picture,Rect2(0,0,640,400),false)
        var lines: Array=MOONSTONES.guardian_message if journey.quest.notice else MOONSTONES.victory_message
        for line in lines:pixel_text(line.text,Vector2(320,line.y*2),true)
        if not journey.quest.notice and int(journey.quest.ending.get("tick",0))>=20:pixel_text("Press fire to continue",Vector2(320,364),true)
    draw_help("MOONSTONE QUEST\nSPACE / ENTER / CLICK: CONTINUE\nTHE GUARDIAN GRANTS ONE STONE DIRECTLY\nMOONSTONES WORK WHILE CARRIED\nSTONEHENGE REQUIRES A MATCHING MOON\nVICTORY COLUMN / SPACE: RETURN TO MENU")
