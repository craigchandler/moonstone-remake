extends RefCounted

# Explicit live read models. Never transmit checkpoint(), pre-rolled treasure,
# campaign RNG streams, private seat credentials or writable resource objects.
static func view(session: RefCounted,seat: int) -> Dictionary:
    var j: RefCounted=session.journey
    var data: Dictionary=j.snapshot()
    data["message"]=j.message
    data.erase("reward_seed");data.quest.erase("seed")
    data.places.erase("seed");data.places.erase("last_slot")
    data.places.erase("item_cycle");data.places.erase("gold_cycle")
    if data.places.visit.get("phase")=="rolling":data.places.visit.dice=[];data.places.visit.payout=0
    data.rivals.erase("seed");data.rivals.erase("last_slot")
    data.rivals.erase("walk");data.rivals.erase("target");data.rivals.erase("goal")
    if seat!=j.party.active or int(j.inventory.items.get("scroll_of_acquisition",0))==0:
        for row in data.rivals.records:row.inventory={"gold":0,"items":{}}
    for id in data.lair_loot:
        if not (j.loot_open and id==j.world.active_lair) and not j.revealed_lairs.has(id):
            data.lair_loot[id]={"gold":0,"items":{},"kind":4,"keys":0,"stones":0}
    var personal: Dictionary=j.party.record(j,seat)
    personal.identity=j.party.players[seat].identity.duplicate(true)
    personal.erase("loot_ready")
    var party: Dictionary={"players":j.party.players.duplicate(true),"active":j.party.active,"turn":j.party.turn,"awaiting":j.party.awaiting,"game_over":j.party.game_over,"frog_days":j.party.personal.map(func(row):return int(row.frog_days))}
    # Local input ports are presentation preferences, never network ownership.
    for player in party.players:player.input=0
    var equipment: Dictionary={}
    if j.combat!=null:
        for id in j.combat.simulation.actors:
            var actor: Dictionary=j.combat.simulation.actors[id]
            if actor.kind not in ["knight","black_knight"]:continue
            if actor.team==1:equipment[id]={"weapon":j.character.effective_weapon(j.inventory.items),"armour":j.character.armour}
            else:
                var rival: Dictionary=j.rivals.find(j.world.active_lair)
                if not rival.is_empty():
                    var knight: RefCounted=j.rivals.knight(rival)
                    equipment[id]={"weapon":knight.effective_weapon(rival.inventory.items),"armour":knight.armour}
    return {"schema":1,"epoch":session.epoch,"revision":session.revision,"tick":session.tick,"battle":session.battle_id,"phase":session.phase(),"paused":session.paused,"campaign":data,"party":party,"personal":personal,"equipment":equipment,"combat":combat(session)}

static func combat(session: RefCounted) -> Dictionary:
    if session.journey.combat==null:return {}
    var fight: RefCounted=session.journey.combat
    return {"epoch":session.epoch,"battle":session.battle_id,"tick":session.tick,"state":fight.simulation.snapshot(),"events":session.feedback.duplicate(true),"humans":fight.human_actors.duplicate(true),"inputs":session.applied_inputs.duplicate(true)}

static func map_frame(session: RefCounted) -> Dictionary:
    var j: RefCounted=session.journey
    var markers: Array=[]
    for row in j.rivals.records:markers.append({"id":row.id,"position":row.position})
    var visit: Dictionary=j.places.visit.duplicate(true)
    if visit.get("phase")=="rolling":visit.dice=[];visit.payout=0
    var quest: Dictionary=j.quest.duplicate(true);quest.erase("seed")
    return {"epoch":session.epoch,"tick":session.tick,"world":j.world.snapshot(),"markers":markers,"travel_spent":j.travel_spent,"visit":visit,"henge":j.henge.duplicate(true),"quest":quest}
