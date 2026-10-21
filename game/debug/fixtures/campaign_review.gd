extends RefCounted
# Explicit debug fixture drives the ordinary campaign menu/client controls.
# No debug command is exposed by the network host.
var world: Node
var link: RefCounted
var failures: Array[String]=[]
var checks: int=0
var captures: String=""
var captured: Dictionary={}
var seen: Dictionary={}
var role: int=0
var output: String=""
var shared: String=""
var stage: int=0
var next_action: int=0
var dropped: bool=false
var resumed: bool=false
var paused_tick: int=-1
var paused_frames: int=0
var last_trace: String=""
func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failures.append(label)
func press(code: int) -> void:
    var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=true
    world.get_viewport().push_input(event,true);event=event.duplicate();event.pressed=false;world.get_viewport().push_input(event,true)
func capture(label: String) -> void:
    if captures.is_empty() or captured.has(label) or DisplayServer.get_name()=="headless":return
    captured[label]=true;DirAccess.make_dir_recursive_absolute(captures)
    await world.get_tree().process_frame
    RenderingServer.force_draw()
    check(world.get_viewport().get_texture().get_image().save_png(captures+"/"+label+".png")==OK,"capture "+label)
func mark(label: String) -> void:
    var file:=FileAccess.open(shared+"/"+label,FileAccess.WRITE);file.store_string("ok");file.close()
func exists(label: String) -> bool:return FileAccess.file_exists(shared+"/"+label)
func action(name: String,args: Dictionary={}) -> void:
    if Time.get_ticks_msec()<next_action:return
    next_action=Time.get_ticks_msec()+400;link.command(name,args)
