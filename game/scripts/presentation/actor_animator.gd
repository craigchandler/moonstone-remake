extends RefCounted

# Presentation history only; never written into the simulation or replay state.
var history: Dictionary = {}
var poses: Dictionary = {}

func reset() -> void:
    history.clear()
    poses.clear()

func update(actors: Dictionary, rules: Resource, art: Resource) -> void:
    poses.clear()
    for id in actors:
        var actor: Dictionary = actors[id]
        var visual: String = actor.get("visual_kind", "")
        var animations: Resource = art.animation_for(actor.kind if visual.is_empty() else visual)
        if animations == null:
            continue
        var point := Vector2i(actor.x, actor.y)
        var previous: Dictionary = history.get(id, {"point": point, "walk_ticks": 0})
        var movement: Vector2i = point - previous.point
        var walk_ticks: int = previous.walk_ticks + 1 if movement != Vector2i.ZERO else 0
        history[id] = {"point": point, "walk_ticks": walk_ticks}
        var definition: Resource = rules.actor_definitions[actor.kind]
        if actor.health <= 0:
            var duration: int = int(actor.get("down_duration", 0))
            if duration == 0: duration = definition.defeat_duration(actor.defeat_clip)
            poses[id] = animations.sample(actor.defeat_clip, duration - actor.down_remaining, duration)
        elif not actor.get("beast",{}).is_empty():
            var state:Dictionary=actor.beast
            poses[id]=animations.sample(state.stage,state.age,582 if state.stage=="execution_opposite" else state.duration)
        elif not actor.get("interaction", {}).is_empty():
            var sequence: Dictionary = actor.interaction
            var elapsed: int = sequence.elapsed
            poses[id] = animations.sample(sequence.stage,elapsed,sequence.duration)
        elif actor.get("held_target", 0) != 0:
            if actor.hold_kind=="squeeze":
                poses[id]=animations.sample(actor.special_clip,actor.rat_phase_elapsed,rules_rat_hold_duration(actor.special_clip))
                continue
            var elapsed: int = actor.hold_elapsed
            var clip: String = actor.special_clip
            var duration: int = 30 if clip == "rat_squeeze" else 12
            poses[id] = animations.sample(clip, mini(elapsed, duration-1) if clip == "rat_squeeze" else elapsed%duration, duration)
        elif actor.get("special_remaining", 0) > 0:
            if actor.special_clip == "rat_air": poses[id] = animations.sample("rat_air", (actor.special_duration-actor.special_remaining)/6)
            else: poses[id] = animations.sample(actor.special_clip, actor.special_duration-actor.special_remaining, actor.special_duration)
        elif not actor.get("terminal_clip", "").is_empty():
            poses[id] = animations.sample(actor.terminal_clip, actor.get("terminal_elapsed",71), actor.get("terminal_duration",72))
        elif actor.reaction_remaining > 0:
            var duration: int = rules.guard_feedback_ticks if actor.reaction == "block" else definition.reaction_ticks
            if actor.reaction != "block" and actor.get("reaction_duration",0)>0: duration=actor.reaction_duration

            poses[id] = animations.sample(actor.reaction, duration - actor.reaction_remaining, duration)
        elif actor.remaining > 0 and rules.moves.has(actor.action):
            var move: Dictionary = rules.moves[actor.action]
            if actor.get("attack_flow",{}).get("branch","") == "contact":
                var timing: Dictionary = rules.attack_timing.moves[actor.action]
                if actor.remaining > timing.contact_return:
                    poses[id] = animations.sample(actor.action,actor.attack_flow.impact_elapsed,move.active,"active")
                else:
                    var ready: Dictionary = art.attack_returns.get(actor.kind,{"clip":"idle","phase":""})
                    poses[id] = animations.sample(ready.clip,999,1000,ready.phase)
                    poses[id]["silent_transition"] = true
                continue
            var elapsed: int = move.windup + move.active + move.recovery - actor.remaining
            if actor.action in ["dragon_flight", "dragon_lower"]:
                poses[id] = animations.sample(actor.action, mini(7, elapsed/6))
                continue
            if actor.action == "dragon_foot":
                poses[id] = animations.sample("idle", 0)
                continue
            if actor.action == "rat_leap":
                if elapsed < move.windup: poses[id] = animations.sample("idle", 0)
                elif elapsed < move.windup+move.active: poses[id] = animations.sample("rat_air", (elapsed-move.windup)/6)
                elif actor.rat_tree:poses[id]=animations.sample("rat_perch",1 if actor.rat_perch_near else 0,2)
                else:poses[id]=animations.sample("rat_land",(elapsed-move.windup-move.active)%12,12)
                continue
            if actor.action == "beast_charge":
                poses[id] = animations.sample("beast_charge", int(actor.beast_phase))
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
            poses[id] = animations.sample(actor.action, elapsed, duration, phase)
        elif actor.guarding:
            poses[id] = animations.sample("block", 0)
        elif movement != Vector2i.ZERO:
            if actor.kind == "dragon":
                poses[id] = animations.sample("dragon_flight", 7) if actor.dragon_raised else animations.sample("idle", 0)
                continue
            var clip: String = "walk"
            if movement.x == 0:
                clip = "walk_away" if movement.y < 0 else "walk_toward"
            var cadence: int = definition.walk_pose_ticks
            poses[id] = animations.sample(clip, (walk_ticks - 1) / cadence * int(animations.clips[clip].step_ticks))
        else:
            poses[id] = animations.sample("dragon_flight", 7) if actor.kind == "dragon" and actor.get("dragon_raised", false) else animations.sample("idle", 0)

func rules_rat_hold_duration(clip: String) -> int:
    return preload("res://scripts/domain/ratman_hold.gd").duration(clip)
