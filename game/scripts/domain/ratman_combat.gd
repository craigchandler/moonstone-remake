extends RefCounted

# Original caster ground decisions and shared successful-hit pause. The existing
# native flight trajectory, tree reservation and hold choreography stay separate.
const GROUND:Array[String]=["rat_strike","rat_bite"]
static func state(actor:Dictionary)->Dictionary:
    if not actor.has("ratman"):actor.ratman={"next_decision":0}
    return actor.ratman
static func manifest(rules:Resource)->Dictionary:
    var p:Resource=rules.ratman
    return {p.profile_id:{"api":p.api_version,"version":p.content_version}}
static func decision(p:Resource,depth_near:bool,held:bool,target_hp:int,wait_steps:int,distance:int)->String:
    if depth_near:
        if held or target_hp<=0:return "idle"
        if wait_steps>0:return "wait"
        if distance<=p.strike_range:return "rat_strike"
        if distance<=p.bite_range:return "rat_bite"
    return "rat_leap"
static func choose(sim:RefCounted,actor:Dictionary,target:Dictionary)->String:
    if target.is_empty():return "idle"
    if actor.remaining>0 or actor.special_remaining>0 or actor.held_target!=0 or actor.stagger_remaining>1 or actor.cooldown_remaining>1 or actor.grab_remaining>0:return "idle"
    var s:Dictionary=state(actor);var p:Resource=sim.rules.ratman
    if sim.tick<int(s.next_decision):return "idle"
    s.next_decision=sim.tick+int(p.decision_ticks)
    var held:bool=target.grab_remaining>0 or target.hidden_by!=0
    for other in sim.actors.values():
        if other.kind=="ratman" and other.held_target!=0:held=true
    var near:bool=abs(int(target.y)-int(actor.y))<=int(sim.rules.actor_definitions.ratman.ai_depth)
    var plan:String=decision(p,near,held,int(target.health),sim.ratman_wait_steps,abs(int(target.x)-int(actor.x)))
    if plan=="wait":
        # Shared source counter: only eligible grounded handler decisions consume
        # it, once per actor/pass. Flight, hurt and hold time cannot burn it away.
        sim.ratman_wait_steps-=1
        return "idle"
    return plan
static func move(rules:Resource,actor:Dictionary)->Dictionary:
    var original:Dictionary=rules.moves[actor.action]
    if actor.action!="rat_leap":return original
    var result:Dictionary=original.duplicate()
    result.recovery=int(rules.ratman.perch_ticks) if actor.rat_tree else 0
    return result
static func contacts(sim:RefCounted,hits:Array)->void:
    for hit in hits:
        if not hit.get("resolved",false) or hit.get("blocked",false) or hit.get("amount",0)<=0:continue
        var source:Dictionary=sim.actors[hit.attacker]
        if source.kind!="ratman" or hit.move not in GROUND or source.health<=0 or source.stagger_remaining>0:continue
        sim.ratman_wait_steps=int(sim.rules.ratman.hit_wait_steps)
