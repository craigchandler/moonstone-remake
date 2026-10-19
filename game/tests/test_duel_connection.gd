extends SceneTree
const Connection=preload("res://scripts/session/duel_connection.gd")
const Protocol=preload("res://scripts/session/duel_protocol.gd")
const Rules=preload("res://content/foundation_rules.tres")
var checks: int=0
var failures: Array[String]=[]
func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failures.append(label);push_error(label)
func pump(a: RefCounted,b: RefCounted,until: String,seconds: float=3.0) -> bool:
    var deadline: int=Time.get_ticks_msec()+int(seconds*1000)
    while Time.get_ticks_msec()<deadline:
        a.poll();b.poll()
        if a.state==until and b.state==until:return true
        await create_timer(0.002).timeout
    return false
func _initialize() -> void:run.call_deferred()
func run() -> void:
    var host: RefCounted=Connection.new(Rules);var guest: RefCounted=Connection.new(Rules)
    var port: int=38000+OS.get_process_id()%20000
    check(Protocol.fingerprint().length()==64,"current combat compatibility fingerprint")
    check(not host.host_game(0,0) and not guest.join_game("",port,1),"invalid endpoint handled before socket creation")
    check(host.host_game(port,0),"real UDP host opens")
    check(guest.join_game("127.0.0.1",port,0),"real UDP client connects")
    check(await pump(host,guest,"waiting"),"compatible handshake reaches ready screen")
    if host.state!="waiting" or guest.state!="waiting":host.close();guest.close();quit(1);return
    check(host.colours==guest.colours and host.colours[0]!=host.colours[1],"duplicate knight colour resolved identically")
    host.ready()
    for n in range(5):host.poll();guest.poll();await process_frame
    check(host.state=="waiting" and guest.remote_ready,"one player cannot start alone; ready status reaches rival")
    guest.ready();check(await pump(host,guest,"playing"),"both ready start a human duel")
    var first: Dictionary=host.session.simulation.snapshot()
    guest.send("frame",{"state":{"actors":{1:{"health":0}}}})
    for n in range(4):host.poll();guest.poll();await process_frame
    check(host.session.simulation.snapshot()==first,"client cannot publish authoritative health/state")
    for n in range(180):
        # Dropped samples and jitter: the guest sends only every fourth host tick.
        if n%4==0:guest.advance(Vector2i.LEFT if n<20 else Vector2i.ZERO,"idle" if n<20 else "swing")
        host.advance(Vector2i.RIGHT if n<20 else Vector2i.ZERO,"idle" if n<20 else "swing")
        guest.poll()
        if not host.session.valid_frame(host.session.frame()):
            print("INVALID_NATIVE_FRAME tick=",host.session.simulation.tick," primitive=",Protocol.primitive(host.session.frame()))
            for actor in host.session.simulation.actors.values():
                for field in host.session.template:
                    if typeof(actor[field])!=typeof(host.session.template[field]):print("ACTOR_TYPE ",field," ",typeof(actor[field])," != ",typeof(host.session.template[field]))
            break
        await create_timer(0.02).timeout
        if host.state=="closed" or guest.state=="closed":break
    var deadline: int=Time.get_ticks_msec()+2000
    while guest.session.simulation.tick<host.session.simulation.tick and Time.get_ticks_msec()<deadline:
        host.poll();guest.poll();await create_timer(0.002).timeout
    print("SOCKET_STATUS ",host.state," ",host.notice," / ",guest.state," ",guest.notice)
    check(host.state!="closed" and guest.state!="closed","jitter and skipped input samples preserve connection")
    var host_state: Dictionary=host.session.simulation.snapshot()
    var guest_state: Dictionary=guest.session.simulation.snapshot()
    if host_state!=guest_state:
        for field in host_state:
            if host_state[field]!=guest_state.get(field):print("SOCKET_DIFF ",field," host=",var_to_str(host_state[field])," guest=",var_to_str(guest_state.get(field)))
    check(host_state==guest_state,"actual socket replica matches all authoritative actor/projectile/RNG state")
    check(guest.received_ticks.size()>100,"real ordered state stream delivered")
    # Explicit terminal fixture isolates rematch lifecycle from combat skill.
    for actor in host.session.simulation.actors.values():actor.health=0;actor.down_remaining=0
    host.advance(Vector2i.ZERO,"idle")
    check(await pump(host,guest,"ended"),"both peers reach the same terminal result")
    host.ready()
    for n in range(5):host.poll();guest.poll();await process_frame
    check(host.state=="ended" and guest.remote_ready,"rematch needs both players")
    guest.ready();check(await pump(host,guest,"playing"),"agreed rematch starts")
    check(host.session.round_id==2 and guest.session.round_id==2 and host.session.simulation.tick==0 and host.session.simulation.snapshot()==guest.session.simulation.snapshot(),"rematch resets the complete shared round")
    guest.close()
    deadline=Time.get_ticks_msec()+2000
    while host.state!="closed" and Time.get_ticks_msec()<deadline:host.poll();await create_timer(0.002).timeout
    check(host.state=="closed","explicit leave stops opponent without AI takeover")
    host.close()
    # A raw ENet peer offers the wrong protocol; no gameplay begins.
    check(host.host_game(port,2),"closed host releases the port")
    var wrong:=ENetMultiplayerPeer.new();check(wrong.create_client("127.0.0.1",port,3)==OK,"mismatched client socket")
    deadline=Time.get_ticks_msec()+2000
    while wrong.get_connection_status()!=MultiplayerPeer.CONNECTION_CONNECTED and Time.get_ticks_msec()<deadline:host.poll();wrong.poll();await create_timer(0.002).timeout
    wrong.set_target_peer(1);wrong.transfer_mode=MultiplayerPeer.TRANSFER_MODE_RELIABLE
    wrong.put_packet(Protocol.encode({"type":"hello","body":{"protocol":-1,"build":"wrong","colour":0}}));wrong.host.flush()
    deadline=Time.get_ticks_msec()+2000
    while host.state!="closed" and Time.get_ticks_msec()<deadline:host.poll();wrong.poll();await create_timer(0.002).timeout
    check(host.state=="closed" and host.notice=="MATCHING GAME BUILDS REQUIRED","incompatible build rejected before match")
    wrong.close();host.close()
    print("NETWORK_SOCKET=",JSON.stringify({"checks":checks,"failures":failures}))
    if failures.is_empty():print("PASS: ",checks," real ENet handshake, owner authority, jitter, result/rematch, disconnect and compatibility checks")
    quit(0 if failures.is_empty() else 1)
