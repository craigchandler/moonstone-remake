extends RefCounted
signal changed
signal frame_received
signal fight_started
const Runner=preload("res://scripts/session/campaign_host_runner.gd")
const Protocol=preload("res://scripts/session/campaign_protocol.gd")
const Replica=preload("res://scripts/session/campaign_journey_replica.gd")
const Runtime=preload("res://scripts/session/runtime_mode.gd")
const DEFAULT_PORT: int=27867
var peer: ENetMultiplayerPeer
var host_runtime: Node
var replica: RefCounted
var own_inventory: RefCounted
var state: String="idle"
var notice: String="HOST OR JOIN A CAMPAIGN"
var seat: int=-1
var room: String=""
var token: String=""
var address: String="127.0.0.1"
var port: int=DEFAULT_PORT
var knight_kind: int=0
var roster: Dictionary={}
var epoch: int=1
var command_sequence: int=0
var input_sequence: int=0
var last_packet: int=0
var last_ping: int=0
var next_retry: int=0
var hello_sent: bool=false
var view_received: bool=false
var phase: String=""
var pending_failure: bool=false
var last_ack: Dictionary={}
var profile_path: String="user://network-campaign-connections.cfg"
var last_host_path: String=""
var latest: Dictionary={}
var pending_inputs: Array=[]
var seen_feedback: Dictionary={}
var latest_tick: int=-1
var latest_revision: int=0
var newest_frame: Dictionary={}
var requested_reconnect: bool=false
var host_run: String=""

func _init() -> void:
    replica=Replica.new();replica.connection=self
    own_inventory=Replica.new();own_inventory.connection=self;own_inventory.read_only=true
func _key() -> String:return address+":"+str(port)
func load_profile() -> void:
    if profile_path.is_empty() or Runtime.debug_enabled():return
    var config:=ConfigFile.new()
    if config.load(profile_path)!=OK:return
    var value: Variant=config.get_value("connections",_key(),{})
    if typeof(value)==TYPE_DICTIONARY and typeof(value.get("token"))==TYPE_STRING and value.token.length()==64:
        token=value.token;room=str(value.get("room",""))
func save_profile() -> void:
    if profile_path.is_empty() or Runtime.debug_enabled():return
    var config:=ConfigFile.new();config.load(profile_path)
    config.set_value("connections",_key(),{"token":token,"room":room})
    config.set_value("rooms",room,token)
    if not last_host_path.is_empty():config.set_value("hosts",_key(),last_host_path)
    config.save(profile_path)
func host_game(listen_port: int,kind: int,count: int=2,resume: bool=false) -> bool:
    close();address="127.0.0.1";port=listen_port;knight_kind=kind
    if listen_port<1024 or listen_port>65535 or count<1 or count>4:return false
    token="";room=""
    var saved_path: String=""
    if resume and not profile_path.is_empty() and not Runtime.debug_enabled():
        var config:=ConfigFile.new()
        if config.load(profile_path)==OK:
            saved_path=str(config.get_value("hosts",_key(),""))
    if resume and saved_path.is_empty():notice="NO HOSTED CAMPAIGN TO RESUME";changed.emit();return false
    last_host_path=saved_path if resume else "user://network-campaigns/"+Crypto.new().generate_random_bytes(16).hex_encode()+".json"
    if resume:load_profile()
    host_runtime=Runner.new(count,_seed(),last_host_path)
    if not host_runtime.host.listen(port):notice=host_runtime.host.notice;host_runtime.free();host_runtime=null;changed.emit();return false
    Engine.get_main_loop().root.add_child(host_runtime)
    return _connect()
func _seed() -> int:
    var rng:=RandomNumberGenerator.new();rng.randomize();return rng.randi_range(2,0x7fffffff)
func join_game(host: String,listen_port: int,kind: int) -> bool:
    close();address=host.strip_edges();port=listen_port;knight_kind=kind;last_host_path=""
    if address.is_empty() or address.length()>100 or port<1024 or port>65535:return false
    token="";room="";load_profile()
    return _connect()
