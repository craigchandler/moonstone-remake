extends RefCounted

# Shared authority for both headless and embedded campaign hosts. No media or UI.
const Journey=preload("res://scripts/session/journey_session.gd")
const Party=preload("res://scripts/session/local_party.gd")
const World=preload("res://content/first_journey.tres")
const Rules=preload("res://content/foundation_rules.tres")
const Places=preload("res://scripts/domain/town_locations.gd")
const Clocks=preload("res://content/packs/classic/campaign/visit_clocks.json")
const INPUT_DELAY: int=1
const INPUT_TTL: int=10
var journey: RefCounted
var epoch: int=1
var tick: int=0
var battle_id: int=0
var revision: int=1
var last_key: String=""
var observed_combat: RefCounted
var battle_ready: Dictionary={}
var command_sequences: Dictionary={}
var input_sequences: Dictionary={}
var applied_inputs: Dictionary={}
var feedback: Array=[]
var held: Dictionary={}
var queued: Dictionary={}
var paused: bool=false
var end_tick: int=-1

func _init(seed_value: int=1,seats: Array=[0,1]) -> void:
    journey=Journey.new(World,Rules,seed_value)
    var roster: Array=Party.defaults()
    for seat in range(4):roster[seat].human=seat in seats
    journey.start_local_party(roster,seed_value)
    sync_phase()

func phase() -> String:
    var j: RefCounted=journey
    if j.party.game_over:return "game_over"
    if not j.quest.ending.is_empty():return "ending"
    if j.quest.notice:return "quest"
    if not j.henge.is_empty():return "henge"
    if j.loot_open:return "loot"
    if j.combat!=null:
        if j.combat.simulation.outcome()!="ongoing":return "result"
        return "battle_ready" if battle_ready.values().has(false) else "battle"
    if not j.pending_attack.is_empty():return "attack"
    if not j.town_id.is_empty():return "town"
    if j.rivals.active!=0:return "computer"
    return "turn_ready" if j.party.awaiting else "map"

func sync_phase() -> bool:
    if journey.combat!=observed_combat:
        observed_combat=journey.combat
        battle_ready.clear();feedback.clear();end_tick=-1
        if observed_combat!=null:
            battle_id+=1
            if observed_combat.human_actors.size()>1:
                for owner in observed_combat.human_actors.values():battle_ready[int(owner)-1]=false
    var key: String=str(journey.party.turn)+":"+phase()+":"+journey.town_id+":"+journey.service+":"+str(journey.places.visit.get("phase",""))+":"+str(journey.henge.get("phase",""))+":"+str(journey.quest.ending.get("stage",""))
    if key==last_key:return false
    last_key=key;epoch+=1;revision+=1;held.clear();queued.clear()
    return true

func set_paused(value: bool) -> void:
    if paused==value:return
    paused=value;epoch+=1;revision+=1;held.clear();queued.clear()

func active(seat: int) -> bool:
    return seat==journey.party.active and not paused and (journey.rivals.active==0 or journey.combat!=null or not journey.pending_attack.is_empty())

