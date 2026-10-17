extends RefCounted

# Presentation history only. Sound choices must never consume simulation RNG.
# Pose cues follow the same weighted poses visible to the player, including when
# native windup/contact/recovery clocks stretch an original animation.
var history: Dictionary = {}
var choices: Dictionary = {}
var last_tick: int = -1

func reset() -> void:
    history.clear()
    choices.clear()
    last_tick = -1

func collect(model: RefCounted, poses: Dictionary, art: Resource, pack: Resource) -> Dictionary:
    var result: Dictionary = {"cues": [], "changed": []}
    if model.tick == last_tick: return result
    if model.tick < last_tick: reset()
    last_tick = model.tick
    var restarted: Dictionary = {}
    for event in model.events:
        if event.type in ["attack", "damage", "down", "spawn", "escape", "hold_cycle", "execution"]:
            restarted[int(event.actor)] = true
        if event.type == "hold":
            restarted[int(event.actor)] = true
            if event.get("restart_attacker",true):restarted[int(event.attacker)] = true
        if event.type == "parry":
            for cue in pack.cues.get("parry", []):
                result.cues.append({"key":cue,"actor":int(event.actor)})
    for id in poses:
        if not model.actors.has(id): continue
        var actor: Dictionary = model.actors[id]
        if int(actor.get("hidden_by", 0)) != 0 or actor.get("vanished", false):
            if history.erase(id): result.changed.append(id)
            continue
        var family: String = actor.get("visual_kind", "")
        if family.is_empty(): family = actor.kind
        if family == "black_knight": family = "knight"
        var animation: Resource = art.animation_for(family)
        var pose: Dictionary = poses[id]
        if pose.get("silent_transition",false):
            if history.get(id,{}).get("key","") != "return": result.changed.append(id)
            history[id] = {"key":"return","position":-1}
            continue
        if animation == null or not animation.clips.has(pose.clip): continue
        var frames: Array = animation.clips[pose.clip].frames
        var position: int = frames.find(pose.index)
        var key: String = family + ":" + String(pose.clip)
        var previous: Dictionary = history.get(id, {})
        var changed: bool = previous.get("key", "") != key or restarted.has(id)
        var before: int = -1 if changed else int(previous.get("position", -1))
        if position < before:
            changed = true # a walking/held animation has wrapped
            before = -1
        if changed: result.changed.append(id)
        for entry in pack.timelines.get(family, {}).get(pose.clip, []):
            if int(entry.pose) <= before or int(entry.pose) > position: continue
            var pick_key: String = family + ":" + str(entry.source)
            var index: int = int(choices.get(pick_key, -1)) + 1
            choices[pick_key] = index
            for cue in entry.options[index % entry.options.size()]:
                result.cues.append({"key":cue,"actor":id})
        history[id] = {"key":key,"position":position}
    for id in history.keys():
        if not poses.has(id):
            history.erase(id)
            result.changed.append(id)
    return result
