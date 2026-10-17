extends SceneTree
func _initialize() -> void:
    var review: RefCounted=preload("res://debug/fixtures/monster_timing_review.gd").new()
    var result: Dictionary=review.run_checks()
    if result.failures.is_empty():print("PASS:",result.checks," consolidated timing checks;16 independent retail-hold scenes and28 live AI/replay scenes")
    else:
        for failure in result.failures.slice(0,16):push_error(failure)
    quit(0 if result.failures.is_empty() else 1)
