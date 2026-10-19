extends SceneTree

func _initialize() -> void: run.call_deferred()

func run() -> void:
    var review: RefCounted=preload("res://debug/fixtures/practice_review.gd").new()
    var result: Dictionary=await review.run_checks(root,"user://practice-unit-save.json")
    print("PRACTICE_STATE=",JSON.stringify(result))
    for failure in result.failures: push_error(failure)
    if result.failures.is_empty(): print("PASS: ",result.checks," normal classic practice, whole roster, colour/input, deterministic retries and solo/party campaign isolation checks")
    quit(0 if result.failures.is_empty() else 1)
