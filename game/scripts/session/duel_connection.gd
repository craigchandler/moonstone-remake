extends RefCounted

# Every player is a client. Hosting optionally owns the same independent runner
# used by the command-line server; screens never advance authority themselves.
signal changed
signal fight_started
signal frame_received
const Session=preload("res://scripts/session/network_duel_session.gd")
const Protocol=preload("res://scripts/session/duel_protocol.gd")
const Runner=preload("res://scripts/session/duel_host_runner.gd")
const DEFAULT_PORT: int=27866
var rules: Resource
var peer: ENetMultiplayerPeer
var session: RefCounted
var host_runtime: Node
var authority: bool=false
var remote: int=0
var local_actor: int=2
var colours: Array=[0,1]
var state: String="idle"
var notice: String="HOST OR JOIN A DUEL"
var local_ready: bool=false
var remote_ready: bool=false
var local_sequence: int=0
var last_packet_ms: int=0
var last_heartbeat_ms: int=0
var hello_sent: bool=false
var received_ticks: Array[int]=[]
var pending_failure: String=""
var invalid_inputs: int:
    get:return host_runtime.host.invalid_inputs if host_runtime!=null else 0

func _init(rule_set: Resource) -> void:rules=rule_set
func _status(next: String,message: String) -> void:state=next;notice=message;changed.emit()

func host_game(port: int,colour: int) -> bool:
    close();authority=true;local_actor=1;colours=[clampi(colour,0,3),(colour+1)%4]
    if port<1024 or port>65535:_status("closed","PORT MUST BE 1024 TO 65535");return false
    if Protocol.fingerprint().length()!=64:_status("closed","NETWORK BUILD IS NOT READY");return false
    host_runtime=Runner.new(rules)
    if not host_runtime.host.listen(port):host_runtime.free();host_runtime=null;_status("closed","CANNOT HOST ON THIS PORT");return false
    Engine.get_main_loop().root.add_child(host_runtime)
    if not _connect("127.0.0.1",port):close();_status("closed","CANNOT CONNECT TO THIS ADDRESS");return false
    # The embedded player keeps seat1 even if a remote hello arrives first.
    host_runtime.host.reserved_peer=peer.get_unique_id()
    _status("hosting","WAITING FOR PLAYER TWO");return true

func join_game(address: String,port: int,colour: int) -> bool:
    close();authority=false;local_actor=2;colours=[0,clampi(colour,0,3)]
    if address.strip_edges().is_empty() or address.length()>100 or port<1024 or port>65535:_status("closed","CHECK ADDRESS AND PORT");return false
    if Protocol.fingerprint().length()!=64:_status("closed","NETWORK BUILD IS NOT READY");return false
    if not _connect(address.strip_edges(),port):_status("closed","CANNOT CONNECT TO THIS ADDRESS");return false
    _status("joining","CONNECTING TO HOST");return true

func _connect(address: String,port: int) -> bool:
    peer=ENetMultiplayerPeer.new()
    if peer.create_client(address,port,3)!=OK:peer=null;return false
    session=Session.new(rules,false);remote=1;local_ready=false;remote_ready=false;local_sequence=0;hello_sent=false;received_ticks.clear()
    last_packet_ms=Time.get_ticks_msec();last_heartbeat_ms=last_packet_ms;pending_failure=""
    peer.peer_disconnected.connect(_disconnected)
    return true

func _disconnected(_id: int) -> void:pending_failure="OPPONENT DISCONNECTED"

func send(kind: String,body: Dictionary={},channel: int=0) -> void:
    if peer==null or peer.get_connection_status()!=MultiplayerPeer.CONNECTION_CONNECTED:return
    var packet: PackedByteArray=Protocol.encode({"type":kind,"body":body})
    if packet.size()>Protocol.MAX_PACKET:_fail("DUEL DATA IS TOO LARGE");return
    peer.set_target_peer(1);peer.transfer_channel=channel
    peer.transfer_mode=MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED if channel==1 else MultiplayerPeer.TRANSFER_MODE_RELIABLE
    peer.put_packet(packet)

