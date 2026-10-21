extends SceneTree
const Connection=preload("res://scripts/session/campaign_connection.gd")
const Runner=preload("res://scripts/session/campaign_host_runner.gd")
const Protocol=preload("res://scripts/session/campaign_protocol.gd")
var checks: int=0
var failures: Array[String]=[]
var players: Array=[]
func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failures.append(label);push_error(label)
func pump(state: String,limit: int=5000) -> bool:
    var until: int=Time.get_ticks_msec()+limit
    while Time.get_ticks_msec()<until:
        for player in players:player.poll()
        if players.all(func(p):return p.state==state):return true
        await create_timer(0.005).timeout
    return false
func _initialize() -> void:run.call_deferred()
func run() -> void:
    var port: int=35000+OS.get_process_id()%20000
    var a: RefCounted=Connection.new();a.profile_path=""
    players.append(a)
    check(a.host_game(port,0,4),"embedded host opens same standalone campaign core")
    var server: Node=a.host_runtime
    for seat in range(1,4):
        var player: RefCounted=Connection.new();player.profile_path="";players.append(player)
        check(player.join_game("127.0.0.1",port,seat),"ordinary client joins human seat")
    check(await pump("lobby"),"four clients reach lobby")
    check(players.map(func(p):return p.seat)==[0,1,2,3],"four stable knight identities")
    players[0].ready();await create_timer(0.06).timeout
    check(not server.host.started,"one player cannot start other players")
    for player in players:player.ready()
    check(await pump("playing"),"all four clients start a classic campaign")
    check(players.all(func(p):return p.view_received and p.replica.party.players.size()==4),"all clients receive complete detached campaign views")
    check(server.host.session.journey.human_players==4,"host owns one four-human campaign")
    check(a.replica.party.awaiting,"first human turn awaits start")
    a.command("begin_turn")
    var until: int=Time.get_ticks_msec()+3000
    while a.phase!="map" and Time.get_ticks_msec()<until:
        for player in players:player.poll()
        await create_timer(0.005).timeout
    check(a.phase=="map","active knight begins map turn through command")
    players[1].command("rest")
    until=Time.get_ticks_msec()+2000
    while players[1].last_ack.is_empty() and Time.get_ticks_msec()<until:
        for player in players:player.poll()
        await create_timer(0.005).timeout
    check(not players[1].last_ack.get("ok",true) and server.host.session.journey.party.active==0,"waiting human cannot end active turn")
    var other_position: Vector2i=server.host.session.journey.party.record(server.host.session.journey,1).position
    var initial: Vector2i=server.host.session.journey.world.position
    var move_until: int=Time.get_ticks_msec()+3000
    while Time.get_ticks_msec()<move_until and server.host.session.journey.world.position.x<=initial.x:
        a.advance(Vector2i.RIGHT)
        for player in players:player.poll()
        await create_timer(0.02).timeout
    if server.host.session.journey.world.position.x<=initial.x:print("MOVEMENT_DEBUG=",JSON.stringify({"position":str(server.host.session.journey.world.position),"initial":str(initial),"phase":server.host.session.phase(),"epoch":server.host.session.epoch,"client_epoch":a.epoch,"state":a.state,"sequence":a.input_sequence,"host_sequences":server.host.session.input_sequences,"held":str(server.host.session.held),"tick":server.host.session.tick,"invalid":server.host.invalid_inputs}))
    check(server.host.session.journey.world.position.x>initial.x,"remote human input advances authoritative map")
    check(server.host.session.journey.party.record(server.host.session.journey,1).position==other_position,"movement changes only the assigned active knight")
    var b: RefCounted=players[1]
    var identities: Array=players.map(func(p):return [p.seat,p.token])
    b.peer.close();b.peer=null;b.state="reconnecting";b.next_retry=Time.get_ticks_msec()+60000
    until=Time.get_ticks_msec()+5000
    while server.host.state!="paused" and Time.get_ticks_msec()<until:
        for player in players:player.poll()
        await create_timer(0.005).timeout
    check(server.host.state=="paused" and server.host.session.paused,"lost player pauses campaign with seat reserved")
    var frozen: Dictionary=server.host.session.safe_checkpoint();var frozen_tick: int=server.host.session.tick
    for n in range(80):
        for player in players:player.poll()
        await create_timer(0.005).timeout
    check(server.host.session.tick==frozen_tick and server.host.session.safe_checkpoint()==frozen,"network reconnect phase advances no simulation, RNG or AI")
    b.next_retry=0
    check(await pump("paused",7000),"all clients reconnect to the same reserved campaign")
    check(players.map(func(p):return [p.seat,p.token])==identities,"reconnect preserves each original knight credential")
    for player in players:player.ready()
    check(await pump("playing"),"players agree to resume paused campaign")
    var stopped: Vector2i=server.host.session.journey.world.position
    for n in range(20):
        for player in players:player.poll()
        await create_timer(0.005).timeout
    check(server.host.session.journey.world.position==stopped,"reconnect cannot replay old held movement")
    a.command("rest")
    until=Time.get_ticks_msec()+3000
    while server.host.session.journey.party.active!=1 and Time.get_ticks_msec()<until:
        for player in players:player.poll()
        await create_timer(0.005).timeout
    check(server.host.session.journey.party.active==1,"rest transfers turn to the next connected human")
    var path: String="user://campaign-host-test-"+str(OS.get_process_id())+".json"
    server.host.store.path=path
    check(server.host.save(),"host writes separate campaign envelope")
    var loaded: Node=Runner.new(2,99,path)
    check(loaded.host.started and loaded.host.session.paused and loaded.host.credentials==server.host.credentials,"dedicated host can resume the same saved roster and reserved seats")
    check(loaded.host.session.journey.checkpoint()==server.host.session.safe_checkpoint(),"restart preserves the existing safe campaign checkpoint")
    loaded.free()
    for index in range(3,0,-1):players[index].close()
    a.close();await process_frame
    for suffix in ["",".bak",".tmp"]:
        if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
    players.clear()
    var profile: String="user://campaign-profile-test-"+str(OS.get_process_id())+".cfg"
    a.profile_path=profile;a.room="a".repeat(32);a.token="1".repeat(64);a.last_host_path="user://first-campaign.json";a.save_profile()
    a.room="b".repeat(32);a.token="2".repeat(64);a.last_host_path="user://second-campaign.json";a.save_profile()
    var config:=ConfigFile.new();config.load(profile)
    check(config.get_value("rooms","a".repeat(32))=="1".repeat(64) and config.get_value("rooms","b".repeat(32))=="2".repeat(64),"hosting a new room retains old reserved credentials")
    check(config.get_value("hosts",a._key())=="user://second-campaign.json","hosted save history is independent from joined rooms")
    a.receive("identify",{"protocol":Protocol.VERSION,"build":Protocol.fingerprint(),"room":"a".repeat(32)})
    check(a.token=="1".repeat(64) and a.room=="a".repeat(32),"old saved room challenge restores its own credential")
    DirAccess.remove_absolute(ProjectSettings.globalize_path(profile))
    print("CAMPAIGN_HOST=",JSON.stringify({"checks":checks,"failures":failures}))
    if failures.is_empty():print("PASS: ",checks," four-client embedded/shared host, seat authority, pause, reconnect and safe restart checks")
    quit(0 if failures.is_empty() else 1)
