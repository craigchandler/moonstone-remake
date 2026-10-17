extends SceneTree
const Review=preload("res://debug/fixtures/trogg_timing_review.gd")
func _initialize() -> void:run.call_deferred()
func run() -> void:
    var result: Dictionary=Review.new().run_checks()
    if result.failures.is_empty():print("PASS:",result.checks," mirrored Trogg drawing/phase/contact/defence and live-repeat checks")
    else:
        for failure in result.failures.slice(0,12):push_error(failure)
    quit(0 if result.failures.is_empty() else 1)
