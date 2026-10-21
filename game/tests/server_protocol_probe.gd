extends SceneTree

# Asset-free clients for the real exported server. This exercises the shared
# protocol/replica, not the graphical game or platform-specific player input.
const Connection=preload("res://scripts/session/duel_connection.gd")
const Rules=preload("res://content/foundation_rules.tres")
const Protocol=preload("res://scripts/session/duel_protocol.gd")
var a: RefCounted
var b: RefCounted
var rounds: Dictionary={}
var output: String
var failures: Array[String]=[]
func check(ok: bool,label: String) -> void:
    if not ok:failures.append(label);push_error(label)
func _initialize() -> void:run.call_deferred()
func pump(target: String) -> bool:
    var until: int=Time.get_ticks_msec()+5000
    while Time.get_ticks_msec()<until:
        a.poll();b.poll()
        if a.state==target and b.state==target:return true
        await create_timer(0.005).timeout
    return false
func input_for(link: RefCounted,attacker: bool) -> void:
    var model: RefCounted=link.session.simulation
    var local: Dictionary=model.actors[link.local_actor]
    var rival: Dictionary=model.actors[3-link.local_actor]
    var direction: int=0
    var action: String="idle"
    if attacker:
        var distance: int=abs(local.x-rival.x)
        var toward: int=signi(int(rival.x)-int(local.x))
        if distance>90:direction=toward
        elif model.tick%24<2:
            if distance>44:direction=toward
            elif distance<28:direction=-toward
            elif local.facing!=toward:direction=toward
        if distance>=28 and distance<=44 and local.facing==toward:action="swing"
    link.advance(Vector2i(direction,0),action)
func run() -> void:
    var args: PackedStringArray=OS.get_cmdline_user_args()
    var port: int=int(args[0]);output=args[1]
    a=Connection.new(Rules);b=Connection.new(Rules)
    check(a.join_game("127.0.0.1",port,0),"first client connects")
    var until: int=Time.get_ticks_msec()+5000
    while a.state!="seated" and Time.get_ticks_msec()<until:a.poll();await create_timer(0.005).timeout
    check(a.state=="seated" and a.local_actor==1,"first ordinary client receives seat1")
    check(b.join_game("127.0.0.1",port,1) and await pump("waiting"),"second client joins")
    check(b.local_actor==2 and not a.authority and not b.authority and not a.session.authoritative and not b.session.authoritative,"only server owns combat authority")
    until=Time.get_ticks_msec()+60000
    while failures.is_empty() and Time.get_ticks_msec()<until and rounds.size()<2:
        a.poll();b.poll()
        if a.state in ["waiting","ended"] and b.state==a.state:
            if a.state=="ended":
                var key: String=str(a.session.round_id)
                check(a.session.simulation.snapshot()==b.session.simulation.snapshot(),"both terminal snapshots match")
                rounds[key]={"tick":a.session.simulation.tick,"hash":Protocol.state_hash(a.session.simulation.snapshot()),"outcome":a.session.simulation.outcome()}
                if rounds.size()==2:break
            a.ready();b.ready()
        if a.state=="playing":input_for(a,a.session.round_id==1)
        if b.state=="playing":input_for(b,b.session.round_id==2)
        await create_timer(0.02).timeout
    check(rounds.size()==2,"two real combat rounds and rematch complete")
    if rounds.size()==2:check(rounds["1"].outcome=="victory" and rounds["2"].outcome=="defeat","both clients can win through real hits")
    a.close()
    until=Time.get_ticks_msec()+5000
    while b.state!="closed" and Time.get_ticks_msec()<until:b.poll();await create_timer(0.005).timeout
    check(b.state=="closed","leaving closes opponent match")
    b.close();await create_timer(0.3).timeout
    check(a.join_game("127.0.0.1",port,2),"fresh first client joins same host")
    until=Time.get_ticks_msec()+5000
    while a.state!="seated" and Time.get_ticks_msec()<until:a.poll();await create_timer(0.005).timeout
    check(a.state=="seated","same process reopens its room")
    check(b.join_game("127.0.0.1",port,3) and await pump("waiting"),"fresh pair completes handshake")
    check(a.session.round_id==1 and b.session.round_id==1 and a.colours==[2,3],"fresh room clears previous round and identities")
    a.close();b.close()
    var file: FileAccess=FileAccess.open(output,FileAccess.WRITE)
    file.store_string(JSON.stringify({"result":"PASS" if failures.is_empty() else "FAIL","rounds":rounds,"failures":failures},"  ")+"\n");file.close()
    if failures.is_empty():print("PASS: exported server, two asset-free clients, real hits, rematch, matching snapshots and room reuse")
    quit(0 if failures.is_empty() else 1)
