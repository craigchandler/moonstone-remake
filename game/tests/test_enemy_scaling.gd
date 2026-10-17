extends SceneTree
const Review=preload("res://debug/fixtures/enemy_scaling_review.gd")
const Host=preload("res://scripts/domain/encounter_scaling_host.gd")
const Base=preload("res://scripts/gameplay/encounter_scaling.gd")
class Replacement extends Base:
    var answer: Variant={"count":2,"concurrent":1}
    func decide(facts: Dictionary) -> Dictionary:
        facts.strength=999 # A copied context cannot change the caller.
        return answer if answer is Dictionary else {}
func _initialize() -> void:run.call_deferred()
func run() -> void:
    var result: Dictionary=Review.new().run_checks("res://tests/fixtures/enemy_scaling.json")
    var rules: Resource=preload("res://content/foundation_rules.tres").duplicate(true)
    var replacement: Resource=Replacement.new();replacement.behavior_id=&"test:replacement"
    rules.encounter_scaling=replacement
    var facts: Dictionary={"strength":1}
    if Host.options(rules,facts)!={"count":2,"concurrent":1} or facts.strength!=1:result.failures.append("replaceable copied-data behaviour")
    for invalid in [{},{"count":0,"concurrent":1},{"count":61,"concurrent":1},{"count":1,"concurrent":5},{"count":1.5,"concurrent":1},{"count":1,"concurrent":1,"extra":true}]:
        replacement.answer=invalid
        if not Host.options(rules,facts).is_empty():result.failures.append("malformed scaling request accepted")
    replacement.api_version=2;replacement.answer={"count":2,"concurrent":1}
    if not Host.options(rules,facts).is_empty():result.failures.append("unsupported script API accepted")
    if result.failures.is_empty():print("PASS:",result.checks," independent scaling checks plus8 script-boundary cases; 4608 table/threshold and360 live lair expectations")
    else:
        for message in result.failures.slice(0,8):push_error(message)
    quit(0 if result.failures.is_empty() else 1)
