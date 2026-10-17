extends RefCounted

# Native states corresponding to retail roots 0845/0847 -> 0844 -> running,
# and 0849/084E. No original instructions are evaluated during play.
static func start(beast: Dictionary, stage: String, duration: int, victim: int = 0) -> void:
    beast.beast = {"stage":stage,"age":0,"duration":duration,"victim":victim}
    beast.action="idle";beast.remaining=0;beast.hit_targets=[]
    beast.reaction="";beast.reaction_remaining=0;beast.stagger_remaining=0
    beast.special_clip=stage;beast.special_duration=duration;beast.special_remaining=duration
    beast.terminal_clip=""

static func hurt(beast: Dictionary, stroke: String) -> void:
    var high: bool = stroke in ["heavy","upward"]
    start(beast,"hurt_a" if high else "hurt_b",54 if high else 42)

static func impact(beast: Dictionary) -> void:
    start(beast,"impact",12)

static func finish(beast: Dictionary, victim: Dictionary, sim: RefCounted) -> void:
    if victim.kind != "knight" or beast.health <= 0: return
    if beast.beast.get("stage","").begins_with("execution_"): return
    var same: bool = beast.facing == victim.facing
    var ally_alive:bool=false
    for other in sim.actors.values():
        if other.team==victim.team and other.health>0:ally_alive=true
    # 084E marks the knight dead before pose6 (11 holds at six ticks =66).
    # LAB_004B then allows 50 more creature steps. The seven-cycle draw list
    # is longer; a solo fight ends during its repeat rather than at its last cel.
    var duration: int = 258 if same else (582 if ally_alive else 366)
    start(beast,"execution_same" if same else "execution_opposite",duration,victim.id)
    victim.hidden_by=beast.id
    victim.down_remaining=duration;victim.down_duration=duration

static func eject(beast: Dictionary, victim: Dictionary) -> void:
    # Retail 0849 spawns the independent 084A victim job after the fifth cycle.
    # The upward/falling positions are in its recovered layers, not a made-up arc.
    victim.hidden_by=0
    victim.x=beast.x;victim.y=beast.y;victim.facing=beast.facing
    victim.visual_kind="war_beast";victim.defeat_clip="ejected"
    victim.down_remaining=180;victim.down_duration=180

static func resume(beast: Dictionary, sim: RefCounted) -> void:
    beast.beast={};beast.special_clip="";beast.special_remaining=0
    beast.action="beast_charge"
    beast.remaining=sim.rules.moves.beast_charge.active
    beast.leap_from_x=beast.x;beast.beast_phase=0;beast.hit_targets=[]
    beast.cooldown_remaining=0

static func death(beast: Dictionary, clip: String) -> void:
    beast.beast={"stage":clip,"age":0,"duration":beast.down_duration,"death":true}

static func advance(sim: RefCounted) -> void:
    for beast in sim.actors.values():
        if beast.kind != "war_beast" or beast.beast.is_empty(): continue
        var state: Dictionary = beast.beast
        state.age+=1
        if state.stage in ["hurt_a","defeat_a"]:
            if state.age in [6,12,18]: beast.x+=beast.facing*({6:24,12:16,18:10}[state.age])
        if state.get("death",false):
            if state.age>=state.duration:beast.beast={}
            continue
        beast.special_remaining=maxi(1,state.duration-state.age)
        if state.stage=="impact" and state.age==6:
            beast.y+=15
            beast.facing=-beast.facing
        if state.stage=="execution_same" and state.age==240:
            eject(beast,sim.actors[state.victim])
            sim.events.append({"type":"beast_eject","actor":beast.id,"victim":state.victim})
        if state.age<state.duration: continue
        match state.stage:
            "hurt_a","hurt_b": impact(beast)
            "impact": resume(beast,sim)
            "execution_same": impact(beast)
            "execution_opposite":
                var victim: Dictionary = sim.actors[state.victim]
                # Original fight ends on this composite's last repeated pose.
                # Keep it intact while a solo defeat is displayed.
                var ally_alive: bool = false
                for other in sim.actors.values():
                    if other.team==victim.team and other.health>0: ally_alive=true
                if not ally_alive:
                    beast.terminal_clip="execution_opposite"
                    beast.terminal_elapsed=state.age-1;beast.terminal_duration=582
                    beast.beast={};beast.special_remaining=0;beast.special_clip=""
                    beast.cooldown_remaining=1000000
                else:
                    # Native co-op continuation: separate the settled victim
                    # before the beast returns to the surviving knight.
                    eject(beast,victim)
                    victim.defeat_clip="settled";victim.down_remaining=0
                    impact(beast)

static func interrupt(sim: RefCounted, beast: Dictionary) -> void:
    for victim in sim.actors.values():
        if victim.hidden_by==beast.id:
            eject(beast,victim)
    beast.beast={};beast.special_clip="";beast.special_remaining=0;beast.terminal_clip=""
