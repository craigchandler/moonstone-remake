extends SceneTree

# Real socket lifecycle failures; these use wall time rather than synthetic ticks.
const Connection=preload("res://scripts/session/duel_connection.gd")
const Protocol=preload("res://scripts/session/duel_protocol.gd")
const Rules=preload("res://content/foundation_rules.tres")
var checks: int=0
var failures: Array[String]=[]

func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failures.append(label);push_error(label)

func wait_closed(link: RefCounted, seconds: float) -> void:
    var deadline: int=Time.get_ticks_msec()+int(seconds*1000)
    while link.state!="closed" and Time.get_ticks_msec()<deadline:
        link.poll();await create_timer(0.005).timeout

func waiting(host: RefCounted,guest: RefCounted) -> bool:
    var deadline: int=Time.get_ticks_msec()+2000
    while Time.get_ticks_msec()<deadline:
        host.poll();guest.poll()
        if host.state=="waiting" and guest.state=="waiting":return true
        await create_timer(0.002).timeout
    return false

func raw_client(host: RefCounted,port: int) -> ENetMultiplayerPeer:
    var raw:=ENetMultiplayerPeer.new()
    if raw.create_client("127.0.0.1",port,3)!=OK:return null
    var deadline: int=Time.get_ticks_msec()+2000
    while Time.get_ticks_msec()<deadline:
        host.poll();raw.poll()
        if raw.get_connection_status()==MultiplayerPeer.CONNECTION_CONNECTED and host.host_runtime.host.clients.has(raw.get_unique_id()):return raw
        await create_timer(0.002).timeout
    raw.close();return null

func _initialize() -> void:run.call_deferred()
func run() -> void:
    var host: RefCounted=Connection.new(Rules);var guest: RefCounted=Connection.new(Rules)
    var port: int=36000+OS.get_process_id()%20000
    check(host.host_game(port,0),"host opens before cancellation")
    host.close();check(host.peer==null and host.state=="idle","cancel hosting releases the live socket")
    check(guest.join_game("127.0.0.1",port,1),"join can begin before the host exists")
    guest.close();check(guest.peer==null and guest.state=="idle","cancel connecting releases the live socket")
    check(host.host_game(port,0) and guest.join_game("127.0.0.1",port,1),"both cancelled objects can be reused")
    check(await waiting(host,guest),"retry after cancellation completes a fresh handshake")
    var before: Dictionary=host.session.simulation.snapshot()
    guest.close();await wait_closed(host,2)
    check(host.state=="closed" and host.session.simulation.snapshot()==before,"leaving the ready screen closes without advancing combat")
    host.close()

    check(guest.join_game("127.0.0.1",port,1),"unavailable host attempt opens")
    await wait_closed(guest,12)
    check(guest.state=="closed" and guest.peer==null and guest.notice=="HOST COULD NOT BE REACHED","unavailable host times out cleanly in real wall time")
    check(guest.session.simulation.state.is_empty(),"failed connection never creates client combat state")
    guest.close()

    check(host.host_game(port,0),"host reopens after failed connection")
    var raw: ENetMultiplayerPeer=await raw_client(host,port)
    check(raw!=null,"silent raw peer connects at the transport layer")
    if raw!=null:
        await wait_closed(host,12)
        check(host.state=="closed" and host.peer==null,"silent peer cannot leave the handshake hanging")
        check(host.session.simulation.tick==0,"silent handshake never starts combat")
        raw.close()
    host.close()

    for mismatch in ["build","protocol"]:
        check(host.host_game(port,2),"host retries before mismatched "+mismatch)
        raw=await raw_client(host,port)
        check(raw!=null,"raw mismatch socket connects "+mismatch)
        if raw!=null:
            var body: Dictionary={"protocol":Protocol.VERSION,"build":Protocol.fingerprint(),"colour":0}
            body[mismatch]="different" if mismatch=="build" else -1
            raw.set_target_peer(1);raw.transfer_mode=MultiplayerPeer.TRANSFER_MODE_RELIABLE
            raw.put_packet(Protocol.encode({"type":"hello","body":body}));raw.host.flush()
            await wait_closed(host,2)
            check(host.state=="closed" and host.notice=="MATCHING GAME BUILDS REQUIRED","reject mismatched "+mismatch+" before readiness")
            check(host.session.simulation.tick==0,"mismatched "+mismatch+" cannot change combat")
            raw.close()
        host.close()

    check(host.host_game(port,0) and guest.join_game("127.0.0.1",port,1),"compatible connection retries after rejections")
    check(await waiting(host,guest),"fresh compatible peers still reach ready")
    before=host.session.simulation.snapshot()
    # Stop polling the guest. Real host heartbeats cannot replace missing peer traffic.
    await wait_closed(host,7)
    check(host.state=="closed" and host.peer==null and host.notice=="CONNECTION TIMED OUT","stalled ready opponent times out in real wall time")
    check(host.session.simulation.snapshot()==before,"timeout never advances a waiting match")
    guest.close();host.close()

    check(host.host_game(port,0),"port remains reusable after every failure")
    raw=await raw_client(host,port)
    if raw!=null:
        raw.set_target_peer(1);raw.transfer_mode=MultiplayerPeer.TRANSFER_MODE_RELIABLE
        raw.put_packet(Protocol.encode({"type":5,"body":{}}));raw.host.flush()
        await wait_closed(host,2)
        check(host.state=="closed" and host.notice=="INVALID DUEL DATA","malformed message header closes without entering combat")
        raw.close()
    else:check(false,"raw malformed-message socket connects")
    host.close();guest.close()
    print("NETWORK_FAILURES=",JSON.stringify({"checks":checks,"failures":failures}))
    if failures.is_empty():print("PASS: ",checks," real socket cancellation, retry, unreachable/silent/stalled peers, protocol/build mismatch and malformed header checks")
    quit(0 if failures.is_empty() else 1)
