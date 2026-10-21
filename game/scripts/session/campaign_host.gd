extends RefCounted
signal changed
const Session=preload("res://scripts/session/campaign_session.gd")
const ReadModel=preload("res://scripts/session/campaign_projection.gd")
const Protocol=preload("res://scripts/session/campaign_protocol.gd")
const Store=preload("res://scripts/session/campaign_store.gd")
var session: RefCounted
var peer: ENetMultiplayerPeer
var store: RefCounted
var room: String=""
var run_id: String=Crypto.new().generate_random_bytes(16).hex_encode()
var human_count: int=2
var seed_value: int=1
var state: String="closed"
var notice: String=""
var started: bool=false
var clients: Dictionary={}
var seats: Dictionary={}
var credentials: Dictionary={}
var ready_players: Dictionary={}
var live_peers: Dictionary={}
var pending_disconnects: Array[int]=[]
var listen_port: int=0
var reset_at: int=0
var heartbeat: int=0
var bytes_sent: int=0
var invalid_inputs: int=0
var last_save_revision: int=-1
var last_map_tick: int=-1
var old_stage: String=""

func _init(count: int=2,seed: int=1,save_path: String="") -> void:
    human_count=clampi(count,1,4);seed_value=seed;session=Session.new(seed,range(human_count));store=Store.new(save_path)
    room=Crypto.new().generate_random_bytes(16).hex_encode()
    if not save_path.is_empty() and (FileAccess.file_exists(save_path) or FileAccess.file_exists(save_path+".bak")):
        var saved: Dictionary=store.load_room(session.journey.validate_checkpoint)
        if saved.is_empty():notice="CANNOT LOAD THIS NETWORK CAMPAIGN";return
        session.journey.restore_checkpoint(saved.checkpoint)
        room=saved.room
        for key in saved.credentials:credentials[int(key)]=saved.credentials[key]
        human_count=session.journey.human_players;started=true;session.set_paused(true);session.sync_phase()

func listen(port: int) -> bool:
    if not notice.is_empty() or port<1024 or port>65535 or Protocol.fingerprint().length()!=64:return false
    listen_port=port
    return _open()
func _open() -> bool:
    peer=ENetMultiplayerPeer.new()
    if peer.create_server(listen_port,8,4)!=OK:peer=null;state="closed";notice="CANNOT OPEN CAMPAIGN PORT";return false
    peer.peer_connected.connect(_connected);peer.peer_disconnected.connect(_disconnected)
    state="paused" if started else "lobby";heartbeat=Time.get_ticks_msec();reset_at=0;changed.emit();return true
func _connected(id: int) -> void:
    clients[id]={"seat":-1,"last":Time.get_ticks_msec(),"rejected":false};live_peers[id]=true
func _disconnected(id: int) -> void:live_peers.erase(id);pending_disconnects.append(id)
func send(id: int,kind: String,body: Dictionary={},channel: int=0) -> void:
    if peer==null or not clients.has(id) or not live_peers.has(id):return
    var packet: PackedByteArray=Protocol.encode({"type":kind,"body":body})
    if packet.size()>Protocol.MAX_PACKET:notice="CAMPAIGN UPDATE TOO LARGE";return
    peer.set_target_peer(id);peer.transfer_channel=channel
    peer.transfer_mode=MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED if channel>0 else MultiplayerPeer.TRANSFER_MODE_RELIABLE
    peer.put_packet(packet);bytes_sent+=packet.size()
func broadcast(kind: String,body: Dictionary,channel: int) -> void:
    # Shared state is encoded once, then sent to each player. Personal views
    # remain separate. Avoid repeating serialization/compression four times.
    var packet: PackedByteArray=Protocol.encode({"type":kind,"body":body})
    if packet.size()>Protocol.MAX_PACKET:return
    for id in seats.values():
        if not live_peers.has(id):continue
        peer.set_target_peer(id);peer.transfer_channel=channel
        peer.transfer_mode=MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
        peer.put_packet(packet);bytes_sent+=packet.size()
func status() -> Dictionary:
    var roster: Array=[]
    for seat in range(4):roster.append({"connected":seats.has(seat),"reserved":credentials.has(seat),"ready":bool(ready_players.get(seat,false))})
    return {"state":state,"room":room,"count":human_count,"started":started,"seats":roster,"notice":notice}
func announce() -> void:
    for id in seats.values():send(id,"status",status())
    changed.emit()
func views() -> void:
    if not started:announce();return
    for seat in seats:send(seats[seat],"view",ReadModel.view(session,seat))
    announce()
func pause(message: String) -> void:
    if not started:return
    session.set_paused(true);state="paused";notice=message;ready_players.clear();views();save()
func _reset_transport(message: String) -> void:
    if reset_at>0:return
    if started:pause(message)
    for id in seats.values():send(id,"reconnect",{"message":message})
    if peer!=null:peer.host.flush()
    reset_at=Time.get_ticks_msec()+100
func _retire() -> void:
    if peer!=null:peer.close();peer=null
    clients.clear();seats.clear();live_peers.clear();pending_disconnects.clear();ready_players.clear()
