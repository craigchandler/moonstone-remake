extends "res://scripts/presentation/practice_menu.gd"

signal finished
signal connected
const Connection = preload("res://scripts/session/duel_connection.gd")
var connection: RefCounted
var address: String = "127.0.0.1"
var port_text: String = str(Connection.DEFAULT_PORT)
var editing: String = ""
var edit_before: String = ""
var select_all: bool = false
var observed_state: String = ""

func _ready() -> void:
    super._ready()
    connection=Connection.new(rules)
    connection.changed.connect(connection_changed)
    connection.fight_started.connect(func() -> void: connected.emit())

func connection_changed() -> void:
    if connection.state!=observed_state and connection.state=="waiting":selected=4
    observed_state=connection.state
    queue_redraw()

func _process(_delta: float) -> void:
    connection.poll()

func _exit_tree() -> void:
    if connection!=null:connection.close()
    super._exit_tree()

func actions() -> Array[String]:return ["host","join","address","port","ready","back"]

func action_rect(index: int) -> Rect2:
    return Rect2(66,[90,126,184,242,294,336][index],220,28)

func activate(action: String) -> void:
    if action=="back":finished.emit()
    elif action in ["address","port"]:
        editing=action;edit_before=address if action=="address" else port_text;select_all=true
    elif action=="host":connection.host_game(int(port_text),knight_kind)
    elif action=="join":connection.join_game(address,int(port_text),knight_kind)
    elif action=="ready":connection.ready()
    queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
    if not event is InputEventKey or not event.pressed:return
    get_viewport().set_input_as_handled();mouse_active=false
    if not editing.is_empty():
        if event.keycode in [KEY_ENTER,KEY_KP_ENTER]:editing=""
        elif event.keycode==KEY_ESCAPE:
            if editing=="address":address=edit_before
            else:port_text=edit_before
            editing=""
        elif (event.ctrl_pressed or event.meta_pressed) and event.keycode==KEY_A:select_all=true
        elif event.keycode in [KEY_BACKSPACE,KEY_DELETE]:
            if editing=="address":address="" if select_all else address.left(maxi(0,address.length()-1))
            else:port_text="" if select_all else port_text.left(maxi(0,port_text.length()-1))
            select_all=false
        elif event.unicode>=32 and event.unicode<127 and not event.ctrl_pressed and not event.meta_pressed:
            var character: String=String.chr(event.unicode)
            var allowed: String="0123456789" if editing=="port" else "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.:-_"
            if character in allowed:
                if select_all:
                    if editing=="address":address=""
                    else:port_text=""
                select_all=false
                if editing=="address" and address.length()<100:address+=character
                elif editing=="port" and port_text.length()<5:port_text+=character
    elif event.echo:return
    elif event.keycode==KEY_F1:help_visible=not help_visible
    elif help_visible:help_visible=false
    elif event.keycode==KEY_ESCAPE:finished.emit()
    elif event.keycode in [KEY_UP,KEY_DOWN]:selected=posmod(selected+(1 if event.keycode==KEY_DOWN else -1),actions().size())
    elif event.keycode in [KEY_LEFT,KEY_RIGHT] and connection.peer==null:knight_kind=posmod(knight_kind+(1 if event.keycode==KEY_RIGHT else -1),4)
    elif event.keycode in [KEY_ENTER,KEY_KP_ENTER,KEY_SPACE,KEY_Z]:activate(actions()[selected])
    queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion:mouse_active=true;pointer=event.position;queue_redraw();return
    if not event is InputEventMouseButton or not event.pressed or event.button_index!=MOUSE_BUTTON_LEFT:return
    get_viewport().set_input_as_handled();mouse_active=true;pointer=event.position
    if help_visible:help_visible=false
    elif on_column(pointer,false):finished.emit()
    else:
        for index in range(actions().size()):
            if action_rect(index).has_point(pointer):
                selected=index;editing="";activate(actions()[index]);break
    queue_redraw()

func addresses() -> Array[String]:
    var values: Array[String]=[]
    for value in IP.get_local_addresses():
        if value.contains(".") and not value.begins_with("127.") and not value.begins_with("169.254."):values.append(value)
    values.sort_custom(func(a: String,b: String) -> bool:return (0 if a.begins_with("192.168.") else 1)<(0 if b.begins_with("192.168.") else 1))
    return values

