extends RefCounted

# One room owns all authoritative state. It has no local player or presentation.
signal changed
const Session=preload("res://scripts/session/network_duel_session.gd")
const Protocol=preload("res://scripts/session/duel_protocol.gd")
var rules: Resource
var peer: ENetMultiplayerPeer
var session: RefCounted
var state: String="closed"
var clients: Dictionary={}
var live_peers: Dictionary={}
var listen_port: int=0
var reset_at_ms: int=0
var seats: Dictionary={}
var colours: Array=[0,1]
var ready_players: Dictionary={1:false,2:false}
var reserved_peer: int=0
var pending_disconnects: Array[int]=[]
var last_heartbeat_ms: int=0
var invalid_inputs: int=0
var completed_rounds: int=0

func _init(rule_set: Resource) -> void:rules=rule_set

func listen(port: int) -> bool:
    close()
    if port<1024 or port>65535 or Protocol.fingerprint().length()!=64:return false
    peer=ENetMultiplayerPeer.new()
    if peer.create_server(port,2,3)!=OK:peer=null;return false
    session=Session.new(rules,true);clients.clear();seats.clear();ready_players={1:false,2:false}
    colours=[0,1];reserved_peer=0;pending_disconnects.clear();invalid_inputs=0;completed_rounds=0
    listen_port=port;reset_at_ms=0
    last_heartbeat_ms=Time.get_ticks_msec()
    peer.peer_connected.connect(_connected);peer.peer_disconnected.connect(_disconnected)
    state="listening";changed.emit();return true

func _connected(id: int) -> void:
    live_peers[id]=true
    clients[id]={"seat":0,"colour":0,"last_packet_ms":Time.get_ticks_msec()}

func _disconnected(id: int) -> void:
    live_peers.erase(id);pending_disconnects.append(id)

func send(id: int,kind: String,body: Dictionary={},channel: int=0) -> void:
    if peer==null or not clients.has(id) or not live_peers.has(id):return
    peer.set_target_peer(id);peer.transfer_channel=channel
    peer.transfer_mode=MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED if channel==2 else MultiplayerPeer.TRANSFER_MODE_RELIABLE
    peer.put_packet(Protocol.encode({"type":kind,"body":body}))

func broadcast(kind: String,body: Dictionary={},channel: int=0) -> void:
    for id in seats.values():send(id,kind,body,channel)

func poll() -> void:
    if peer==null:return
    if state=="resetting":
        if Time.get_ticks_msec()>=reset_at_ms:_reopen()
        return
    peer.poll()
    # Native callbacks only queue work; never close a peer inside its own poll.
    for id in pending_disconnects:
        if clients.has(id):_abort("OPPONENT DISCONNECTED");return
    pending_disconnects.clear()
    var count: int=0
    while peer!=null and peer.get_available_packet_count()>0 and count<128:
        count+=1
        var sender: int=peer.get_packet_peer()
        var packet: Dictionary=Protocol.decode(peer.get_packet())
        if not clients.has(sender):continue
        if packet.is_empty() or typeof(packet.get("type"))!=TYPE_STRING or typeof(packet.get("body"))!=TYPE_DICTIONARY:_abort("INVALID DUEL DATA");return
        clients[sender].last_packet_ms=Time.get_ticks_msec()
        receive(sender,packet.type,packet.body)
    if peer==null:return
    var now: int=Time.get_ticks_msec()
    for client in clients.values():
        if now-int(client.last_packet_ms)>(10000 if int(client.seat)==0 else 5000):
            _abort("HOST COULD NOT BE REACHED" if int(client.seat)==0 else "CONNECTION TIMED OUT");return
    if now-last_heartbeat_ms>500:
        last_heartbeat_ms=now
        if state in ["playing","ended"]:broadcast("frame",session.frame())
        else:broadcast("ping")

