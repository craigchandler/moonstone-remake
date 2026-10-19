extends "res://scripts/presentation/original_panel_view.gd"

const Practice = preload("res://scripts/session/practice_session.gd")
var arena: Node2D

func _ready() -> void:
    # The combat surface retains input ownership and the normal pointer mode.
    old_mouse_mode = Input.mouse_mode
    texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func result_label() -> String:
    return {"victory":"PRACTICE WON","defeat":"PRACTICE LOST","draw":"PRACTICE DRAW"}.get(arena.session.simulation.outcome(),"")

func _draw() -> void:
    if arena == null or arena.session == null: return
    var model: RefCounted = arena.session.simulation
    var player: Dictionary = model.actors[1]
    var foes: int = model.spawn_remaining
    for actor in model.actors.values():
        if actor.team == 2 and actor.health > 0: foes += 1
    var gold := Color("ddc68c")
    draw_rect(Rect2(0,0,640,34),Color.BLACK)
    pixel_text("PRACTICE",Vector2(12,3),false,gold)
    pixel_text(Practice.LABELS[String(arena.encounter)],Vector2(454,3),true,gold)
    pixel_text("HEALTH %d/%d   DAGGERS %d   FOES %d" % [player.health,player.maximum,player.daggers,foes],Vector2(12,20))
    draw_rect(Rect2(0,360,640,40),Color.BLACK)
    var controls: Node = get_node("/root/MoonstoneInput")
    if controls.using_controller:
        pixel_text("STICK MOVE   %s SWING   %s CHOP   %s LUNGE" % [controls.binding_name("swing"),controls.binding_name("heavy"),controls.binding_name("lunge")],Vector2(320,366),true)
        pixel_text("%s OPPONENTS   START PAUSE / CONTROLS" % controls.binding_name("retreat").to_upper(),Vector2(320,384),true,gold)
    else:
        pixel_text("ARROWS MOVE   Z SWING   X CHOP   C LUNGE",Vector2(320,366),true)
        pixel_text("R RETRY   ESC OPPONENTS   F1 HELP",Vector2(320,384),true,gold)
    if model.outcome() != "ongoing":
        draw_rect(Rect2(114,62,412,82),Color.BLACK)
        draw_rect(Rect2(114,62,412,82),gold,false,2)
        pixel_text(result_label(),Vector2(320,76),true,gold)
        pixel_text(((controls.binding_name("accept").to_upper()+" RETRY") if controls.using_controller else "ENTER RETRY") if arena.practice_finished() else "R RETRY",Vector2(320,102),true)
        pixel_text((controls.binding_name("retreat").to_upper() if controls.using_controller else "ESC")+" CHOOSE OPPONENT",Vector2(320,124),true)
    draw_help("ARROWS: MOVE / EVADE\nZ SWING / X OVERHEAD / C LUNGE\nV REVERSE / A UPWARD / D DAGGER\nSPACE: GUARD / GUARD + DOWN: ESCAPE HOLD\nR: RETRY WITH FRESH HEALTH AND DAGGERS\nESC: CHOOSE ANOTHER OPPONENT\nG: GORE / F8: SOUND / F9-F10: VOLUME\nF1: RESUME PRACTICE", "STICK / D-PAD: MOVE / EVADE\nSTART: PAUSE / CONTROLLER SETUP\n"+controls.binding_name("swing")+": SWING / "+controls.binding_name("heavy")+": OVERHEAD\n"+controls.binding_name("lunge")+": LUNGE / "+controls.binding_name("reverse")+": REVERSE\n"+controls.binding_name("upward")+": UPWARD / "+controls.binding_name("dagger")+": DAGGER\n"+controls.binding_name("block")+": GUARD / GUARD + DOWN: ESCAPE\n"+controls.binding_name("retreat")+": CHOOSE ANOTHER OPPONENT\nF1: RESUME PRACTICE")
