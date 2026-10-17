extends RefCounted

# Presentation history only. These particles never enter saves, collision or RNG.
var active: Array[Dictionary] = []
var last_tick: int = -1

func reset() -> void:
    active.clear()
    last_tick = -1

func update(model: RefCounted, art: Resource) -> void:
    if model.tick == last_tick: return
    if model.tick < last_tick: reset()
    last_tick = model.tick
    for i in range(active.size()-1,-1,-1):
        if model.tick-active[i].born >= active[i].duration: active.remove_at(i)
    for event in model.events:
        if event.type != "hit_effect": continue
        var animation: Resource = art.effects.get(event.effect)
        if animation == null or not animation.clips.has("burst"): continue
        var clip: Dictionary = animation.clips.burst
        var duration: int = int(clip.step_ticks)*clip.frames.size()
        if active.size() >= 32: active.pop_front()
        active.append({"kind":event.effect,"x":event.x,"y":event.y,
            "facing":event.facing,"born":model.tick,"duration":duration})
