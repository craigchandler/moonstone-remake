class_name MoonstoneCombatGeometry
extends Resource

const Timing = preload("res://scripts/domain/weighted_frames.gd")
@export var attacks: Dictionary = {}

func points_for(move: String, elapsed: int, duration: int) -> Array:
    var frames: Array = attacks.get(move, [])
    if frames.is_empty():
        return []
    var weights: Array = []
    for frame in frames:
        weights.append(frame.weight)
    return frames[Timing.select(weights, elapsed, duration)].points
