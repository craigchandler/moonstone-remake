extends RefCounted

const Timing=preload("res://scripts/domain/weighted_frames.gd")

static func sample(animation: Resource, motion: Dictionary, ready: Dictionary={}) -> Dictionary:
    if motion.get("return_pose",false):
        var pose: Dictionary=animation.sample(ready.get("clip","idle"),999,1000,ready.get("phase",""))
        pose["silent_transition"]=true
        return pose
    if motion.phase=="follow_through":
        return follow_through(animation,motion)
    var elapsed: int=motion.elapsed
    if motion.get("cycle_step",false):elapsed*=int(animation.clips[motion.clip].step_ticks)
    var result: Dictionary=animation.sample(motion.clip,elapsed,motion.duration,motion.phase)
    if motion.get("silent_transition",false):result["silent_transition"]=true
    return result

static func follow_through(animation: Resource,motion: Dictionary) -> Dictionary:
    # Continue from the real impact pose through the existing classic clip.
    # Only artwork is sampled; this path never reads/writes simulation objects.
    var clip: Dictionary=animation.clips[motion.clip]
    var impact: Dictionary=animation.sample(motion.clip,motion.from_active,motion.active_duration,"active")
    var first: int=clip.frames.find(impact.index)
    var selected: int=first+Timing.select(clip.weights.slice(first),motion.elapsed,motion.duration)
    var elapsed: int=0
    var duration: int=0
    for i in clip.weights.size():
        if i<selected:elapsed+=int(clip.weights[i])
        duration+=int(clip.weights[i])
    var pose: Dictionary=animation.sample(motion.clip,elapsed,duration)
    pose["phase"]=motion.phase
    pose["silent_transition"]=true
    return pose
