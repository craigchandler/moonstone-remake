extends "res://scripts/presentation/network_duel_menu.gd"
const CampaignConnection=preload("res://scripts/session/campaign_connection.gd")
var human_count: int=2
func input_kind() -> String:return "network_duel_menu"
func _ready() -> void:
    super._ready()
    connection.close()
    connection=CampaignConnection.new()
    port_text=str(CampaignConnection.DEFAULT_PORT)
    connection.changed.connect(connection_changed)
    connection.fight_started.connect(func() -> void:connected.emit())
func connection_changed() -> void:
    if connection.state!=observed_state and connection.state in ["lobby","paused"]:selected=6
    observed_state=connection.state
    queue_redraw()
func actions() -> Array[String]:return ["host","resume","join","address","port","players","ready","back"]
func action_rect(index: int) -> Rect2:return Rect2(66,[78,112,146,190,232,266,302,338][index],220,26)
func activate(action: String) -> void:
    if action=="back":finished.emit()
    elif action in ["address","port"]:editing=action;edit_before=address if action=="address" else port_text;select_all=true
    elif action=="host":connection.host_game(int(port_text),knight_kind,human_count)
    elif action=="resume":connection.host_game(int(port_text),knight_kind,human_count,true)
    elif action=="join":connection.join_game(address,int(port_text),knight_kind)
    elif action=="players" and connection.peer==null:human_count=1+human_count%4
    elif action=="ready":connection.ready()
    queue_redraw()
func draw_knight_preview(point: Vector2,colour: int,facing: int) -> void:
    var parts: Array[Dictionary]=preview_parts("knight")
    var bounds: Rect2=preview_bounds(parts)
    var scale: float=minf(1.5,76.0/bounds.size.y)
    var origin: Vector2=-Vector2(bounds.get_center().x,bounds.end.y)
    draw_set_transform(point,0.0,Vector2(facing,1))
    for part in parts:creature_renderer.draw_pose(self,part.animation,part.pose,"blue",false,colour,origin+part.point,scale)
    draw_set_transform(Vector2.ZERO)
func _draw() -> void:
    if connection==null:return
    draw_classic_background()
    var gold:=Color("ddc68c")
    pixel_text("NETWORK JOURNEY",Vector2(320,8),true,gold)
    pixel_text("CONNECTION",Vector2(174,56),true,gold)
    pixel_text("FOUR KNIGHTS",Vector2(470,56),true,gold)
    var labels: Array[String]=["HOST NEW JOURNEY","RESUME HOSTED GAME","JOIN JOURNEY",address.right(22).to_upper(),port_text,"HUMANS: "+str(connection.roster.get("count",human_count)),"READY / RESUME","BACK"]
    pixel_text("HOST ADDRESS",Vector2(174,178),true,gold);pixel_text("PORT",Vector2(174,220),true,gold)
    for index in range(actions().size()):
        var rect: Rect2=action_rect(index)
        pixel_text(labels[index]+("!" if editing==actions()[index] else ""),rect.position+Vector2(110,8),true,gold if selected==index else Color.WHITE)
    for seat in range(4):
        var point:=Vector2(410+(seat%2)*118,166+(seat/2)*114)
        draw_knight_preview(point,seat,1 if seat%2==0 else -1)
        var row: Dictionary=connection.roster.get("seats",[{},{},{},{}])[seat]
        var state: String="READY" if row.get("ready",false) else "JOINED" if row.get("connected",false) else "RESERVED" if row.get("reserved",false) else "OPEN"
        pixel_text(Identity.COLOURS[seat].to_upper()+ (" / YOU" if connection.seat==seat else ""),point+Vector2(0,8),true,gold)
        pixel_text(state,point+Vector2(0,24),true,Color.WHITE)
    short_lines(connection.notice if not connection.notice.is_empty() else "ALL HUMANS READY TO START",322)
    if connection.host_runtime!=null:
        var local_addresses: Array[String]=addresses()
        if not local_addresses.is_empty():pixel_text("HOST: "+local_addresses[0],Vector2(470,362),true,gold)
    draw_pointer(action_rect(selected).position+Vector2(10,14))
    pixel_text("LEFT / RIGHT KNIGHT",Vector2(174,382),true,gold)
    pixel_text("ESC BACK / F1 HELP",Vector2(470,382),true,gold)
    draw_help("HOST NEW OR JOIN A STANDALONE CAMPAIGN SERVER\nUP TO FOUR HUMAN KNIGHTS / REST ARE COMPUTER\nHUMANS FIELD SETS HOW MANY MUST JOIN A NEW HOST\nALL PLAYERS CHOOSE READY TO START OR RESUME\nCLASSIC TURNS / WATCH OTHERS AND BROWSE YOUR PACK\nDISCONNECT PAUSES AND RESERVES YOUR KNIGHT\nRESUME HOSTED GAME LOADS YOUR LAST HOSTED SAVE\nPORT27867 IS THE CAMPAIGN DEFAULT\nREJOIN THE SAME ADDRESS TO RECLAIM YOUR KNIGHT\nMATCHING CAMPAIGN BUILDS ARE REQUIRED")