func report(parent: Node) -> void:
    var port: int=27867;var dedicated: bool=false;var address: String="127.0.0.1"
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--campaign-role="):role=int(arg.get_slice("=",1))
        elif arg.begins_with("--campaign-port="):port=int(arg.get_slice("=",1))
        elif arg.begins_with("--campaign-result="):output=arg.trim_prefix("--campaign-result=")
        elif arg.begins_with("--campaign-shared="):shared=arg.trim_prefix("--campaign-shared=")
        elif arg.begins_with("--campaign-capture="):captures=arg.trim_prefix("--campaign-capture=")
        elif arg.begins_with("--campaign-address="):address=arg.get_slice("=",1)
        elif arg=="--campaign-dedicated":dedicated=true
    if output.is_empty() or shared.is_empty() or role not in [0,1]:parent.get_tree().quit(2);return
    world=load("res://scenes/main.tscn").instantiate();world.debug_mode=false;world.parse_launch_arguments=false;world.saving_enabled=false;parent.add_child(world)
    world.show_menu({});world.menu_view.activate("network")
    check(world.campaign_lobby!=null,"ordinary title opens network campaign menu")
    var lobby: Node=world.campaign_lobby
    lobby.knight_kind=role;lobby.port_text=str(port);lobby.address=address;lobby.human_count=2
    await capture("campaign-lobby")
    lobby.activate("host" if role==0 and not dedicated else "join");link=lobby.connection;link.profile_path=""
    var controls: Node=parent.get_node("/root/MoonstoneInput")
    var deadline: int=Time.get_ticks_msec()+110000
    while Time.get_ticks_msec()<deadline:
        await parent.get_tree().physics_frame
        controls.focused=true;controls.refresh_context();controls.blocked.clear();controls.buttons.clear()
        if link.state in ["lobby","paused"] and Time.get_ticks_msec()>=next_action:
            next_action=Time.get_ticks_msec()+400;link.ready()
        if role==1 and exists("complete"):mark("guest-complete");break
        if not link.view_received:continue
        var j: RefCounted=link.replica
        var trace: String=link.state+":"+link.phase+":"+str(j.party.active)+":"+j.service+":"+str(stage)
        if trace!=last_trace:print("CAMPAIGN_PROGRESS role=",role," state=",trace," position=",j.world.position," tick=",link.latest_tick);last_trace=trace
        seen[link.phase]=true
        if world.campaign_view==null:check(false,"normal lobby transitions to campaign view");break
        var remote: Node=world.campaign_view
        if link.state!="playing":
            if dropped or exists("dropped"):
                if link.state=="paused":
                    if paused_tick<0:paused_tick=link.latest_tick
                    else:check(link.latest_tick==paused_tick,"paused campaign tick stays frozen");paused_frames+=1
                await capture("campaign-paused")
            continue
        if exists("dropped") and paused_tick>=0:resumed=true
        if role==1:
            if remote.personal_pack==null and (link.phase=="battle" or not seen.has("pack")):
                press(KEY_I);seen.pack=true;check(remote.personal_pack!=null,"waiting player opens their own inventory")
                check(remote.personal_pack.journey.identity.kind==role,"spectator inventory belongs to its own knight")
                await capture("spectator-inventory")
            if link.phase=="battle" and not dropped and j.combat.simulation.tick>=90:
                if remote.personal_pack!=null:press(KEY_I)
                dropped=true;mark("dropped");link.send("leave");link.peer.host.flush();link._retry();link.next_retry=Time.get_ticks_msec()+2800
            if j.party.active==1 and link.phase=="turn_ready" and stage==0:
                if remote.personal_pack!=null:press(KEY_I)
                action("begin_turn")
            elif j.party.active==1 and link.phase=="map" and stage==0:action("rest")
            if exists("complete"):break
            continue
        if stage==0:
            if link.phase=="turn_ready":action("begin_turn")
            elif link.phase=="map":
                var delta: Vector2i=Vector2i(82,28)-j.world.position
                if delta.length_squared()>9:
                    controls.buttons[JOY_BUTTON_DPAD_LEFT]=delta.x<0;controls.buttons[JOY_BUTTON_DPAD_RIGHT]=delta.x>0
                    controls.buttons[JOY_BUTTON_DPAD_UP]=delta.y<0;controls.buttons[JOY_BUTTON_DPAD_DOWN]=delta.y>0
                else:action("enter",{"id":"highwood"})
            elif link.phase=="town":check(j.town_id=="highwood","active player enters classic town");stage=1;await capture("campaign-town")
        elif stage==1:
            if j.service=="":action("service",{"id":"smith"})
            elif j.service=="smith":
                if j.character.weapon=="long_sword":action("buy",{"id":"broad_sword"})
                else:check(j.character.weapon=="broad_sword" and j.inventory.gold==0,"server applies smith purchase once");stage=2;await capture("campaign-smith")
        elif stage==2:
            action("leave_town")
            if link.phase!="town":stage=3
        elif stage==3:
            if j.party.active==0 and link.phase=="turn_ready":action("begin_turn")
            elif j.party.active==0 and link.phase=="map":stage=4
        elif stage==4:
            var delta: Vector2i=j.world.lair("grassland_north").position-j.world.position
            if delta.length_squared()>4:
                controls.buttons[JOY_BUTTON_DPAD_LEFT]=delta.x<0;controls.buttons[JOY_BUTTON_DPAD_RIGHT]=delta.x>0
                controls.buttons[JOY_BUTTON_DPAD_UP]=delta.y<0;controls.buttons[JOY_BUTTON_DPAD_DOWN]=delta.y>0
            elif link.phase=="map":action("enter",{"id":"grassland_north"})
            if link.phase=="battle":stage=5;check(remote.arena!=null,"normal client enters monster battle");await capture("campaign-battle")
        elif stage==5:
            if link.phase=="battle":
                controls.buttons[controls.profile.bindings.swing.code]=true
                if resumed and j.combat.simulation.tick>=180:action("retreat")
            elif link.phase=="result":action("result")
            elif link.phase=="loot":
                var pile: Dictionary=j.available_loot()
                action("collect_loot" if int(pile.get("gold",0))+int(pile.get("keys",0))+int(pile.get("stones",0))+pile.get("items",{}).size()>0 else "leave_loot")
            elif link.phase=="map":check(resumed,"battle survived reserved-seat reconnect");stage=6
        elif stage==6:
            if link.phase=="map":action("rest")
            else:mark("complete");break
    check(Time.get_ticks_msec()<deadline,"campaign runtime completes before timeout")
    check(seen.has("battle") and seen.has("town") and seen.has("computer"),"shared campaign includes towns, monster combat and AI turns")
    check(resumed and paused_tick>=0,"lost player rejoins the same paused campaign")
    check(link.seat==role,"seat identity remains stable")
    var report_data: Dictionary={"result":"PASS" if failures.is_empty() else "FAIL","role":role,"checks":checks,"failures":failures,"stages":seen.keys(),"state":link.state,"phase":link.phase,"position":str(link.replica.world.position),"paused_frames":paused_frames,"resumed":resumed,"captures":captured.keys()}
    var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(report_data,"  ")+"\n");file.close()
    print("CAMPAIGN_RUNTIME=",JSON.stringify(report_data))
    if role==0 and failures.is_empty():
        var goodbye: int=Time.get_ticks_msec()+2000
        while not exists("guest-complete") and Time.get_ticks_msec()<goodbye:await parent.get_tree().process_frame
    world.close_campaign_network();world.queue_free();await parent.get_tree().process_frame
    link=null;world=null
    if failures.is_empty():print("PASS: campaign client ",role," through ordinary menu, classic map/town/battle, inventory and reconnect")
    parent.get_tree().quit(0 if failures.is_empty() else 1)
