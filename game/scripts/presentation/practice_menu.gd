extends "res://scripts/presentation/classic_panel_view.gd"

signal chosen(encounter: StringName)
var rules: Resource = preload("res://content/foundation_rules.tres")
var creature_art: Resource = preload("res://content/classic_art.tres")
var choices: Array[String] = ["duel","spear_lair","axe_lair","hammer_lair","beast_lair","rat_lair","mud_lair","troll_lair","balok_lair","dragon_fight","guardian_fight","black_knight_fight"]
var selected: int = 0

func row_rect(index: int) -> Rect2:
    return Rect2(50+(index/6)*278,60+(index%6)*49,264,46)

func _unhandled_key_input(event: InputEvent) -> void:
    if not event is InputEventKey or not event.pressed: return
    get_viewport().set_input_as_handled()
    if event.keycode==KEY_ESCAPE: chosen.emit(&"")
    elif event.keycode==KEY_UP: selected=posmod(selected-1,choices.size())
    elif event.keycode==KEY_DOWN: selected=(selected+1)%choices.size()
    elif event.keycode in [KEY_LEFT,KEY_RIGHT]: selected=(selected+6)%choices.size()
    elif event.keycode in [KEY_ENTER,KEY_SPACE]: chosen.emit(StringName(choices[selected]))
    queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
    if not event is InputEventMouseButton or not event.pressed or event.button_index!=MOUSE_BUTTON_LEFT: return
    for i in range(choices.size()):
        if row_rect(i).has_point(event.position):
            get_viewport().set_input_as_handled()
            chosen.emit(StringName(choices[i]))
            return

func _draw() -> void:
    draw_classic_background()
    var gold:=Color("ddc68c")
    draw_string(font,Vector2(0,30),"PRACTISE A FIGHT",HORIZONTAL_ALIGNMENT_CENTER,640,22,gold)
    for i in range(choices.size()):
        var rect: Rect2=row_rect(i)
        draw_rect(rect,Color("303329") if selected==i else Color("101613"))
        if selected==i: draw_rect(rect,gold,false)
        var encounter: Dictionary=rules.encounters.get(choices[i],{})
        var kind: String=encounter.get("creature","knight")
        var animations: Resource=creature_art.animation_for(kind)
        if animations!=null:
            var pose: Dictionary=animations.sample("idle",0)
            var scale: float=minf(0.65,42.0/pose.region.size.y)
            draw_texture_rect_region(animations.atlas_for("purple_clean"),Rect2(rect.position+Vector2(31,42)+pose.offset*scale,pose.region.size*scale),pose.region)
        draw_string(font,rect.position+Vector2(64,28),encounter.get("enemy_label","Knight duel"),HORIZONTAL_ALIGNMENT_LEFT,-1,14,gold)
    draw_string(font,Vector2(0,381),"Arrows select / Enter or click starts / Esc returns",HORIZONTAL_ALIGNMENT_CENTER,640,12,gold)
    draw_string(font,Vector2(0,396),"Practice keeps journey equipment, treasure and experience unchanged.",HORIZONTAL_ALIGNMENT_CENTER,640,10,Color("b8c0b1"))
