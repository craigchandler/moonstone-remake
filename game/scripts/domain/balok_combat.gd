extends RefCounted

# Actor-owned integer state; no images, animation callbacks, wall time or RNG.
# Aim/start/step follow the original dagger-style Balok trajectory. The native
# five-tick step is calibrated to the supplied film, not a global game speed.
const FLIGHTS: Array[String]=["balok_hop","balok_pounce"]

static func state(actor: Dictionary) -> Dictionary:
    if not actor.has("balok"):actor.balok={"retry":0,"next_retry":0,"flight":{}}
    return actor.balok

static func choose(rules: Resource,actor: Dictionary,target: Dictionary) -> String:
    if target.is_empty() or target.health<=0:return "idle"
    var p: Resource=rules.balok
    var distance: int=absi(int(target.x)-int(actor.x))
    if absi(int(target.y)-int(actor.y))<=int(rules.actor_definitions.balok.ai_depth):
        if distance<=p.close_range:return "balok_hop"
        if distance<=p.swipe_range:return "balok_swipe" if actor.last_attack!="balok_swipe" else "balok_maul"
        if distance<=p.maul_range:return "balok_maul"
        if target.daggers==0 and distance<=p.wait_range:return "idle"
    return "balok_pounce"

static func begin(rules: Resource,actor: Dictionary,target: Dictionary,tick: int) -> bool:
    if target.is_empty():return false
    var p: Resource=rules.balok
    var s: Dictionary=state(actor)
    var close: bool=absi(int(target.x)-int(actor.x))<=p.close_range and absi(int(target.y)-int(actor.y))<=rules.actor_definitions.balok.ai_depth
    if close:s.retry=0
    if s.retry>0:
        if tick<s.next_retry:return false
        s.retry-=1;s.next_retry=tick+int(p.step_ticks)
        if s.retry>0:return false
    var direction: int=1 if target.x>=actor.x else -1
    var to_x: int=int(target.x)-direction*int(p.target_offset)
    var distance: int=maxi(absi(to_x-int(actor.x)),absi(int(target.y)-int(actor.y)))
    var aimed_steps: int=distance/8
    var arc: int=maxi(3,distance/2)
    if aimed_steps<=4:aimed_steps=4;arc=10
    var steps: int=mini(aimed_steps,int(p.maximum_steps))
    var half: int=(steps+1)/2
    var velocity: int=(arc*256/half)*2
    var gravity: int=velocity/(half-1)
    var dx: int=(to_x-int(actor.x))*64/steps
    var dy: int=(int(target.y)-int(actor.y))*64/steps
    s.flight={"profile":p.profile_id,"version":p.content_version,"step":0,"steps":steps,
        "aim_steps":aimed_steps,"arc":arc,"x6":int(actor.x)*64,"y6":int(actor.y)*64,
        "z8":0,"dx":dx,"dy":dy,"velocity":velocity,"gravity":gravity,"landed":false}
    actor.leap_from_x=actor.x;actor.leap_from_y=actor.y;actor.leap_from_height=0;actor.leap_to_height=0
    actor.leap_to_x=(int(s.flight.x6)+dx*steps)>>6
    actor.leap_to_y=(int(s.flight.y6)+dy*steps)>>6
    return true

static func move(rules: Resource,actor: Dictionary) -> Dictionary:
    var original: Dictionary=rules.moves[actor.action]
    if actor.kind!="balok" or actor.action not in FLIGHTS:return original
    var f: Dictionary=actor.get("balok",{}).get("flight",{})
    if f.is_empty():return original # Old in-memory fixtures have no new state.
    var result: Dictionary=original.duplicate()
    result.windup=int(rules.balok.step_ticks)
    result.active=(int(f.steps)-1)*int(rules.balok.step_ticks)
    result.recovery=int(rules.balok.step_ticks)
    return result

static func step(actor: Dictionary) -> void:
    var f: Dictionary=state(actor).flight
    f.z8-=int(f.velocity);f.velocity-=int(f.gravity)
    f.x6+=int(f.dx);f.y6+=int(f.dy);f.step+=1
    actor.x=int(f.x6)>>6;actor.y=int(f.y6)>>6;actor.height=int(f.z8)>>8

static func advance(rules: Resource,actor: Dictionary,progress: int) -> void:
    var f: Dictionary=state(actor).flight
    var expected: int=mini(int(f.steps)-1,1+(progress-1)/int(rules.balok.step_ticks))
    while f.step<expected:step(actor)
    actor.height=int(f.z8)>>8

static func land(rules: Resource,actor: Dictionary,tick: int) -> void:
    var s: Dictionary=state(actor)
    var f: Dictionary=s.flight
    if f.is_empty() or f.landed:return
    while f.step<f.steps:step(actor)
    actor.height=0;actor.rest_height=0;f.landed=true
    s.retry=int(rules.balok.retry_calls);s.next_retry=tick

static func can_contact(actor: Dictionary) -> bool:
    var f: Dictionary=actor.get("balok",{}).get("flight",{})
    if f.is_empty():return false
    return f.step>0 and int(f.aim_steps)/2>=int(f.steps)-int(f.step) and actor.height>=-40

static func finish(actor: Dictionary) -> void:
    state(actor).flight={}

static func interrupt(actor: Dictionary) -> void:
    # Retain the remake's interruptible airborne hit policy; this correction
    # does not introduce original-flight damage immunity.
    actor.balok={"retry":0,"next_retry":0,"flight":{}}
