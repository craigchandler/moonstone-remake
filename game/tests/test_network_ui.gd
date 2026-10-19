extends SceneTree
const Connection=preload("res://scripts/session/duel_connection.gd")
const Rules=preload("res://content/foundation_rules.tres")
var checks: int=0
var failures: Array[String]=[]
func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failures.append(label);push_error(label)
func press(code: int,unicode: int=0) -> void:
    var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.unicode=unicode;event.pressed=true
    root.push_input(event,true);event=event.duplicate();event.pressed=false;root.push_input(event,true)
func pump(a: RefCounted,b: RefCounted,state: String) -> bool:
    var deadline: int=Time.get_ticks_msec()+2000
    while Time.get_ticks_msec()<deadline:
        a.poll();b.poll()
        if a.state==state and b.state==state:return true
        await create_timer(0.002).timeout
    return false
func _initialize() -> void:run.call_deferred()
func run() -> void:
    var world: Node=load("res://scenes/main.tscn").instantiate()
    world.debug_mode=false;world.parse_launch_arguments=false;world.saving_enabled=false
    root.add_child(world);world.set_physics_process(false)
    var players: Array=[]
    for kind in range(4):players.append({"human":kind<2,"input":kind,"identity":{"kind":kind,"name":"DUEL TEST "+str(kind+1)}})
    check(world.journey.start_local_party(players,7100,false),"party fixture")
    var saved: Dictionary=world.journey.checkpoint();var before: Dictionary=world.journey.snapshot()
    world.show_menu(saved);press(KEY_P);press(KEY_N)
    check(world.network_lobby!=null and not world.practice_view.visible,"normal practice N opens classic network lobby")
    var menu: Node=world.network_lobby
    check(menu.art.panel_background!=null and menu.art.pixel_font!=null,"classic arches and font")
    for index in range(menu.actions().size()):check(Rect2(50,80,246,288).encloses(menu.action_rect(index)),"network action fits inside arch "+str(index))
    menu.activate("address")
    for character in "192.168.1.20":press(0,character.unicode_at(0))
    press(KEY_ENTER);check(menu.address=="192.168.1.20" and menu.editing.is_empty(),"address entry replaces selected text and confirms")
    menu.activate("address");press(KEY_BACKSPACE);press(KEY_ESCAPE)
    check(menu.address=="192.168.1.20","Escape cancels address edits")
    menu.address="127.0.0.1";menu.port_text=str(40000+OS.get_process_id()%15000)
    menu.activate("host")
    var guest: RefCounted=Connection.new(Rules);guest.join_game("127.0.0.1",int(menu.port_text),1)
    check(await pump(menu.connection,guest,"waiting"),"host menu reaches ready state")
    check(menu.selected==menu.actions().find("ready"),"ready is selected after connection, so Enter cannot restart the socket")
    press(KEY_ENTER);guest.ready()
    check(await pump(menu.connection,guest,"playing"),"menu ready starts actual duel")
    check(world.arena!=null and not menu.visible and world.arena.network_duel==menu.connection,"network session is shown in arena")
    world.arena.set_physics_process(false)
    var controls: Node=root.get_node("MoonstoneInput")
    controls.open_pause()
    check(paused and world.arena.can_process() and controls.pause_view.reason=="DUEL CONTINUES","local pause menu leaves network arena processing")
    var tick: int=menu.connection.session.simulation.tick
    world.arena._physics_process(0.02)
    check(menu.connection.session.simulation.tick==tick+1,"host authority advances while local controls are paused")
    controls.close_pause()
    press(KEY_F1);tick=menu.connection.session.simulation.tick
    world.arena._physics_process(0.02)
    check(world.arena.practice_overlay.help_visible and menu.connection.session.simulation.tick==tick+1,"network help shows controls without pausing rival")
    press(KEY_ESCAPE);check(world.arena!=null and not world.arena.practice_overlay.help_visible,"Escape dismisses help before leaving")
    for actor in menu.connection.session.simulation.actors.values():actor.health=0;actor.down_remaining=0
    world.arena._physics_process(0.02)
    check(await pump(menu.connection,guest,"ended"),"network result shown after terminal state")
    var arena: Node=world.arena
    press(KEY_R);check(menu.connection.local_ready and menu.connection.session.round_id==1,"R requests agreement instead of locally restarting")
    guest.ready();check(await pump(menu.connection,guest,"playing"),"both confirm rematch")
    check(world.arena==arena and arena.network_round==2 and arena.session.simulation.tick==0,"round resets existing presentation without a second arena")
    guest.close()
    var deadline: int=Time.get_ticks_msec()+2000
    while menu.connection.state!="closed" and Time.get_ticks_msec()<deadline:menu.connection.poll();await create_timer(0.002).timeout
    check(menu.connection.state=="closed","duel reports disconnect")
    press(KEY_ENTER)
    check(world.arena==null and world.network_lobby==null and world.practice_view.visible,"disconnect confirmation restores practice input")
    world._physics_process(0.02)
    check(world.journey.checkpoint()==saved and world.journey.snapshot()==before,"network mode preserves party, world, kit and RNG")
    press(KEY_ESCAPE)
    check(world.menu_view.visible and world.practice==null,"practice returns to original title")
    world.queue_free();await process_frame
    print("NETWORK_UI=",JSON.stringify({"checks":checks,"failures":failures}))
    if failures.is_empty():print("PASS: ",checks," classic host/join UI, text editing, ready, local pause, rematch, disconnect and campaign isolation checks")
    quit(0 if failures.is_empty() else 1)
