extends SceneTree
const Review=preload("res://debug/fixtures/entry_lanes_review.gd")
const Host=preload("res://scripts/domain/entry_placement_host.gd")
const Base=preload("res://scripts/gameplay/entry_placement.gd")
class Replacement extends Base:
    var answer: Dictionary={"counter":2,"depth":150}
    func decide(facts: Dictionary) -> Dictionary:
        facts.counter=999
        return answer
func _initialize() -> void:run.call_deferred()
func run() -> void:
    var result: Dictionary=Review.new().run_checks("res://tests/fixtures/beast_entries.json")
    var rules: Resource=preload("res://content/foundation_rules.tres").duplicate(true)
    var replacement: Resource=Replacement.new();replacement.behavior_id=&"test:entry"
    rules.entry_placement=replacement
    var state: Dictionary={"profile":"test:entry","api":1,"version":1,"counter":1,"low_edge":123}
    if Host.next(rules,state)!=150 or state.counter!=2:result.failures.append("replaceable copied-facts policy")
    for invalid in [{},{"counter":0,"depth":150},{"counter":4,"depth":150},{"counter":2,"depth":-1},{"counter":2,"depth":256},{"counter":2.0,"depth":150},{"counter":2,"depth":150.0},{"counter":2,"depth":150,"extra":true}]:
        replacement.answer=invalid
        var before: Dictionary=state.duplicate(true)
        if Host.next(rules,state)!=-1 or state!=before:result.failures.append("invalid output partially changes cursor")
    replacement.api_version=2
    if Host.next(rules,state)!=-1:result.failures.append("unsupported entry API")
    if result.failures.is_empty():print("PASS:",result.checks," entry checks plus10 policy-boundary cases")
    else:
        for failure in result.failures.slice(0,8):push_error(failure)
    quit(0 if result.failures.is_empty() else 1)
