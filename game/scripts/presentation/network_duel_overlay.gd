extends "res://scripts/presentation/original_panel_view.gd"

var arena: Node2D

func _ready() -> void:
    old_mouse_mode=Input.mouse_mode;texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST

func _draw() -> void:
    var link: RefCounted=arena.network_duel
    var model: RefCounted=arena.session.simulation
    if model.actors.is_empty():return
    var gold:=Color("ddc68c")
    draw_rect(Rect2(0,0,640,34),Color.BLACK)
    for id in [1,2]:
        var actor: Dictionary=model.actors[id]
        var label: String="YOU" if id==link.local_actor else "RIVAL"
        pixel_text(label+" %d/%d" % [actor.health,actor.maximum],Vector2(12+(id-1)*328,3),false,gold)
        pixel_text("DAGGERS "+str(actor.daggers),Vector2(12+(id-1)*328,20))
    draw_rect(Rect2(0,360,640,40),Color.BLACK)
    var controls: Node=get_node("/root/MoonstoneInput")
    pixel_text("NETWORK DUEL / ROUND "+str(link.session.round_id),Vector2(320,366),true,gold)
    pixel_text((controls.binding_name("retreat").to_upper()+" LEAVE / "+controls.pause_name().to_upper()+" CONTROLS") if controls.using_controller else "ESC LEAVE / F1 CONTROLS",Vector2(320,384),true)
    if link.state=="closed" or link.session.settled:
        draw_rect(Rect2(94,68,452,96),Color.BLACK)
        draw_rect(Rect2(94,68,452,96),gold,false,2)
        var outcome: String=model.outcome()
        var label: String="DRAW" if outcome=="draw" else ("YOU WON" if (outcome=="victory")== (link.local_actor==1) else "YOU LOST")
        pixel_text("DUEL ENDED" if link.state=="closed" else label,Vector2(320,82),true,gold)
        pixel_text(link.notice if link.state=="closed" else ("WAITING FOR REMATCH" if link.local_ready else "ENTER REQUEST REMATCH"),Vector2(320,108),true)
        pixel_text("ENTER / ESC BACK" if link.state=="closed" else "BOTH MUST AGREE / ESC LEAVE",Vector2(320,140),true)
    draw_help("ARROWS MOVE / Z SWING / X OVERHEAD / C LUNGE\nV REVERSE / A UPWARD / D DAGGER / SPACE GUARD\nESC LEAVES THE DUEL\nAFTER THE ROUND ENTER REQUESTS A REMATCH\nBOTH PLAYERS MUST AGREE TO A REMATCH\nTHE DUEL CONTINUES WHILE LOCAL MENUS ARE OPEN\nF1 CLOSES CONTROLS", "STICK / D-PAD MOVE\n"+controls.binding_name("swing")+" SWING / "+controls.binding_name("heavy")+" OVERHEAD\n"+controls.binding_name("lunge")+" LUNGE / "+controls.binding_name("reverse")+" REVERSE\n"+controls.binding_name("upward")+" UPWARD / "+controls.binding_name("dagger")+" DAGGER\n"+controls.binding_name("block")+" GUARD / "+controls.binding_name("retreat")+" LEAVE\nCONFIRM REQUESTS REMATCH AFTER THE ROUND\nLOCAL MENUS DO NOT PAUSE THE DUEL")