func short_lines(text: String, y: int) -> void:
    var line: String=""
    for word in text.split(" "):
        if (line+" "+word).length()>23:pixel_text(line,Vector2(470,y),true);y+=16;line=""
        line=word if line.is_empty() else line+" "+word
    pixel_text(line,Vector2(470,y),true)

func _draw() -> void:
    if connection==null:return
    draw_classic_background()
    var gold:=Color("ddc68c")
    pixel_text("NETWORK DUEL",Vector2(320,8),true,gold)
    pixel_text("CONNECTION",Vector2(174,60),true,gold)
    pixel_text("KNIGHTS",Vector2(470,60),true,gold)
    var own: int=knight_kind if connection.peer==null else connection.colours[connection.local_actor-1]
    var other: int=(own+1)%4 if connection.peer==null else connection.colours[2-connection.local_actor]
    draw_preview("knight",Vector2(414,220),own,"blue")
    draw_preview("knight",Vector2(526,220),other,"blue",-1)
    pixel_text("YOU",Vector2(414,234),true,gold);pixel_text("RIVAL",Vector2(526,234),true,gold)
    var labels: Array[String]=["HOST DUEL","JOIN DUEL",address.right(22).to_upper(),port_text,"READY" if not connection.local_ready else "WAITING","BACK"]
    pixel_text("HOST ADDRESS",Vector2(174,168),true,gold)
    pixel_text("PORT",Vector2(174,226),true,gold)
    for index in range(actions().size()):
        var rect: Rect2=action_rect(index)
        pixel_text(labels[index]+("!" if editing==actions()[index] else ""),rect.position+Vector2(110,8),true,gold if selected==index else Color.WHITE)
    short_lines(connection.notice,268)
    if connection.authority and connection.state in ["hosting","seated"]:
        var ips: Array[String]=addresses()
        pixel_text("YOUR ADDRESS",Vector2(470,312),true,gold)
        pixel_text(ips[0] if not ips.is_empty() else "127.0.0.1",Vector2(470,330),true)
    elif connection.state=="waiting":
        pixel_text("YOU "+("READY" if connection.local_ready else "WAIT"),Vector2(470,314),true,gold)
        pixel_text("RIVAL "+("READY" if connection.remote_ready else "WAIT"),Vector2(470,332),true,gold)
    draw_pointer(action_rect(selected).position+Vector2(10,14))
    pixel_text("SAME NETWORK",Vector2(174,372),true,gold)
    pixel_text("ESC BACK / F1 HELP",Vector2(470,372),true,gold)
    pixel_text("LEFT / RIGHT KNIGHT",Vector2(174,388),true)
    pixel_text("ENTER CHOOSE",Vector2(470,388),true)
    draw_help("ONE PLAYER HOSTS OR USE A COMMAND LINE HOST\nDEDICATED HOST: BOTH PLAYERS JOIN\nOTHER PLAYER ENTERS THE HOST ADDRESS AND PORT\nBOTH PLAYERS CHOOSE READY TO BEGIN\nUP / DOWN SELECTS / ENTER CHOOSES\nLEFT / RIGHT CHANGES KNIGHT BEFORE CONNECTING\nSELECT ADDRESS OR PORT TO TYPE / CTRL+A REPLACES\nBOTH PLAYERS MUST USE MATCHING GAME BUILDS\nA DISCONNECT ENDS THE DUEL\nLOCAL MENUS DO NOT PAUSE A NETWORK DUEL", "ONE PLAYER HOSTS / OTHER PLAYER JOINS\nDEDICATED HOST: BOTH PLAYERS JOIN\nUSE A KEYBOARD TO ENTER ADDRESS AND PORT\nSTICK / D-PAD SELECTS / CONFIRM CHOOSES\nBOTH PLAYERS CHOOSE READY TO BEGIN\nSTART OPENS CONTROLLER SETUP DURING THE DUEL\nLOCAL MENUS DO NOT PAUSE A NETWORK DUEL")
