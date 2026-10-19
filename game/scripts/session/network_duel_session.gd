extends RefCounted

const Simulation = preload("res://scripts/domain/combat_simulation.gd")
const Replica = preload("res://scripts/session/duel_replica.gd")
const Protocol = preload("res://scripts/session/duel_protocol.gd")
var rules: Resource
var authoritative: bool
var simulation: RefCounted
var round_id: int = 0
var settled: bool = false
var last_input: Dictionary = {1:0,2:0}
var sequences: Dictionary = {1:0,2:0}
var queue: Dictionary = {}
var held: Dictionary = {}
var template: Dictionary

func _init(rule_set: Resource, authority: bool = true) -> void:
    rules=rule_set;authoritative=authority
    var model: RefCounted=Simulation.new(rules);model.start(&"competitive",2,&"duel")
    template=model.actors[1].duplicate(true)
    begin(1)

func begin(number: int) -> void:
    round_id=number;settled=false;last_input={1:0,2:0};sequences={1:0,2:0};queue.clear();held.clear()
    if authoritative:
        simulation=Simulation.new(rules)
        simulation.start(&"competitive",2,&"duel",{"combat_seed":0x4455454c})
    else: simulation=Replica.new()

func submit(actor: int, value: Dictionary) -> bool:
    if not authoritative or actor not in [1,2] or settled or not Protocol.intent(value,round_id,simulation.tick,last_input[actor]): return false
    last_input[actor]=value.sequence
    var target: int=simulation.tick+Protocol.INPUT_DELAY
    if not queue.has(target):queue[target]={}
    queue[target][actor]={"dx":value.dx,"dy":value.dy,"action":value.action,"expires":target+Protocol.INPUT_TTL}
    return true

func step() -> bool:
    if not authoritative or settled: return false
    var tick: int=simulation.tick
    for actor in queue.get(tick,{}):held[actor]=queue[tick][actor]
    queue.erase(tick)
    for actor in [1,2]:
        var value: Dictionary=held.get(actor,{})
        if int(value.get("expires",-1))<tick:value={}
        sequences[actor]+=1
        simulation.submit(actor,{"actor":actor,"tick":tick,"sequence":sequences[actor],"dx":int(value.get("dx",0)),"dy":int(value.get("dy",0)),"action":String(value.get("action","idle"))})
    simulation.advance()
    settled=simulation.outcome()!="ongoing"
    for actor in simulation.actors.values():
        if actor.health<=0 and actor.down_remaining>0:settled=false
    return true

func frame() -> Dictionary:
    var snapshot: Dictionary=simulation.snapshot()
    return {"round":round_id,"state":snapshot,"hash":Protocol.state_hash(snapshot),"events":simulation.events.duplicate(true),"finished":settled}

func valid_frame(value: Dictionary) -> bool:
    if not value.has_all(["round","state","hash","events","finished"]) or typeof(value.round)!=TYPE_INT or value.round!=round_id or typeof(value.state)!=TYPE_DICTIONARY or typeof(value.events)!=TYPE_ARRAY or typeof(value.finished)!=TYPE_BOOL or typeof(value.hash)!=TYPE_STRING: return false
    var state: Dictionary=value.state
    if not Protocol.primitive(value) or Protocol.state_hash(state)!=value.hash:return false
    if state.get("schema")!=25 or state.get("mode")!="competitive" or state.get("encounter")!="duel" or typeof(state.get("tick"))!=TYPE_INT or state.tick<0 or state.tick>0x7fffffff or typeof(state.get("actors"))!=TYPE_DICTIONARY:return false
    if not state.actors.has_all([1,2]) or state.actors.size()!=2 or typeof(state.get("projectiles"))!=TYPE_ARRAY or typeof(state.get("rat_perch"))!=TYPE_DICTIONARY or state.get("spawn_remaining")!=0:return false
    for id in [1,2]:
        var actor: Variant=state.actors[id]
        if typeof(actor)!=TYPE_DICTIONARY:return false
        for field in template:
            if not actor.has(field) or typeof(actor[field])!=typeof(template[field]):return false
        if actor.id!=id or actor.owner!=id or actor.team!=id or actor.kind!="knight" or actor.maximum!=20 or actor.health<0 or actor.health>20 or abs(actor.x)>10000 or abs(actor.y)>10000 or actor.facing not in [-1,1] or actor.action not in Protocol.ACTIONS+["down"]:return false
    return true

func accept_frame(value: Dictionary, fresh_round: bool = false) -> bool:
    if authoritative or not valid_frame(value): return false
    if not simulation.state.is_empty() and (value.state.tick<=simulation.tick and not fresh_round):return false
    simulation.apply(value.state,value.events);settled=value.finished
    return true
