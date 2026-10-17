extends SceneTree
const Journey=preload("res://scripts/session/journey_session.gd")
const Store=preload("res://scripts/session/journey_store.gd")
func _initialize() -> void:
    run.call_deferred()
func run() -> void:
    var journey: RefCounted=Journey.new(load("res://content/first_journey.tres"),load("res://content/foundation_rules.tres"),123)
    var path: String="user://debug-mode-unit-"+str(OS.get_process_id())+".json"
    var normal: RefCounted=Store.new(path,journey.validate_checkpoint)
    if not normal.save_checkpoint(journey.checkpoint()):push_error("normal save must work");quit(1);return
    journey.inventory.gold+=1
    if not normal.save_checkpoint(journey.checkpoint()) or not FileAccess.file_exists(path+".bak"):push_error("normal backup must work");quit(1);return
    var temporary: FileAccess=FileAccess.open(path+".tmp",FileAccess.WRITE);temporary.store_string("existing temporary sentinel");temporary.close()
    var review: RefCounted=preload("res://debug/fixtures/debug_mode_review.gd").new()
    var result: Dictionary=await review.run_checks(root,path)
    for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(path+suffix)
    if result.failures.is_empty():print("PASS:",result.checks," debug action/hint guards, explicit launch parsing, session-only progress and unchanged existing save/backup/temp/preferences; normal disk saves retained")
    else:
        for failure in result.failures:push_error(failure)
    quit(0 if result.failures.is_empty() else 1)
