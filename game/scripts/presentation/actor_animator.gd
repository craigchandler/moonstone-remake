extends RefCounted

# Compatibility facade for sound cues and diagnostics. The semantic requests
# are also consumed by renderers that do not use classic sprite poses.
const Motion=preload("res://scripts/presentation/graphics/actor_motion.gd")
const Classic=preload("res://scripts/presentation/graphics/classic_pose_sampler.gd")
var motion: RefCounted=Motion.new()
var history: Dictionary:
    get: return motion.history
var motions: Dictionary:
    get: return motion.motions
var poses: Dictionary={}

func reset() -> void:
    motion.reset()
    poses.clear()

func update(actors: Dictionary, rules: Resource, art: Resource, elapsed_ticks: int = 1) -> void:
    motion.update(actors,rules,elapsed_ticks)
    poses.clear()
    for id in actors:
        var actor: Dictionary=actors[id]
        var family: String=actor.kind if actor.get("visual_kind","").is_empty() else actor.visual_kind
        var animation: Resource=art.animation_for(family)
        if animation!=null:poses[id]=Classic.sample(animation,motions[id],art.attack_returns.get(actor.kind,{}))
