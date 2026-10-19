extends RefCounted

# Translate authoritative clocks into semantic animation requests. This layer
# knows no textures, atlases, source rectangles or renderer frame numbers.
var history: Dictionary = {}
var motions: Dictionary = {}

func reset() -> void:
    history.clear()
    motions.clear()

func update(actors: Dictionary, rules: Resource, elapsed_ticks: int = 1) -> void:
    motions.clear()
    for id in actors:
        var actor: Dictionary = actors[id]
        var point := Vector2i(actor.x, actor.y)
        var previous: Dictionary = history.get(id, {"point": point, "walk_ticks": 0})
        var movement: Vector2i = point - previous.point
        var walk_ticks: int = previous.walk_ticks + maxi(1,elapsed_ticks) if movement != Vector2i.ZERO else 0
        history[id] = {"point": point, "walk_ticks": walk_ticks}
        var definition: Resource = rules.actor_definitions[actor.kind]
        if actor.health <= 0:
            var duration: int = int(actor.get("down_duration", 0))
            if duration == 0: duration = definition.defeat_duration(actor.defeat_clip)
            motions[id] = sample(actor.defeat_clip, duration - actor.down_remaining, duration)
        elif not actor.get("beast",{}).is_empty():
            var state:Dictionary=actor.beast
            motions[id]=sample(state.stage,state.age,582 if state.stage=="execution_opposite" else state.duration)
        elif not actor.get("interaction", {}).is_empty():
            var sequence: Dictionary = actor.interaction
            var elapsed: int = sequence.elapsed
            motions[id] = sample(sequence.stage,elapsed,sequence.duration)
        elif actor.get("held_target", 0) != 0:
            if actor.hold_kind=="squeeze":
                motions[id]=sample(actor.special_clip,actor.rat_phase_elapsed,rules_rat_hold_duration(actor.special_clip))
                continue
            var elapsed: int = actor.hold_elapsed
            var clip: String = actor.special_clip
            var duration: int = 30 if clip == "rat_squeeze" else 12
            motions[id] = sample(clip, mini(elapsed, duration-1) if clip == "rat_squeeze" else elapsed%duration, duration)
        elif actor.get("special_remaining", 0) > 0:
            if actor.special_clip == "rat_air": motions[id] = sample("rat_air", (actor.special_duration-actor.special_remaining)/6)
            else: motions[id] = sample(actor.special_clip, actor.special_duration-actor.special_remaining, actor.special_duration)
        elif not actor.get("terminal_clip", "").is_empty():
            motions[id] = sample(actor.terminal_clip, actor.get("terminal_elapsed",71), actor.get("terminal_duration",72))
        elif actor.reaction_remaining > 0:
            var duration: int = rules.guard_feedback_ticks if actor.reaction == "block" else definition.reaction_ticks
            if actor.reaction != "block" and actor.get("reaction_duration",0)>0: duration=actor.reaction_duration

            motions[id] = sample(actor.reaction, duration - actor.reaction_remaining, duration)
        elif actor.remaining > 0 and rules.moves.has(actor.action):
            var move: Dictionary = preload("res://scripts/domain/ratman_combat.gd").move(rules,actor) if actor.kind=="ratman" else preload("res://scripts/domain/balok_combat.gd").move(rules,actor)
            if actor.get("attack_flow",{}).get("branch","") == "contact":
                var timing: Dictionary = rules.attack_timing.moves[actor.action]
                if actor.kind in ["knight","black_knight"] and actor.action=="swing":
                    # Hold the impact drawing until the next source-script pass,
                    # then finish the visible blade path without extra contacts.
                    var duration: int=int(timing.contact_hold+timing.contact_return)
                    if actor.remaining>duration:
                        motions[id]=sample(actor.action,actor.attack_flow.impact_elapsed,move.active,"active")
                    else:
                        motions[id]=sample(actor.action,duration-actor.remaining,duration,"follow_through")
                        motions[id]["from_active"]=actor.attack_flow.impact_elapsed
                        motions[id]["active_duration"]=move.active
                    motions[id]["silent_transition"]=true
                elif actor.remaining > timing.contact_return:
                    motions[id]=sample(actor.action,actor.attack_flow.impact_elapsed,move.active,"active")
                else:
                    motions[id]=sample("idle",999,1000)
                    motions[id]["return_pose"]=true
                continue
            var elapsed: int = move.windup + move.active + move.recovery - actor.remaining
            if actor.action in ["dragon_flight", "dragon_lower"]:
                motions[id] = sample(actor.action, mini(7, elapsed/6))
                continue
            if actor.action == "dragon_foot":
                motions[id] = sample("idle", 0)
                continue
            if actor.action == "rat_leap":
                if elapsed < move.windup: motions[id] = sample("idle", 0)
                elif elapsed < move.windup+move.active: motions[id] = sample("rat_air", (elapsed-move.windup)/6)
                elif actor.rat_tree:motions[id]=sample("rat_perch",1 if actor.rat_perch_near else 0,2)
                else:motions[id]=sample("rat_land",(elapsed-move.windup-move.active)%12,12)
                continue
            if actor.action == "beast_charge":
                motions[id] = sample("beast_charge", int(actor.beast_phase))
                continue
            var phase: String = "windup"
            var duration: int = move.windup
            if elapsed >= move.windup + move.active:
                elapsed -= move.windup + move.active
                phase = "recovery"
                duration = move.recovery
            elif elapsed >= move.windup:
                elapsed -= move.windup
                phase = "active"
                duration = move.active
            motions[id] = sample(actor.action, elapsed, duration, phase)
        elif actor.guarding:
            motions[id] = sample("block", 0)
        elif movement != Vector2i.ZERO:
            if actor.kind == "dragon":
                motions[id] = sample("dragon_flight", 7) if actor.dragon_raised else sample("idle", 0)
                continue
            var clip: String = "walk"
            if movement.x == 0:
                clip = "walk_away" if movement.y < 0 else "walk_toward"
            var cadence: int = definition.walk_pose_ticks
            motions[id] = sample(clip, (walk_ticks - 1) / cadence)
            motions[id]["cycle_step"] = true
        else:
            motions[id] = sample("dragon_flight", 7) if actor.kind == "dragon" and actor.get("dragon_raised", false) else sample("idle", 0)

func sample(clip: String, elapsed: int, duration: int=0, phase: String="") -> Dictionary:
    return {"clip":clip,"elapsed":elapsed,"duration":duration,"phase":phase}

func feet(actor: Dictionary, rules: Resource) -> Dictionary:
    if actor.action=="dragon_foot" and actor.remaining>0:
        var move: Dictionary=rules.moves.dragon_foot
        var duration: int=move.windup+move.active+move.recovery
        return sample("dragon_foot",duration-actor.remaining,duration)
    return sample("feet_down" if actor.health<=0 else "feet_idle",0)

func rules_rat_hold_duration(clip: String) -> int:
    return preload("res://scripts/domain/ratman_hold.gd").duration(clip)
