extends RefCounted

# ENet transport and match lifecycle; only the host steps NetworkDuelSession.
signal changed
signal fight_started
signal frame_received
const Session = preload("res://scripts/session/network_duel_session.gd")
const Protocol = preload("res://scripts/session/duel_protocol.gd")
const DEFAULT_PORT: int = 27866
var rules: Resource
var peer: ENetMultiplayerPeer
var session: RefCounted
var authority: bool = false
var remote: int = 0
var local_actor: int = 1
var colours: Array = [0,1]
var state: String = "idle"
var notice: String = "HOST OR JOIN A DUEL"
var local_ready: bool = false
var remote_ready: bool = false
var local_sequence: int = 0
var last_packet_ms: int = 0
var last_heartbeat_ms: int = 0
var hello_sent: bool = false
var received_ticks: Array[int] = []
var invalid_inputs: int = 0
var pending_failure: String = ""

func _init(rule_set: Resource) -> void:rules=rule_set

func _status(next: String, message: String) -> void:
    state=next;notice=message;changed.emit()

func host_game(port: int, colour: int) -> bool:
    close();authority=true;local_actor=1;colours=[clampi(colour,0,3),(colour+1)%4]
    if port<1024 or port>65535:_status("closed","PORT MUST BE 1024 TO 65535");return false
    if Protocol.fingerprint().length()!=64:_status("closed","NETWORK BUILD IS NOT READY");return false
    peer=ENetMultiplayerPeer.new()
    var error: Error=peer.create_server(port,1,3)
    if error!=OK:peer=null;_status("closed","CANNOT HOST ON THIS PORT");return false
    _prepare();_status("hosting","WAITING FOR PLAYER TWO");return true

func join_game(address: String, port: int, colour: int) -> bool:
    close();authority=false;local_actor=2;colours=[0,clampi(colour,0,3)]
    if address.strip_edges().is_empty() or address.length()>100 or port<1024 or port>65535:_status("closed","CHECK ADDRESS AND PORT");return false
    if Protocol.fingerprint().length()!=64:_status("closed","NETWORK BUILD IS NOT READY");return false
    peer=ENetMultiplayerPeer.new()
    var error: Error=peer.create_client(address.strip_edges(),port,3)
    if error!=OK:peer=null;_status("closed","CANNOT CONNECT TO THIS ADDRESS");return false
    _prepare();_status("joining","CONNECTING TO HOST");return true

func _prepare() -> void:
    session=Session.new(rules,authority);remote=0;local_ready=false;remote_ready=false;local_sequence=0;hello_sent=false;received_ticks.clear()
    last_packet_ms=Time.get_ticks_msec();last_heartbeat_ms=last_packet_ms;pending_failure=""
    peer.peer_connected.connect(_connected)
    peer.peer_disconnected.connect(_disconnected)

func _connected(id: int) -> void:
    if authority:
        if remote==0:remote=id;last_packet_ms=Time.get_ticks_msec()
    elif id==1:remote=1

func _disconnected(id: int) -> void:
    if id==remote or not authority:pending_failure="OPPONENT DISCONNECTED"

func send(kind: String, body: Dictionary = {}, channel: int = 0) -> void:
    if peer==null or remote==0 or peer.get_connection_status()!=MultiplayerPeer.CONNECTION_CONNECTED:return
    var packet: PackedByteArray=Protocol.encode({"type":kind,"body":body})
    if packet.size()>Protocol.MAX_PACKET:_fail("DUEL DATA IS TOO LARGE");return
    peer.set_target_peer(remote);peer.transfer_channel=channel
    peer.transfer_mode=MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED if channel in [1,2] else MultiplayerPeer.TRANSFER_MODE_RELIABLE
    peer.put_packet(packet)

func poll() -> void:
    if peer==null:return
    peer.poll()
    if not pending_failure.is_empty():
        var message: String=pending_failure;pending_failure="";_fail(message);return
    if peer==null:return
    if not authority and not hello_sent and peer.get_connection_status()==MultiplayerPeer.CONNECTION_CONNECTED:
        remote=1;hello_sent=true
        send("hello",{"protocol":Protocol.VERSION,"build":Protocol.fingerprint(),"colour":colours[1]})
    var count: int=0
    while peer!=null and peer.get_available_packet_count()>0 and count<128:
        count+=1
        var sender: int=peer.get_packet_peer()
        var packet: Dictionary=Protocol.decode(peer.get_packet())
        if sender!=remote:continue
        if packet.is_empty() or typeof(packet.get("type"))!=TYPE_STRING or typeof(packet.get("body"))!=TYPE_DICTIONARY:_fail("INVALID DUEL DATA");return
        last_packet_ms=Time.get_ticks_msec()
        receive(packet.type,packet.body)
    if peer==null:return
    var now: int=Time.get_ticks_msec()
    if (state=="joining" or (state=="hosting" and remote!=0)) and (now-last_packet_ms>10000 or peer.get_connection_status()==MultiplayerPeer.CONNECTION_DISCONNECTED):_fail("HOST COULD NOT BE REACHED");return
    if state in ["waiting","playing","ended"] and now-last_packet_ms>5000:_fail("CONNECTION TIMED OUT");return
    if remote!=0 and now-last_heartbeat_ms>500:
        last_heartbeat_ms=now
        if authority and state in ["playing","ended"]:send("frame",session.frame())
        else:send("ping",{"round":session.round_id})