func receive(sender: int,kind: String,body: Dictionary) -> void:
    var client: Dictionary=clients[sender]
    if kind=="bye":_abort("OPPONENT LEFT THE DUEL");return
    if kind=="ping":return
    if kind=="hello" and int(client.seat)==0:
        if state!="listening" or body.get("protocol")!=Protocol.VERSION or body.get("build")!=Protocol.fingerprint() or typeof(body.get("colour"))!=TYPE_INT or body.colour<0 or body.colour>3:
            _abort("MATCHING GAME BUILDS REQUIRED");return
        var seat: int=1 if sender==reserved_peer else (2 if reserved_peer!=0 else (1 if not seats.has(1) else 2))
        if seats.has(seat):_abort("DUEL IS FULL");return
        seats[seat]=sender;client.seat=seat;client.colour=body.colour;colours[seat-1]=body.colour
        if colours[0]==colours[1]:colours[2-seat]=(body.colour+1)%4
        if seats.size()==2:
            # Resolve colours by stable seat, independent of hello arrival order.
            colours=[clients[seats[1]].colour,clients[seats[2]].colour]
            if colours[0]==colours[1]:colours[1]=(colours[1]+1)%4
            state="waiting"
            for actor in [1,2]:_welcome(seats[actor],"welcome")
        else:_welcome(sender,"seat")
        changed.emit();return
    if int(client.seat)==0:return
    var actor: int=client.seat
    if kind=="ready" and state in ["waiting","ended"]:
        if typeof(body.get("round"))!=TYPE_INT or body.round!=session.round_id:return
        ready_players[actor]=true
        send(seats[3-actor],"ready",{"round":session.round_id})
        if ready_players[1] and ready_players[2]:
            if state=="ended":session.begin(session.round_id+1)
            ready_players={1:false,2:false};state="playing"
            broadcast("start",session.frame())
        changed.emit()
    elif kind=="input" and state=="playing":
        if not session.submit(actor,body):invalid_inputs+=1
        elif session.simulation.tick-int(body.seen)>250:_abort("CONNECTION IS TOO FAR BEHIND")

func _welcome(id: int,kind: String) -> void:
    send(id,kind,{"protocol":Protocol.VERSION,"build":Protocol.fingerprint(),"actor":clients[id].seat,"colours":colours,"frame":session.frame()})

func advance() -> void:
    if state!="playing":return
    session.step()
    broadcast("frame",session.frame(),0 if session.settled else 2)
    if session.settled:
        completed_rounds+=1;ready_players={1:false,2:false};state="ended";changed.emit()

func _abort(message: String) -> void:
    for id in clients:send(id,"error",{"message":message})
    if peer!=null:peer.host.flush()
    clients.clear();seats.clear();ready_players={1:false,2:false};pending_disconnects.clear()
    session=Session.new(rules,true)
    # Retire the whole transport after the notice grace. Godot 4.6.1 keeps
    # acknowledged native disconnects alive; its per-peer forced cleanup also
    # removes a list entry before following that entry's next pointer. A fresh
    # listener avoids polling either retired peer and contains abandoned input.
    reset_at_ms=Time.get_ticks_msec()+100
    state="resetting";changed.emit()

func _reopen() -> void:
    peer.close();peer=ENetMultiplayerPeer.new()
    live_peers.clear();reserved_peer=0;reset_at_ms=0
    if peer.create_server(listen_port,2,3)!=OK:
        peer=null;state="closed";changed.emit();return
    peer.peer_connected.connect(_connected);peer.peer_disconnected.connect(_disconnected)
    last_heartbeat_ms=Time.get_ticks_msec()
    state="listening";changed.emit()

func close(message: String="SERVER STOPPED") -> void:
    if peer!=null:
        for id in clients:send(id,"error",{"message":message})
        if peer.get_connection_status()!=MultiplayerPeer.CONNECTION_DISCONNECTED:peer.host.flush()
        peer.close();peer=null
    clients.clear();seats.clear();live_peers.clear();pending_disconnects.clear();reset_at_ms=0;state="closed"
