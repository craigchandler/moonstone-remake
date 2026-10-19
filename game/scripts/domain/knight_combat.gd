extends RefCounted

const Random=preload("res://scripts/domain/loot_roller.gd")
const ACTIONS={"idle":0,"lunge":4,"swing":8,"dagger":12,"defend":16,"reverse":20,"upward":24,"block":28,"heavy":32}
static func state(actor:Dictionary)->Dictionary:
    if not actor.has("knight_ai"):actor.knight_ai={"next_decision":0,"last_action":"idle","action":"idle"}
    return actor.knight_ai
static func manifest(rules:Resource)->Dictionary:
    var p:Resource=rules.knight_ai
    return {p.profile_id:{"api":p.api_version,"version":p.content_version}}
static func decision(p:Resource,f:Dictionary,random:RefCounted)->String:
    var distance:int=f.distance
    if f.hp<=0:return "swing" if distance<=p.swing_range else "walk"
    # Retail always makes this guard draw, including a latched stance. An
    # out-of-range guard check leaves the opponent-side flag as its distance.
    var guard:int=random.percent()
    if guard>=int(f.odds) and f.opposite:
        if int(f.opponent) in [8,32,4]:
            if distance<=p.guard_range:return "defend" if f.opponent==8 else "block"
            distance=1 if f.left else 0
    if random.percent()<=int(f.odds):
        random.next_value() # Source's unused taunt draw still advances the seed.
        return "walk"
    if distance<=p.swing_range and f.last!=8:return "swing"
    if distance<=p.heavy_range and f.last!=32:return "heavy"
    if distance<=p.lunge_range and (f.daggers==0 or f.last!=4):return "lunge"
    return "dagger" if f.daggers>0 else "walk"
static func choose(sim:RefCounted,actor:Dictionary,target:Dictionary)->Dictionary:
    var idle:Dictionary={"direction":Vector2i.ZERO,"action":"idle","facing":actor.facing}
    if target.is_empty():return idle
    if actor.remaining>0 or actor.special_remaining>0 or actor.held_target!=0 or actor.stagger_remaining>1 or actor.cooldown_remaining>1 or actor.grab_remaining>0:return idle
    var s:Dictionary=state(actor);var p:Resource=sim.rules.knight_ai
    var dx:int=signi(int(target.x)-int(actor.x));var dy:int=signi(int(target.y)-int(actor.y)) if abs(int(target.y)-int(actor.y))>p.depth else 0
    var facing:int=dx if dx else int(actor.facing)
    var distance:int=abs(int(target.x)-int(actor.x))
    var movement:=Vector2i(dx if distance>p.lunge_range else (-dx if distance<=p.keep_distance else 0),dy)
    if sim.tick<int(s.next_decision):
        # Continuous native walking stops at the lane/range boundary, even
        # between source decision passes. Never overshoot with stale input.
        return {"direction":movement if s.action=="walk" else Vector2i.ZERO,
            "action":s.action if s.action in ["block","defend"] else "idle","facing":facing}
    s.next_decision=sim.tick+int(p.decision_ticks)
    var action:String="walk"
    if dy==0:
        var random:RefCounted=Random.new(null,sim.knight_random_state)
        var difficulty:int=clampi(int(sim.encounter_settings.get("knight_difficulty",0)),0,p.odds.size()-1)
        action=decision(p,{"distance":distance,"hp":target.health,"odds":int(p.odds[difficulty]),
            "opposite":target.facing!=facing,"left":target.x<actor.x,"daggers":actor.daggers,
            "last":ACTIONS.get(s.last_action,0),"opponent":28 if target.guarding else ACTIONS.get(target.action,0)},random)
        sim.knight_random_state=random.state
    if action!="walk":movement=Vector2i.ZERO;s.last_action=action
    s.action=action
    return {"direction":movement,"action":action,"facing":facing}
