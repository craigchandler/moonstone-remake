extends SceneTree
const Session=preload("res://scripts/session/network_duel_session.gd")
const Protocol=preload("res://scripts/session/duel_protocol.gd")
const Rules=preload("res://content/foundation_rules.tres")
var checks: int=0
var failures: Array[String]=[]
func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failures.append(label);push_error(label)
func input(actor: int,sequence: int,tick: int,action: String="idle",dx: int=0,round_id: int=1) -> Dictionary:
    return {"round":round_id,"sequence":sequence,"dx":dx,"dy":0,"action":action,"seen":tick}
func _initialize() -> void:run.call_deferred()
func run() -> void:
    var host: RefCounted=Session.new(Rules)
    var guest: RefCounted=Session.new(Rules,false)
    check(host.simulation.actors[1].owner==1 and host.simulation.actors[2].owner==2,"two stable human owners, no AI")
    check(guest.accept_frame(host.frame(),true),"initial host snapshot accepted")
    check(not guest.step() and not guest.submit(1,input(1,1,0)),"client cannot step rules or issue authoritative commands")
    check(host.submit(1,input(1,1,0,"idle",1)),"host movement intent queued")
    var x: int=host.simulation.actors[1].x
    for n in range(Protocol.INPUT_DELAY):host.step();check(host.simulation.actors[1].x==x,"input buffer delays movement equally")
    host.step();check(host.simulation.actors[1].x>x,"input applied at authoritative buffered tick")
    check(not host.submit(2,input(2,1,100)),"future acknowledged tick rejected")
    check(host.submit(2,input(2,1,0)),"lagging peer tick accepted without trusting remote scheduling")
    check(not host.submit(2,input(2,1,0)),"duplicate sequence rejected")
    var bad: Dictionary=input(2,2,0);bad.actor=1
    check(not host.submit(2,bad),"remote actor spoof rejected")
    for key in ["round","sequence","dx","dy","seen"]:
        bad=input(2,2,0);bad[key]=1.5
        check(not host.submit(2,bad),"fractional input rejected "+key)
    for action in ["teleport","guardian_lunge","kill"]:check(not host.submit(2,input(2,2,0,action)),"non-knight move rejected "+action)
    check(not host.submit(3,input(2,2,0)),"third actor rejected")
    for n in range(Protocol.INPUT_DELAY+Protocol.INPUT_TTL+2):host.step()
    x=host.simulation.actors[1].x
    for n in range(20):host.step()
    check(host.simulation.actors[1].x==x,"lost/released input expires instead of sticking forever")
    host.begin(2);guest.begin(2)
    check(not host.submit(2,input(2,1,0,"swing",0,1)),"late previous-round input rejected")
    check(guest.accept_frame(host.frame(),true),"new round has fresh host state")
    for tick in range(300):
        for actor in [1,2]:host.submit(actor,input(actor,tick+1,host.simulation.tick,"swing",1 if actor==1 and tick<40 else (-1 if actor==2 and tick<40 else 0),2))
        host.step()
        var packet: Dictionary=Protocol.decode(Protocol.encode({"frame":host.frame()}))
        check(not packet.is_empty(),"bounded variant wire encoding "+str(tick))
        if not guest.settled:
            check(guest.accept_frame(packet.frame),"monotonic authoritative frame "+str(tick))
            check(host.simulation.snapshot()==guest.simulation.snapshot(),"detached replica equals host "+str(tick))
        if host.settled:break
    host.simulation.actors[2].health=0
    host.simulation.knock_down(host.simulation.actors[2],"defeat")
    var death_frame: Dictionary=host.frame()
    check(host.simulation.actors[2].action=="down" and guest.accept_frame(death_frame,true),"native lethal knight down state is accepted without permitting a down input")
    check(not host.submit(2,input(2,500,host.simulation.tick,"down",0,2)),"death state cannot be submitted as a player move")
    var frame: Dictionary=host.frame()
    check(not guest.accept_frame(frame),"duplicate state tick ignored")
    var untouched: Dictionary=guest.simulation.snapshot()
    frame=host.frame();frame.state.actors[1].owner=999;frame.hash=Protocol.state_hash(frame.state)
    check(not guest.accept_frame(frame,true) and guest.simulation.snapshot()==untouched,"owner tampering rejected atomically")
    frame=host.frame();frame.state.actors[1].erase("remaining");frame.hash=Protocol.state_hash(frame.state)
    check(not guest.accept_frame(frame,true),"incomplete actor rejected")
    frame=host.frame();frame.hash="wrong"
    check(not guest.accept_frame(frame,true),"corrupt state rejected")
    check(Protocol.decode(PackedByteArray()).is_empty(),"empty packet rejected")
    var large:=PackedByteArray();large.resize(Protocol.MAX_PACKET+1)
    check(Protocol.decode(large).is_empty(),"oversized packet rejected before decoding")
    check(not Protocol.primitive(Resource.new()),"wire cannot contain executable/resource objects")
    print("NETWORK_PACKET_BYTES raw=",var_to_bytes(host.frame()).size()," compressed=",Protocol.encode(host.frame()).size())
    print("NETWORK_UNIT=",JSON.stringify({"checks":checks,"failures":failures,"state_hash":Protocol.state_hash(host.simulation.snapshot())}))
    if failures.is_empty():print("PASS: ",checks," authoritative duel, input buffer/expiry, ownership, wire and replica checks")
    quit(0 if failures.is_empty() else 1)
