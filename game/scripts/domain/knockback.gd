extends RefCounted

# Shared rules and actor-owned progress. Artwork and original runtime are absent.
static func start(actor:Dictionary,direction:int,content:Resource,tick:int)->void:
    actor.motion={"direction":1 if direction>0 else -1,"next_step":0,"started_tick":tick}
    advance(actor,tick,content)

static func advance(actor:Dictionary,tick:int,content:Resource)->void:
    if actor.motion.is_empty():return
    var state:Dictionary=actor.motion
    var elapsed:int=tick-state.started_tick
    while state.next_step<content.hop_steps.size() and state.next_step*content.step_ticks<=elapsed:
        var front:int=actor.x+content.front_offset*state.direction
        var blocked:bool=front>content.right_limit if state.direction>0 else front<content.left_limit
        if not blocked:actor.x+=content.hop_steps[state.next_step]*state.direction
        state.next_step+=1
    if state.next_step>=content.hop_steps.size():actor.motion={}

static func walk_x(x:int,delta:int)->int:
    # A source hop can overshoot the ordinary native movement bounds. Vertical
    # input must not teleport it back; horizontal input walks back gradually.
    if x>298:return x+mini(delta,0)
    if x<22:return x+maxi(delta,0)
    return clampi(x+delta,22,298)