func command(seat: int,sequence: int,at_epoch: int,action: String,args: Dictionary={}) -> Dictionary:
    if seat<0 or seat>3 or not journey.party.players[seat].human:return {"ok":false,"reason":"INVALID SEAT"}
    var previous: int=int(command_sequences.get(seat,0))
    if sequence<=previous:return {"ok":false,"reason":"ALREADY RECEIVED","duplicate":true}
    if sequence!=previous+1:return {"ok":false,"reason":"COMMAND SEQUENCE"}
    command_sequences[seat]=sequence
    if paused or at_epoch!=epoch:return {"ok":false,"reason":"STATE CHANGED"}
    var ok: bool=false
    if action=="battle_ready" and phase()=="battle_ready" and battle_ready.has(seat):battle_ready[seat]=true;ok=true
    elif not active(seat):return {"ok":false,"reason":"WAIT FOR YOUR TURN"}
    else:
        var j: RefCounted=journey
        match action:
            "begin_turn":ok=j.begin_turn()
            "rest":ok=j.rest()
            "enter":
                if typeof(args.get("id"))==TYPE_STRING:ok=j.confirm_location(args.id)
            "result":
                if j.combat!=null:
                    var finished: bool=true
                    for actor in j.combat.simulation.actors.values():
                        if actor.health<=0 and actor.down_remaining>0:finished=false
                    if finished:ok=j.prepare_loot() if j.combat.simulation.outcome()=="victory" else j.return_to_map(false)
            "retreat":
                if j.combat!=null:
                    var dying: bool=false
                    for actor in j.combat.simulation.actors.values():
                        if actor.health<=0 and actor.down_remaining>0:dying=true
                    if j.combat.simulation.outcome()=="ongoing" or not dying:ok=j.return_to_map(false)
            "leave_loot":
                if j.loot_open:ok=j.return_to_map(false)
            "take_loot":
                if typeof(args.get("id"))==TYPE_STRING:ok=j.take_loot(args.id)
            "collect_loot":
                if j.looting():j.collect_all_loot();ok=true
            "service":
                if typeof(args.get("id"))==TYPE_STRING:ok=j.open_service(args.id)
            "close_service":
                if j.places.visit.get("phase")=="rolling" or (j.town_id=="wizard" and j.places.visit.get("phase")!="sheet"):return {"ok":false,"reason":"WAIT FOR THE SCENE"}
                if j.town_id in ["home","wizard"]:ok=j.leave_town()
                elif not j.town_id.is_empty():j.service="";j.places.visit={};ok=true
            "leave_town":
                if j.places.visit.get("phase")!="rolling" and (j.town_id!="wizard" or j.places.visit.get("phase")=="sheet"):ok=j.leave_town()
            "buy":
                if typeof(args.get("id"))==TYPE_STRING:ok=j.buy_equipment(args.id)
            "heal":
                if typeof(args.get("id"))==TYPE_STRING:ok=j.buy_healing(args.id)
            "upgrade":
                if args.get("id") in ["strength","constitution","endurance"]:ok=j.upgrade_stat(args.id)
            "item":
                if typeof(args.get("id"))==TYPE_STRING:
                    var target: Variant=args.get("target")
                    if typeof(target)==TYPE_DICTIONARY and target.size()==2 and typeof(target.get("x"))==TYPE_INT and typeof(target.get("y"))==TYPE_INT:target=Vector2i(target.x,target.y)
                    ok=j.use_item(args.id,target)
            "protection":
                if typeof(args.get("use"))==TYPE_BOOL:ok=j.resolve_pending_attack(args.use)
            "trade":
                if typeof(args.get("id"))==TYPE_STRING and typeof(args.get("buy"))==TYPE_BOOL:ok=Places.trade(j,args.id,args.buy)
            "donation":
                if typeof(args.get("amount"))==TYPE_INT and j.places.visit.get("phase")=="donation":j.places.visit.donation=clampi(args.amount,0,j.inventory.gold);ok=true
            "donate":ok=Places.donate(j,int(j.places.visit.get("donation",0)))
            "wager":
                if typeof(args.get("amount"))==TYPE_INT:ok=Places.wager(j,args.amount)
            "visit_next":
                var v: Dictionary=j.places.visit
                if v.get("kind")=="wizard":ok=Places.advance_wizard(j)
                elif v.get("phase")=="greeting":v.phase="donation";ok=true
                elif v.get("phase")=="dice":v.phase="tavern";ok=true
            "henge_next":ok=j.advance_henge()
            "henge_offer":
                if typeof(args.get("id"))==TYPE_STRING:ok=j.offer_henge_item(args.id)
            "henge_skip":ok=j.complete_henge()
            "henge_leave_offer":ok=j.leave_henge_offering()
            "henge_leave":ok=j.leave_henge()
            "quest_ack":ok=j.acknowledge_moonstone()
            "ending_start":ok=j.enter_ending()
            "ending_finish":ok=j.finish_ending()
    revision+=1;sync_phase()
    return {"ok":ok,"reason":"" if ok else "ACTION NOT AVAILABLE"}

