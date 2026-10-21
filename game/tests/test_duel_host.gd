extends SceneTree

const Runner=preload("res://scripts/session/duel_host_runner.gd")
const Connection=preload("res://scripts/session/duel_connection.gd")
const Rules=preload("res://content/foundation_rules.tres")
var checks: int=0
var failures: Array[String]=[]
func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failures.append(label);push_error(label)
func pump(a: RefCounted,b: RefCounted,state: String) -> bool:
    var deadline: int=Time.get_ticks_msec()+2000
    while Time.get_ticks_msec()<deadline:
        a.poll();b.poll()
        if a.state==state and b.state==state:return true
        await create_timer(0.002).timeout
    return false
func _initialize() -> void:run.call_deferred()
func run() -> void:
    var server: Node=Runner.new(Rules);root.add_child(server)
    var port: int=35000+OS.get_process_id()%20000
    check(server.host.listen(port),"independent host opens without an arena or local knight")
    var initial: Dictionary=server.host.session.simulation.snapshot()
    var a: RefCounted=Connection.new(Rules);var b: RefCounted=Connection.new(Rules)
    check(a.join_game("127.0.0.1",port,3),"first ordinary client joins dedicated host")
    var deadline: int=Time.get_ticks_msec()+2000
    while a.state!="seated" and Time.get_ticks_msec()<deadline:a.poll();await create_timer(0.002).timeout
    check(a.state=="seated" and a.local_actor==1,"first client receives stable seat1 without owning the server")
    a.ready();await create_timer(0.06).timeout;a.poll()
    check(not a.local_ready and server.host.session.simulation.tick==0,"one client cannot start a round before an opponent exists")
    check(b.join_game("127.0.0.1",port,3),"second ordinary client joins dedicated host")
    check(await pump(a,b,"waiting"),"two clients reach readiness")
    check(a.local_actor==1 and b.local_actor==2 and not a.authority and not b.authority,"server owns neither knight and assigns both connections")
    check(a.colours==[3,0] and a.colours==b.colours,"duplicate colour resolution is independent of UI")
    check(not a.session.authoritative and not b.session.authoritative and server.host.session.authoritative,"both players have read-only replicas")
    check(not a.session.step() and not b.session.step(),"neither client can advance combat authority")
    a.send("frame",{"state":{"actors":{2:{"health":0}}}})
    a.send("input",{"actor":2,"round":1,"sequence":1,"dx":1,"dy":0,"action":"swing","seen":0},1)
    await create_timer(0.06).timeout
    check(server.host.session.simulation.snapshot()==initial,"unready/spoofed input and client health frames cannot change state")
    a.ready();await create_timer(0.06).timeout;a.poll();b.poll()
    check(a.state=="waiting" and b.remote_ready,"one player's ready cannot start the game")
    b.ready();check(await pump(a,b,"playing"),"both remote players start a round")
    var tick: int=server.host.session.simulation.tick
    await create_timer(0.14).timeout;a.poll();b.poll()
    check(server.host.session.simulation.tick>=tick+5,"authority clock runs without screen updates or input calls")
    var x1: int=server.host.session.simulation.actors[1].x
    var x2: int=server.host.session.simulation.actors[2].x
    for n in range(40):
        a.advance(Vector2i.RIGHT,"idle");b.advance(Vector2i.LEFT,"idle")
        await create_timer(0.02).timeout
        if server.host.session.simulation.actors[1].x>x1 and server.host.session.simulation.actors[2].x<x2:break
    print("REMOTE_INPUT ",server.host.session.simulation.tick," positions=",server.host.session.simulation.actors[1].x,",",server.host.session.simulation.actors[2].x," sequences=",server.host.session.last_input," replica=",a.session.simulation.tick,",",b.session.simulation.tick)
    check(server.host.session.simulation.actors[1].x>x1 and server.host.session.simulation.actors[2].x<x2,"each remote client controls only its assigned human")
    a.send("input",{"round":1,"sequence":a.local_sequence+1,"actor":2,"dx":1,"dy":0,"action":"swing","seen":server.host.session.simulation.tick})
    deadline=Time.get_ticks_msec()+1000
    while server.host.invalid_inputs==0 and Time.get_ticks_msec()<deadline:a.poll();b.poll();await create_timer(0.002).timeout
    check(server.host.invalid_inputs>0,"ownership-spoofing fields rejected by shared host")
    server.set_physics_process(false)
    server.host.broadcast("frame",server.host.session.frame())
    deadline=Time.get_ticks_msec()+2000
    while Time.get_ticks_msec()<deadline:
        server.host.poll();a.poll();b.poll()
        if a.session.simulation.tick==server.host.session.simulation.tick and b.session.simulation.tick==a.session.simulation.tick:break
        await create_timer(0.002).timeout
    check(a.session.simulation.snapshot()==server.host.session.simulation.snapshot() and b.session.simulation.snapshot()==a.session.simulation.snapshot(),"both complete replicas equal the independent authoritative state")
    # Explicit terminal fixture tests lifecycle; exported review uses real hits.
    for actor in server.host.session.simulation.actors.values():actor.health=0;actor.down_remaining=0
    server.set_physics_process(true)
    check(await pump(a,b,"ended"),"both clients receive the terminal result")
    check(a.session.simulation.snapshot()==b.session.simulation.snapshot() and server.host.completed_rounds==1,"terminal tick, RNG and complete state agree")
    a.ready();await create_timer(0.06).timeout;a.poll();b.poll()
    check(server.host.state=="ended" and b.remote_ready,"one client cannot restart the other")
    b.ready();check(await pump(a,b,"playing"),"both agree to rematch")
    check(a.session.round_id==2 and b.session.round_id==2 and server.host.session.simulation.actors[1].health==20,"rematch creates a fresh independent round")
    b.close()
    deadline=Time.get_ticks_msec()+2000
    while (a.state!="closed" or server.host.state!="listening") and Time.get_ticks_msec()<deadline:a.poll();await create_timer(0.002).timeout
    check(a.state=="closed" and server.host.state=="listening" and server.host.peer!=null,"disconnect stops the match while standalone host keeps listening")
    check(server.host.clients.is_empty() and server.host.seats.is_empty() and server.host.session.simulation.snapshot()==initial,"abandoned match leaves no input, player, RNG or combat state")
    a.close()
    check(a.join_game("127.0.0.1",port,1) and b.join_game("127.0.0.1",port,2),"same server accepts a fresh pair sequentially")
    check(await pump(a,b,"waiting"),"fresh pair completes handshake after prior disconnect")
    check(a.session.round_id==1 and b.session.round_id==1 and a.colours==[1,2],"new match has fresh identity/round state")
    # Neither client polls/acknowledges the server's disconnect during this
    # interval. A lost process must not keep a native ENet slot occupied.
    var transport_a: ENetPacketPeer=server.host.peer.get_peer(a.peer.get_unique_id())
    var transport_b: ENetPacketPeer=server.host.peer.get_peer(b.peer.get_unique_id())
    server.host._abort("CONNECTION TIMED OUT")
    await create_timer(0.18).timeout
    check(transport_a.get_state()==ENetPacketPeer.STATE_DISCONNECTED and transport_b.get_state()==ENetPacketPeer.STATE_DISCONNECTED,"abandoned native slots released without client acknowledgement")
    check(await pump(a,b,"closed"),"aborted clients receive a terminal connection state")
    a.close();b.close()
    check(a.join_game("127.0.0.1",port,1) and b.join_game("127.0.0.1",port,2) and await pump(a,b,"waiting"),"another full pair joins immediately after an unacknowledged disconnect")
    server.stop();server.queue_free()
    deadline=Time.get_ticks_msec()+2000
    while Time.get_ticks_msec()<deadline:
        a.poll();b.poll()
        if a.state=="closed" and b.state=="closed":break
        await create_timer(0.002).timeout
    check(a.state=="closed" and b.state=="closed","stopping a dedicated host releases both clients")
    a.close();b.close();await process_frame
    print("DUEL_HOST=",JSON.stringify({"checks":checks,"failures":failures}))
    if failures.is_empty():print("PASS: ",checks," dedicated/shared host, independent clock, remote seats, authority, rematch, reuse and shutdown checks")
    quit(0 if failures.is_empty() else 1)