func receive(kind: String, body: Dictionary) -> void:
    if kind=="bye":_fail("OPPONENT LEFT THE DUEL");return
    if kind=="reject":_fail("MATCHING GAME BUILDS REQUIRED");return
    if kind=="ping":return
    if authority:
        if kind=="hello" and state=="hosting":
            if body.get("protocol")!=Protocol.VERSION or body.get("build")!=Protocol.fingerprint() or typeof(body.get("colour"))!=TYPE_INT or body.colour<0 or body.colour>3:
                send("reject");_fail("MATCHING GAME BUILDS REQUIRED");return
            colours[1]=body.colour if body.colour!=colours[0] else (body.colour+1)%4
            _status("waiting","ENTER WHEN READY")
            send("welcome",{"protocol":Protocol.VERSION,"build":Protocol.fingerprint(),"colours":colours,"frame":session.frame()})
        elif kind=="ready" and state in ["waiting","ended"] and body.get("round")==session.round_id:
            remote_ready=true;changed.emit();_try_start()
        elif kind=="input" and state=="playing":
            if not session.submit(2,body):invalid_inputs+=1
            elif session.simulation.tick-int(body.seen)>250:_fail("CONNECTION IS TOO FAR BEHIND")
    else:
        if kind=="welcome" and state=="joining":
            if body.get("protocol")!=Protocol.VERSION or body.get("build")!=Protocol.fingerprint() or not _colours(body.get("colours")) or typeof(body.get("frame"))!=TYPE_DICTIONARY or not session.accept_frame(body.frame,true):_fail("MATCHING GAME BUILDS REQUIRED");return
            colours=body.colours.duplicate();_status("waiting","ENTER WHEN READY");frame_received.emit()
        elif kind=="start" and state in ["waiting","ended"]:
            if typeof(body.get("round"))!=TYPE_INT or body.round not in [session.round_id,session.round_id+1]:return
            if body.round!=session.round_id:session.begin(body.round)
            if not session.accept_frame(body,true):_fail("INVALID ROUND STATE");return
            local_ready=false;remote_ready=false;local_sequence=0
            _status("playing","");frame_received.emit();fight_started.emit()
        elif kind=="frame" and state in ["playing","ended"]:
            if body.get("round")!=session.round_id:return
            if typeof(body.get("state"))!=TYPE_DICTIONARY:_fail("INVALID HOST STATE");return
            if typeof(body.state.get("tick"))!=TYPE_INT:_fail("INVALID HOST STATE");return
            if body.state.tick<=session.simulation.tick:return
            if not session.accept_frame(body):_fail("INVALID HOST STATE");return
            received_ticks.append(session.simulation.tick)
            if received_ticks.size()>256:received_ticks.pop_front()
            frame_received.emit()
            if session.settled and state!="ended":local_ready=false;remote_ready=false;_status("ended","ROUND FINISHED")
        elif kind=="ready" and state in ["waiting","ended"] and body.get("round")==session.round_id:remote_ready=true;changed.emit()

func _colours(value: Variant) -> bool:
    return typeof(value)==TYPE_ARRAY and value.size()==2 and typeof(value[0])==TYPE_INT and typeof(value[1])==TYPE_INT and value[0]>=0 and value[0]<=3 and value[1]>=0 and value[1]<=3 and value[0]!=value[1]

func ready() -> void:
    if state not in ["waiting","ended"] or local_ready:return
    local_ready=true;send("ready",{"round":session.round_id});changed.emit()
    if authority:_try_start()

func _try_start() -> void:
    if not local_ready or not remote_ready:return
    if state=="ended":session.begin(session.round_id+1)
    local_ready=false;remote_ready=false;local_sequence=0
    _status("playing","");send("start",session.frame());frame_received.emit();fight_started.emit()

func advance(direction: Vector2i, action: String) -> void:
    poll()
    if state!="playing":return
    local_sequence+=1
    var input: Dictionary={"round":session.round_id,"sequence":local_sequence,"dx":direction.x,"dy":direction.y,"action":action,"seen":session.simulation.tick}
    if authority:
        session.submit(1,input)
        session.step()
        send("frame",session.frame(),0 if session.settled else 2);frame_received.emit()
        if session.settled:local_ready=false;remote_ready=false;_status("ended","ROUND FINISHED")
    else:send("input",input,1)

func _fail(message: String) -> void:
    if peer!=null:
        if peer.get_connection_status()!=MultiplayerPeer.CONNECTION_DISCONNECTED:peer.host.flush()
        peer.close();peer=null
    _status("closed",message)

func close() -> void:
    if peer!=null:
        send("bye")
        if peer.get_connection_status()!=MultiplayerPeer.CONNECTION_DISCONNECTED:peer.host.flush()
        peer.close();peer=null
    state="idle";remote=0