func input(seat: int,sequence: int,at_epoch: int,direction: Vector2i,action: String) -> bool:
    if paused or at_epoch!=epoch or seat<0 or seat>3 or not journey.party.players[seat].human or sequence<=int(input_sequences.get(seat,0)) or sequence>int(input_sequences.get(seat,0))+1000 or abs(direction.x)>1 or abs(direction.y)>1 or action not in ["idle","swing","heavy","lunge","reverse","upward","dagger","block"]:return false
    var controlled: bool=active(seat) and phase()=="map"
    if journey.combat!=null and phase()=="battle":controlled=journey.combat.human_actors.values().has(seat+1)
    if not controlled:return false
    input_sequences[seat]=sequence
    var key: int=tick+INPUT_DELAY
    if not queued.has(key):queued[key]={}
    queued[key][seat]={"direction":direction,"action":action,"expires":key+INPUT_TTL,"sequence":sequence}
    return true

func intent(seat: int) -> Dictionary:
    var value: Dictionary=held.get(seat,{})
    return value if not value.is_empty() and tick<=int(value.expires) else {"direction":Vector2i.ZERO,"action":"idle"}

func advance() -> bool:
    if paused:return false
    if queued.has(tick):
        for seat in queued[tick]:
            held[seat]=queued[tick][seat];applied_inputs[seat]=int(queued[tick][seat].sequence)
        queued.erase(tick)
    var j: RefCounted=journey
    var stage: String=phase()
    if stage=="computer":j.advance_rival_turn()
    elif stage=="map":j.travel(intent(j.party.active).direction)
    elif stage in ["battle","result"]:
        if stage=="result" and end_tick<0:end_tick=tick
        var owner: int=int(j.combat.human_actors.get(1,j.party.active+1))-1
        var first: Dictionary=intent(owner)
        var additional: Dictionary={}
        for id in j.combat.human_actors:
            if id!=1:additional[id]=intent(int(j.combat.human_actors[id])-1)
        j.combat.advance(first.direction,first.action,additional)
        capture_feedback()
        if j.combat.simulation.outcome()!="ongoing":
            j.settle_battle()
            var finished: bool=true
            for actor in j.combat.simulation.actors.values():
                if actor.health<=0 and actor.down_remaining>0:finished=false
            if finished and j.combat.simulation.outcome()=="victory":j.prepare_loot()
    elif stage=="henge":j.tick_henge()
    elif stage=="quest":j.tick_quest()
    elif stage=="ending":j.tick_ending()
    elif stage=="town" and not j.places.visit.is_empty():
        var v: Dictionary=j.places.visit
        v.tick=mini(1000000,int(v.tick)+1)
        if v.phase=="rolling" and int(v.tick)>=int(Clocks.data.dice_roll_ticks):v.phase="dice";v.tick=0
    tick+=1
    return sync_phase()

func capture_feedback() -> void:
    var sim: RefCounted=journey.combat.simulation
    for index in range(sim.events.size()):
        var event: Dictionary=sim.events[index].duplicate(true)
        event["_network_id"]=str(battle_id)+":"+str(sim.tick)+":"+str(index)
        event["_network_tick"]=sim.tick
        feedback.append(event)
    while not feedback.is_empty() and (feedback.size()>128 or int(feedback[0]._network_tick)<sim.tick-20):feedback.pop_front()

func safe_checkpoint() -> Dictionary:
    # Reproduce existing disk-resume semantics without checkpoint() changing a
    # live result/loot phase merely because the host is writing a save.
    var j: RefCounted=journey
    var data: Dictionary=j.snapshot()
    if j.combat!=null and j.combat.simulation.outcome()=="victory" and j.battle_settled:data.loot_open=true
    data.phase="attack" if not j.pending_attack.is_empty() else ("loot" if data.loot_open else "map")
    if not data.loot_open and j.pending_attack.is_empty():
        if not data.world.active_lair.is_empty():
            data.world.entry_lock=data.world.active_lair;data.world.active_lair="";data.world.last_result="retreated"
        data.battle_settled=false
    return j.party.wrap(j,data)