func _connect() -> bool:
    if Protocol.fingerprint().length()!=64:notice="CAMPAIGN BUILD IS NOT READY";state="closed";changed.emit();return false
    peer=ENetMultiplayerPeer.new()
    if peer.create_client(address,port,4)!=OK:peer=null;state="closed";notice="CANNOT CONNECT TO CAMPAIGN";changed.emit();return false
    peer.peer_disconnected.connect(func(_id: int) -> void:pending_failure=true)
    hello_sent=false;pending_failure=false;last_packet=Time.get_ticks_msec();last_ping=last_packet
    state="joining";notice="CONNECTING TO CAMPAIGN";changed.emit();return true
func send(kind: String,body: Dictionary={},channel: int=0) -> void:
    if peer==null or peer.get_connection_status()!=MultiplayerPeer.CONNECTION_CONNECTED:return
    var packet: PackedByteArray=Protocol.encode({"type":kind,"body":body})
    if packet.size()>Protocol.MAX_PACKET:return
    peer.set_target_peer(1);peer.transfer_channel=channel
    peer.transfer_mode=MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED if channel>0 else MultiplayerPeer.TRANSFER_MODE_RELIABLE
    peer.put_packet(packet)
func poll() -> void:
    var now: int=Time.get_ticks_msec()
    if peer==null:
        if state=="reconnecting" and now>=next_retry:_connect()
        return
    peer.poll()
    if not hello_sent and peer.get_connection_status()==MultiplayerPeer.CONNECTION_CONNECTED:
        hello_sent=true;send("hello",{"protocol":Protocol.VERSION,"build":Protocol.fingerprint(),"kind":knight_kind,"token":token,"room":room})
    var count: int=0
    while peer!=null and peer.get_available_packet_count()>0 and count<128:
        count+=1
        var sender: int=peer.get_packet_peer()
        var packet: Dictionary=Protocol.decode(peer.get_packet())
        if sender!=1:continue
        if not Protocol.packet(packet):_error("INVALID CAMPAIGN DATA");return
        last_packet=now;receive(packet.type,packet.body)
    if peer==null:return
    if pending_failure or now-last_packet>5000:_retry();return
    if now-last_ping>400:last_ping=now;send("ping")
