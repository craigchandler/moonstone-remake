extends RefCounted

const Rules=preload("res://content/foundation_rules.tres")
const Protocol=preload("res://scripts/session/duel_protocol.gd")
var world: Node
var link: RefCounted
var checks: int=0
var failures: Array[String]=[]
var captures: String=""
var captured: Dictionary={}
var traced: String=""

func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failures.append(label)

func press(code: int) -> void:
    var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=true
    world.get_viewport().push_input(event,true);event=event.duplicate();event.pressed=false;world.get_viewport().push_input(event,true)

func files() -> Dictionary:
    var result: Dictionary={}
    for name in ["user://journey.json","user://journey.json.bak","user://journey.json.tmp","user://preferences.cfg","user://controller.json"]:
        result[name]=FileAccess.get_file_as_bytes(name) if FileAccess.file_exists(name) else null
    return result

func capture(label: String) -> void:
    if captures.is_empty() or captured.has(label) or DisplayServer.get_name()=="headless":return
    captured[label]=true;DirAccess.make_dir_recursive_absolute(captures)
    await world.get_tree().process_frame
    await RenderingServer.frame_post_draw
    check(world.get_viewport().get_texture().get_image().save_png(captures+"/"+label+".png")==OK,"capture "+label)

func write_report(path: String, role: String, phase: String, rounds: Dictionary, saved: Dictionary, protected: Dictionary) -> void:
    check(world.journey.checkpoint()==saved,"network mode preserves campaign checkpoint")
    check(files()==protected,"network mode preserves existing/absent save and preference files")
    var result: Dictionary={"role":role,"phase":phase,"checks":checks,"failures":failures,"rounds":rounds,"notice":link.notice,"state":link.state,"captures":captured.keys()}
    var file: FileAccess=FileAccess.open(path,FileAccess.WRITE)
    file.store_string(JSON.stringify(result,"  ")+"\n");file.close()