func poll() -> void:
    if peer==null:return
    peer.poll()
    if not hello_sent and peer.get_connection_status()==MultiplayerPeer.CONNECTION_CONNECTED:
        hello_sent=true
        send("hello",{"protocol":Protocol.VERSION,"build":Protocol.fingerprint(),"colour":colours[0] if authority else colours[1]})
    var count: int=0
    while peer!=null and peer.get_available_packet_count()>0 and count<128:
        count+=1
        var sender: int=peer.get_packet_peer()
        var packet: Dictionary=Protocol.decode(peer.get_packet())
        if sender!=1:continue
        if packet.is_empty() or typeof(packet.get("type"))!=TYPE_STRING or typeof(packet.get("body"))!=TYPE_DICTIONARY:_fail("INVALID DUEL DATA");return
        last_packet_ms=Time.get_ticks_msec();receive(packet.type,packet.body)
    if peer==null:return
    if not pending_failure.is_empty():
        var message: String=pending_failure;pending_failure="";_fail(message);return
    var now: int=Time.get_ticks_msec()
    if state in ["joining","hosting"] and (now-last_packet_ms>10000 or peer.get_connection_status()==MultiplayerPeer.CONNECTION_DISCONNECTED):_fail("HOST COULD NOT BE REACHED");return
    if state in ["seated","waiting","playing","ended"] and now-last_packet_ms>5000:_fail("CONNECTION TIMED OUT");return
    if now-last_heartbeat_ms>500:last_heartbeat_ms=now;send("ping")

func receive(kind: String,body: Dictionary) -> void:
    if kind=="error":
        _fail(body.message if typeof(body.get("message"))==TYPE_STRING and body.message.length()<=80 else "INVALID DUEL DATA");return
    if kind=="ping":return
    if kind in ["seat","welcome"] and state in ["joining","hosting","seated"]:
        if body.get("protocol")!=Protocol.VERSION or body.get("build")!=Protocol.fingerprint() or typeof(body.get("actor"))!=TYPE_INT or body.actor not in [1,2] or not _colours(body.get("colours")) or typeof(body.get("frame"))!=TYPE_DICTIONARY or not session.accept_frame(body.frame,true):_fail("MATCHING GAME BUILDS REQUIRED");return
        local_actor=body.actor;colours=body.colours.duplicate()
        _status("waiting" if kind=="welcome" else "seated","ENTER WHEN READY" if kind=="welcome" else "WAITING FOR AN OPPONENT")
        frame_received.emit()
    elif kind=="start" and state in ["waiting","ended"]:
        if typeof(body.get("round"))!=TYPE_INT or body.round not in [session.round_id,session.round_id+1]:return
        if body.round!=session.round_id:session.begin(body.round)
        if not session.accept_frame(body,true):_fail("INVALID ROUND STATE");return
        local_ready=false;remote_ready=false;local_sequence=0
        _status("playing","");frame_received.emit();fight_started.emit()
    elif kind=="frame" and state in ["playing","ended"]:
        if body.get("round")!=session.round_id:return
        if typeof(body.get("state"))!=TYPE_DICTIONARY or typeof(body.state.get("tick"))!=TYPE_INT:_fail("INVALID HOST STATE");return
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
func advance(direction: Vector2i,action: String) -> void:
    poll()
    if state!="playing":return
    local_sequence+=1
    send("input",{"round":session.round_id,"sequence":local_sequence,"dx":direction.x,"dy":direction.y,"action":action,"seen":session.simulation.tick},1)
func _drop() -> void:
    if peer!=null:
        if peer.get_connection_status()!=MultiplayerPeer.CONNECTION_DISCONNECTED:peer.host.flush()
        peer.close();peer=null
    if host_runtime!=null:
        host_runtime.stop("OPPONENT LEFT THE DUEL");host_runtime.queue_free();host_runtime=null
    remote=0
func _fail(message: String) -> void:_drop();_status("closed",message)
func close() -> void:send("bye");_drop();state="idle"