func poll() -> void:
    if peer==null:return
    if reset_at>0:
        if Time.get_ticks_msec()>=reset_at:_retire();_open()
        return
    peer.poll()
    for id in pending_disconnects:
        if clients.has(id) and clients[id].seat>=0:_reset_transport("PLAYER DISCONNECTED - SEAT RESERVED");return
        clients.erase(id)
    pending_disconnects.clear()
    var count: int=0
    while peer!=null and peer.get_available_packet_count()>0 and count<256:
        count+=1
        var id: int=peer.get_packet_peer()
        var packet: Dictionary=Protocol.decode(peer.get_packet())
        if not clients.has(id):continue
        if not Protocol.packet(packet):invalid_inputs+=1;continue
        clients[id].last=Time.get_ticks_msec()
        receive(id,packet.type,packet.body)
        if reset_at>0:return
    var now: int=Time.get_ticks_msec()
    for id in clients.keys():
        var client: Dictionary=clients[id]
        var age: int=now-int(client.last)
        if client.seat>=0:
            if age>5000:_reset_transport("CONNECTION LOST - SEAT RESERVED");return
            if started and state=="playing" and age>1500:pause("CONNECTION STALLED - WAITING FOR PLAYER")
        elif age>5000:
            peer.disconnect_peer(id);clients.erase(id);live_peers.erase(id)
    if now-heartbeat>=500:
        heartbeat=now;announce()
func receive(id: int,kind: String,body: Dictionary) -> void:
    var client: Dictionary=clients[id]
    if kind=="ping":return
    if kind=="hello":
        if client.seat>=0:return
        if body.size()!=5 or not Protocol.integer(body.get("kind"),0,3) or typeof(body.get("token"))!=TYPE_STRING or typeof(body.get("room"))!=TYPE_STRING:invalid_inputs+=1;return
        if body.get("protocol")!=Protocol.VERSION or body.get("build")!=Protocol.fingerprint():send(id,"error",{"message":"MATCHING CAMPAIGN BUILDS REQUIRED"});return
        var seat: int=-1
        var token: String=""
        if typeof(body.get("token"))==TYPE_STRING and body.token.length()==64 and body.token.is_valid_hex_number(false):
            for key in credentials:
                if credentials[key]==body.token.sha256_text() and not seats.has(key):seat=int(key);token=body.token;break
        if seat<0 and not started and seats.size()<human_count:
            var desired: int=int(body.get("kind",0)) if Protocol.integer(body.get("kind"),0,3) else 0
            for offset in range(4):
                var candidate: int=(desired+offset)%4
                if not seats.has(candidate) and not credentials.has(candidate):seat=candidate;break
            if seat>=0:token=Crypto.new().generate_random_bytes(32).hex_encode();credentials[seat]=token.sha256_text()
        if seat<0:
            if started and body.room!=room:send(id,"identify",{"protocol":Protocol.VERSION,"build":Protocol.fingerprint(),"room":room})
            else:send(id,"error",{"message":"THIS KNIGHT IS RESERVED OR THE GAME IS FULL"})
            return
        client.seat=seat;seats[seat]=id;ready_players[seat]=false
        send(id,"welcome",{"protocol":Protocol.VERSION,"build":Protocol.fingerprint(),"room":room,"run":run_id,"seat":seat,"token":token,"commands":int(session.command_sequences.get(seat,0)),"inputs":int(session.input_sequences.get(seat,0)),"status":status()})
        if started:send(id,"view",ReadModel.view(session,seat))
        announce();return
    var seat: int=int(client.seat)
    if seat<0:return
    if kind=="leave":_reset_transport("PLAYER LEFT - SEAT RESERVED");return
    if kind=="ready":
        if state not in ["lobby","paused"] or seats.size()!=human_count:return
        ready_players[seat]=true
        if ready_players.size()==human_count and ready_players.values().all(func(value):return value):
            if not started:
                session=Session.new(seed_value,seats.keys());started=true
            session.set_paused(false);state="playing";notice="";ready_players.clear();save();views()
        else:announce()
        return
    if not started or state!="playing":return
    if kind=="command":
        if body.size()!=4 or not Protocol.integer(body.get("sequence"),1,0x7fffffff) or not Protocol.integer(body.get("epoch"),1,0x7fffffff) or typeof(body.get("action"))!=TYPE_STRING or typeof(body.get("args"))!=TYPE_DICTIONARY:invalid_inputs+=1;return
        var reply: Dictionary=session.command(seat,body.sequence,body.epoch,body.action,body.args)
        reply.sequence=body.sequence;send(id,"ack",reply);save();views()
    elif kind=="input":
        if body.size()!=5 or not Protocol.integer(body.get("sequence"),1,0x7fffffff) or not Protocol.integer(body.get("epoch"),1,0x7fffffff) or not Protocol.integer(body.get("dx"),-1,1) or not Protocol.integer(body.get("dy"),-1,1) or typeof(body.get("action"))!=TYPE_STRING:invalid_inputs+=1;return
        if not session.input(seat,body.sequence,body.epoch,Vector2i(body.dx,body.dy),body.action):invalid_inputs+=1
func advance() -> void:
    if not started or state!="playing" or reset_at>0:return
    var changed_phase: bool=session.advance()
    if session.tick%100==0 and session.phase() in ["map","computer"]:save()
    if changed_phase:save();views()
    elif session.phase() in ["battle","result"]:
        broadcast("combat",ReadModel.combat(session),2)
    elif session.tick%2==0 and session.phase() in ["map","computer","town","henge","quest","ending"]:
        var frame: Dictionary=ReadModel.map_frame(session)
        broadcast("map",frame,1)
func save() -> bool:
    if not started or store.path.is_empty():return true
    var result: bool=store.save_room({"room":room,"credentials":credentials.duplicate(true),"checkpoint":session.safe_checkpoint()},session.journey.validate_checkpoint)
    if not result:notice=store.notice
    return result
func close() -> void:
    save()
    if peer!=null:
        for id in seats.values():send(id,"reconnect",{"message":"HOST STOPPED - CAMPAIGN SAVED"})
        peer.host.flush()
    _retire();state="closed"