func report(parent: Node) -> void:
    var role: String="host";var port: int=27866;var address: String="127.0.0.1";var output: String="";var drop: String="guest";var graceful: bool=false;var target_rounds: int=2
    for argument in OS.get_cmdline_user_args():
        if argument.begins_with("--network-role="):role=argument.trim_prefix("--network-role=")
        elif argument.begins_with("--network-port="):port=int(argument.trim_prefix("--network-port="))
        elif argument.begins_with("--network-address="):address=argument.trim_prefix("--network-address=")
        elif argument.begins_with("--network-result="):output=argument.trim_prefix("--network-result=")
        elif argument.begins_with("--network-drop="):drop=argument.trim_prefix("--network-drop=")
        elif argument.begins_with("--network-capture="):captures=argument.trim_prefix("--network-capture=")
        elif argument.begins_with("--network-rounds="):target_rounds=clampi(int(argument.trim_prefix("--network-rounds=")),2,12)
        elif argument=="--network-graceful":graceful=true
    if role not in ["host","guest"] or output.is_empty():push_error("Network probe requires role/result");parent.get_tree().quit(1);return
    var protected: Dictionary=files()
    world=load("res://scenes/main.tscn").instantiate();world.debug_mode=false;world.parse_launch_arguments=false;world.saving_enabled=false
    parent.add_child(world)
    world.journey.inventory.gold=73;world.journey.character.experience=7
    var saved: Dictionary=world.journey.checkpoint()
    world.show_menu(saved)
    press(KEY_P);check(world.practice_view!=null,"normal title enters practice")
    await capture("practice-network")
    press(KEY_N);check(world.network_lobby!=null,"normal practice opens network menu")
    if world.network_lobby==null:parent.get_tree().quit(1);return
    var lobby: Node=world.network_lobby
    lobby.knight_kind=0 if role=="host" else 3;lobby.port_text=str(port);lobby.address=address
    await capture("lobby-idle")
    lobby.activate("host" if role=="host" else "join");link=lobby.connection
    await capture("lobby-connecting")
    var controls: Node=parent.get_node("/root/MoonstoneInput")
    var rounds: Dictionary={};var drop_written: bool=false
    var deadline: int=Time.get_ticks_msec()+maxi(60000,target_rounds*12000+30000)
    while Time.get_ticks_msec()<deadline:
        await parent.get_tree().physics_frame
        controls.focused=true;controls.refresh_context();controls.blocked.clear();controls.buttons.clear()
        if link.state=="waiting":
            await capture("lobby-ready");link.ready()
        elif link.state=="playing" and world.arena!=null:
            var model: RefCounted=link.session.simulation
            var local: Dictionary=model.actors[link.local_actor]
            var rival: Dictionary=model.actors[3-link.local_actor]
            var tag: String=str(link.session.round_id)+":"+str(model.tick/100)
            if tag!=traced:
                traced=tag
                print("NETWORK_PROGRESS ",role," round=",link.session.round_id," tick=",model.tick," local=",local.x,",",local.y," hp=",local.health," rival=",rival.x,",",rival.y," hp=",rival.health," facing=",local.facing," action=",local.action," invalid=",link.invalid_inputs," sequence=",link.local_sequence)
            var attacker: bool=(role=="host" and link.session.round_id%2==1) or (role=="guest" and link.session.round_id%2==0)
            if attacker and local.health>0:
                var distance: int=abs(local.x-rival.x)
                # A delayed observer must not hold movement until the old 42px
                # sample: that can walk inside the sword's contact points. Near
                # melee, use short ordinary input taps and await their feedback.
                var toward: int=signi(int(rival.x)-int(local.x))
                var step: int=0
                if distance>90:step=toward
                elif model.tick%24<2:
                    if distance>44:step=toward
                    elif distance<28:step=-toward
                    elif local.facing!=toward:step=toward
                controls.buttons[JOY_BUTTON_DPAD_LEFT]=step<0
                controls.buttons[JOY_BUTTON_DPAD_RIGHT]=step>0
                if distance>=28 and distance<=44 and local.facing==toward:controls.buttons[controls.profile.bindings.swing.code]=true
            if model.tick>35:await capture("duel-round-"+str(link.session.round_id))
            if link.session.round_id>target_rounds and model.tick>=30 and role==drop and not drop_written:
                drop_written=true
                write_report(output,role,"drop",rounds,saved,protected)
                if graceful:
                    press(KEY_ESCAPE)
                    check(world.arena==null and world.network_lobby==null and world.practice_view.visible,"Escape leaves socket and returns to practice")
                    write_report(output,role,"complete",rounds,saved,protected)
                    print("PASS: network role ",role," graceful leave and ",checks," checks")
                    link.close();world.queue_free();await parent.get_tree().process_frame
                    world=null;link=null
                    parent.get_tree().quit(0 if failures.is_empty() else 1);return
        elif link.state=="ended":
            var key: String=str(link.session.round_id)
            if not rounds.has(key):
                rounds[key]={"tick":link.session.simulation.tick,"hash":Protocol.state_hash(link.session.simulation.snapshot()),"outcome":link.session.simulation.outcome()}
                check(world.arena!=null and not world.arena.managed_by_world,"standalone network fight")
                check(link.session.simulation.actors[1].owner==1 and link.session.simulation.actors[2].owner==2,"both combatants stay human-owned")
                await capture("result-round-"+key)
            link.ready()
        elif link.state=="closed":
            check(rounds.size()==target_rounds,"requested real combat rounds and rematches completed")
            await capture("disconnected")
            press(KEY_ENTER)
            check(world.arena==null and world.network_lobby==null and world.practice_view.visible,"disconnect confirmation returns to practice")
            write_report(output,role,"complete",rounds,saved,protected)
            print("PASS: network role ",role," disconnect and ",checks," checks")
            link.close();world.queue_free();await parent.get_tree().process_frame
            world=null;link=null
            parent.get_tree().quit(0 if failures.is_empty() else 1);return
    check(false,"network probe timed out")
    write_report(output,role,"timeout",rounds,saved,protected)
    parent.get_tree().quit(1)