func receive(kind: String,body: Dictionary) -> void:
    if kind=="error":_error(str(body.get("message","CAMPAIGN CONNECTION FAILED")));return
    if kind=="reconnect":_retry();return
    if kind=="identify":
        if body.get("protocol")!=Protocol.VERSION or body.get("build")!=Protocol.fingerprint() or not Protocol.hex(body.get("room"),32):_error("INVALID CAMPAIGN IDENTITY");return
        if body.room==room:_error("THIS KNIGHT IS RESERVED OR THE GAME IS FULL");return
        var config:=ConfigFile.new()
        var saved: Variant=""
        if not profile_path.is_empty() and not Runtime.debug_enabled() and config.load(profile_path)==OK:saved=config.get_value("rooms",body.room,"")
        if not Protocol.hex(saved,64):_error("NO RESERVED KNIGHT FOR THIS CAMPAIGN");return
        token=saved;room=body.room;hello_sent=false;return
    if kind=="welcome":
        if not Protocol.welcome(body):_error("INVALID CAMPAIGN HANDSHAKE");return
        if host_run!=body.run:seen_feedback.clear();pending_inputs.clear()
        host_run=body.run
        latest_tick=-1;latest_revision=0;newest_frame={};epoch=1
        seat=body.seat;room=body.room;token=body.token;command_sequence=int(body.commands);input_sequence=int(body.inputs);save_profile()
        roster=body.status;state=str(roster.state);notice="ENTER WHEN EVERYONE IS READY";changed.emit()
    elif kind=="status":
        if not Protocol.status(body):_error("INVALID CAMPAIGN STATUS");return
        roster=body;state=body.state;notice=str(body.get("notice",""));changed.emit()
    elif kind=="view":
        if not Protocol.valid_view(body):_error("INVALID CAMPAIGN SNAPSHOT");return
        var first: bool=not view_received
        if body.revision<latest_revision:return
        latest_revision=int(body.revision)
        if int(body.epoch)!=epoch:pending_inputs.clear()
        latest=body.duplicate(true);latest_tick=int(body.tick);epoch=int(body.epoch);phase=body.phase
        _filter_feedback(body.combat)
        replica.apply(body);own_inventory.apply(body,true)
        # Reliable transactions can arrive behind a newer movement packet on
        # another ENet channel. Apply their inventory/turn data, retaining the
        # freshest movement/combat state from the same phase.
        if newest_frame.get("epoch")==epoch and int(newest_frame.get("tick",-1))>latest_tick:
            latest_tick=int(newest_frame.tick)
            if newest_frame.has("state"):
                var confirmed: Dictionary=newest_frame.duplicate(true);confirmed.events=[];replica.apply_combat(confirmed)
            else:replica.apply_map(newest_frame)
        view_received=true;frame_received.emit()
        if first:fight_started.emit()
    elif kind=="combat":
        if not view_received or body.get("epoch")!=epoch or body.get("battle")!=replica.battle_number or not Protocol.valid_combat(body):return
        if body.tick<=latest_tick:return
        latest_tick=body.tick;_filter_feedback(body);newest_frame=body.duplicate(true);replica.apply_combat(body);frame_received.emit()
    elif kind=="map":
        if not view_received or body.get("epoch")!=epoch or not Protocol.valid_map(body) or body.tick<=latest_tick:return
        latest_tick=body.tick;newest_frame=body.duplicate(true);replica.apply_map(body);frame_received.emit()
    elif kind=="ack":last_ack=body
func _filter_feedback(value: Dictionary) -> void:
    if value.is_empty():return
    var fresh: Array=[]
    for event in value.events:
        var id: String=str(event.get("_network_id",""))
        if id.is_empty() or seen_feedback.has(id):continue
        seen_feedback[id]=true;fresh.append(event)
    while seen_feedback.size()>512:seen_feedback.erase(seen_feedback.keys()[0])
    value.events=fresh
    var ack: int=int(value.get("inputs",{}).get(seat,0))
    while not pending_inputs.is_empty() and int(pending_inputs[0].sequence)<=ack:pending_inputs.pop_front()
func command(action: String,args: Dictionary={}) -> bool:
    if state!="playing" or not view_received:return false
    command_sequence+=1;send("command",{"sequence":command_sequence,"epoch":epoch,"action":action,"args":args});return true
func advance(direction: Vector2i,action: String="idle") -> void:
    if state!="playing" or not view_received:return
    input_sequence+=1
    pending_inputs.append({"sequence":input_sequence,"direction":direction,"action":action})
    if pending_inputs.size()>32:pending_inputs.pop_front()
    send("input",{"sequence":input_sequence,"epoch":epoch,"dx":direction.x,"dy":direction.y,"action":action},3)
func ready() -> void:
    if state in ["lobby","paused"]:send("ready")
func _retry() -> void:
    if peer!=null:peer.close();peer=null
    pending_inputs.clear()
    state="reconnecting";notice="RECONNECTING - YOUR KNIGHT IS RESERVED";next_retry=Time.get_ticks_msec()+500;requested_reconnect=true
    changed.emit()
func _error(message: String) -> void:
    if peer!=null:peer.close();peer=null
    state="closed";notice=message.left(100);changed.emit()
func close() -> void:
    if peer!=null:send("leave");peer.host.flush();peer.close();peer=null
    if host_runtime!=null:host_runtime.stop();host_runtime.queue_free();host_runtime=null
    state="idle";seat=-1;view_received=false;latest={};latest_tick=-1;requested_reconnect=false
    seen_feedback.clear();pending_inputs.clear();host_run="";newest_frame={};latest_revision=0
