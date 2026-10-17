extends SceneTree
var review: RefCounted
func _initialize() -> void:run.call_deferred()
func run() -> void:
    review=preload("res://debug/fixtures/controller_review.gd").new()
    var result: Dictionary=await review.run_checks(root)
    if result.failures.is_empty():print("PASS:",result.checks," controller mapping/menu/gameplay/pause/connection checks; eight full-state session traces")
    else:
        for failure in result.failures:push_error(failure)
    quit(0 if result.failures.is_empty() else 1)
