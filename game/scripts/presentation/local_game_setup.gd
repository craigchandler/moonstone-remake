extends "res://scripts/presentation/original_panel_view.gd"

signal confirmed(players: Array)
signal cancelled
const Party=preload("res://scripts/session/local_party.gd")
const Identity=preload("res://scripts/domain/knight_identity.gd")
const KnightArt=preload("res://assets/classic/knight_selection/art.tres")
var players: Array=Party.defaults()
var selected: int=0
var field: int=0 # name, human/AI, logical controller port
var editing: bool=false
var select_all: bool=false
var notice: String=""

func row_rect(index: int) -> Rect2:
    return Rect2(24,52+index*64,592,60) if index<4 else Rect2(150,318+(index-4)*32,340,28)

func field_rect(index: int,column: int) -> Rect2:
    return Rect2([88,250,410][column],row_rect(index).position.y+8,[150,150,195][column],36)

func activate() -> void:
    if selected==5:cancelled.emit();return
    if selected==4:
        if Party.valid_players(players,preload("res://scripts/domain/journey_archive.gd").integer):confirmed.emit(players.duplicate(true))
        else:notice="Choose a human knight; give each controller its own port."
    elif field==0:editing=true;select_all=true
    elif field==1:players[selected].human=not players[selected].human
    else:players[selected].input=(int(players[selected].input)+1)%5
    queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
    if not event is InputEventKey or not event.pressed:return
    get_viewport().set_input_as_handled();mouse_active=false
    if editing:
        if event.keycode in [KEY_ENTER,KEY_KP_ENTER,KEY_ESCAPE]:editing=false
        elif (event.ctrl_pressed or event.meta_pressed) and event.keycode==KEY_A:select_all=true
        elif event.keycode in [KEY_BACKSPACE,KEY_DELETE]:
            players[selected].identity.name="" if select_all else String(players[selected].identity.name).left(maxi(0,String(players[selected].identity.name).length()-1));select_all=false
        elif event.unicode>=32 and event.unicode<=126 and not event.ctrl_pressed and not event.meta_pressed:
            if select_all:players[selected].identity.name="";select_all=false
            if String(players[selected].identity.name).length()<Identity.NAME_MAX:players[selected].identity.name+=String.chr(event.unicode)
    elif not event.echo:
        if event.keycode==KEY_F1:help_visible=not help_visible
        elif help_visible:help_visible=false
        elif event.keycode==KEY_ESCAPE:cancelled.emit()
        elif event.keycode in [KEY_UP,KEY_DOWN]:selected=posmod(selected+(1 if event.keycode==KEY_DOWN else -1),6)
        elif event.keycode in [KEY_LEFT,KEY_RIGHT]:field=posmod(field+(1 if event.keycode==KEY_RIGHT else -1),3)
        elif event.keycode in [KEY_ENTER,KEY_KP_ENTER,KEY_SPACE,KEY_Z]:activate()
    queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion:mouse_active=true;pointer=event.position;queue_redraw();return
    if not event is InputEventMouseButton or not event.pressed or event.button_index!=MOUSE_BUTTON_LEFT:return
    get_viewport().set_input_as_handled();mouse_active=true;pointer=event.position
    if help_visible:help_visible=false;queue_redraw();return
    if editing:editing=false;queue_redraw();return
    for index in range(6):
        if not row_rect(index).has_point(pointer):continue
        selected=index
        if index<4:
            for column in range(3):
                if field_rect(index,column).has_point(pointer):field=column;activate();return
        else:activate();return

func _draw() -> void:
    draw_texture_rect(preload("res://assets/classic/intro_menu/art.tres").background,Rect2(0,0,640,400),false)
    draw_rect(Rect2(14,6,612,388),Color(0.02,0.025,0.035,0.96))
    pixel_text("LOCAL MULTIPLAYER",Vector2(320,14),true,Color("ddc68c"))
    pixel_text("NAME             PLAYER          CONTROLS",Vector2(88,36),false,Color("aaaeb8"))
    for index in range(4):
        var row: Dictionary=players[index]
        draw_texture_rect(KnightArt.portraits[index],Rect2(28,row_rect(index).position.y,48,57),false)
        if selected==index:draw_rect(field_rect(index,field),Color(0.22,0.19,0.09,0.9))
        pixel_text(row.identity.name+("_" if editing and selected==index else ""),Vector2(94,row_rect(index).position.y+16))
        pixel_text("HUMAN" if row.human else "COMPUTER",Vector2(256,row_rect(index).position.y+16))
        pixel_text(("KEYBOARD" if row.input==0 else "CONTROLLER "+str(row.input)) if row.human else "AUTO",Vector2(416,row_rect(index).position.y+16))
    for index in [4,5]:
        if selected==index:draw_rect(row_rect(index),Color(0.22,0.19,0.09,0.9))
        pixel_text("START GAME" if index==4 else "BACK",Vector2(320,row_rect(index).position.y+4),true)
    if not notice.is_empty():pixel_text(notice.left(60).to_upper(),Vector2(320,378),true,Color("ddc68c"))
    draw_help("LOCAL MULTIPLAYER\nUP / DOWN: KNIGHT OR START\nLEFT / RIGHT: NAME, PLAYER, CONTROLS\nSPACE / CLICK: EDIT OR CHANGE\nCONTROLLER PORTS FOLLOW CONNECTED ORDER\nONE CONTROLLER PORT PER HUMAN\nMISSING CONTROLLER: KEYBOARD FALLBACK\nMAP TURNS SHARE THE NORMAL KEYS\nDUEL DEFENDER USES THE NUMBER PAD\nF1: CLOSE HELP")
    draw_pointer(row_rect(selected).get_center() if selected>=4 else field_rect(selected,field).get_center())
