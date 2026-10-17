class_name MoonstoneAnimationSet
extends Resource

const Timing = preload("res://scripts/domain/weighted_frames.gd")

@export var atlases: Dictionary = {}
@export var default_variant: String = ""
@export var poses: Array[Dictionary] = []
@export var clips: Dictionary = {}

func atlas_for(variant: String) -> Texture2D:
    return atlases.get(variant, atlases.get(default_variant))

func sample(clip_name: String, elapsed: int, duration: int = 0, phase: String = "") -> Dictionary:
    var clip: Dictionary = clips.get(clip_name, clips.get("idle", {}))
    if clip.is_empty():
        return {}
    var frames: Array = clip.frames
    if not phase.is_empty() and clip.get("phases", {}).has(phase):
        frames = clip.phases[phase]
    var frame: int
    if duration > 0:
        # Allocate each rule phase across its poses, retaining original hold ratios.
        var weights: Array = clip.weights
        if not phase.is_empty() and clip.get("phases", {}).has(phase):
            weights = []
            for index in frames:
                weights.append(clip.weights[clip.frames.find(index)])
        frame = frames[Timing.select(weights, elapsed, duration)]
    else:
        frame = frames[int(elapsed / int(clip.step_ticks)) % frames.size()]
    return {"index": frame, "region": poses[frame].region, "offset": poses[frame].offset,
        "clip": clip_name, "phase": phase}
