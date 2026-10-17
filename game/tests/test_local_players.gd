extends SceneTree
func _initialize() -> void:run.call_deferred()
func run() -> void:
    var review: RefCounted=preload("res://debug/fixtures/local_players_review.gd").new()
    var result: Dictionary=await review.run_checks(root)
    if result.failures.is_empty():print("PASS:",result.checks," local player ownership, rounds, duels, save compatibility checks")
    else:
        for label in result.failures:push_error(label)
    quit(0 if result.failures.is_empty() else 1)
