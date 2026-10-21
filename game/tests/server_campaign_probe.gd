extends SceneTree
# Asset-free clients for an exported standalone campaign server.
const Connection=preload("res://scripts/session/campaign_connection.gd")
var players: Array=[]
var failures: Array[String]=[]
var checks: int=0
var port: int
var directory: String
var resuming: bool=false
func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failures.append(label);push_error(label)
func pump(target: String,limit: int=6000) -> bool:
    var end: int=Time.get_ticks_msec()+limit
    while Time.get_ticks_msec()<end:
        for player in players:player.poll()
        if players.all(func(p):return p.state==target):return true
        await create_timer(0.005).timeout
    return false
func frames(count: int) -> void:
    for index in range(count):
        for player in players:player.poll()
        await create_timer(0.02).timeout
func _initialize() -> void:run.call_deferred()
func run() -> void:
    var args: PackedStringArray=OS.get_cmdline_user_args();port=int(args[0]);directory=args[1];resuming="--resume" in args
    var tokens: Array=[]
    if resuming:tokens=JSON.parse_string(FileAccess.get_file_as_string(directory+"/credentials.local.json"))
    for seat in range(4):
        var player: RefCounted=Connection.new();player.profile_path="";players.append(player)
        check(player.join_game("127.0.0.1",port,seat),"ordinary art-free campaign client connects")
        if resuming:player.token=tokens[seat].token;player.room=tokens[seat].room
    check(await pump("paused" if resuming else "lobby"),"four clients join existing reserved seats or new lobby")
    check(players.map(func(p):return p.seat)==[0,1,2,3],"four identities are stable")
    for player in players:player.ready()
    check(await pump("playing"),"all four agree to play")
    await frames(5)
    if not resuming:
        for seat in range(4):
            check(players[seat].replica.party.active==seat,"classic turn reaches each connected human")
            players[seat].command("begin_turn");await frames(6)
            check(players[seat].phase=="map","ordinary turn-start command reaches server")
            players[seat].command("rest");await frames(6)
        check(players[0].replica.day==2,"one full round applies upkeep exactly once")
    var owner: int=players[0].replica.party.active
    if players[owner].phase=="turn_ready":players[owner].command("begin_turn");await frames(5)
    var before: Vector2i=players[owner].replica.world.position
    for index in range(12):players[owner].advance(Vector2i.RIGHT);await frames(1)
    await frames(5)
    check(players[owner].replica.world.position.x>before.x,"server advances map movement from assigned seat input")
    check(players.all(func(p):return p.replica.world.position==players[0].replica.world.position),"all map observers agree")
    var credentials: Array=[]
    for player in players:credentials.append({"room":player.room,"token":player.token})
    var file:=FileAccess.open(directory+"/credentials.local.json",FileAccess.WRITE);file.store_string(JSON.stringify(credentials));file.close()
    players[1].send("leave");players[1].peer.host.flush();players[1]._retry();players[1].next_retry=Time.get_ticks_msec()+1800
    var end: int=Time.get_ticks_msec()+5000
    while players[0].state!="paused" and players[0].state!="reconnecting" and Time.get_ticks_msec()<end:await frames(1)
    await frames(20)
    var frozen: Vector2i=players[0].replica.world.position
    var frozen_tick: int=players[0].latest_tick
    await frames(30)
    check(players[0].replica.world.position==frozen and players[0].latest_tick==frozen_tick,"disconnect freezes live campaign")
    check(await pump("paused",8000),"whole native transport reopens while campaign/credentials survive")
    check(players.map(func(p):return {"room":p.room,"token":p.token})==credentials,"reserved credentials survive reconnect")
    for player in players:player.ready()
    check(await pump("playing"),"all reserved humans resume")
    await frames(10)
    check(players[0].replica.world.position==frozen,"reconnect does not replay held input")
    for player in players:check(player.own_inventory.identity.kind==player.seat,"personal inventory retains assigned knight")
    var result: Dictionary={"result":"PASS" if failures.is_empty() else "FAIL","checks":checks,"failures":failures,"resumed_saved_room":resuming,"day":players[0].replica.day,"turn":players[0].replica.party.turn,"room":players[0].room}
    file=FileAccess.open(directory+("/campaign-resume.json" if resuming else "/campaign-clients.json"),FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "));file.close()
    for player in players:player.close()
    players.clear();await process_frame
    if failures.is_empty():print("PASS: ",checks," exported campaign host with four art-free clients, turns, map agreement, inventory, pause and reconnect")
    quit(0 if failures.is_empty() else 1)
