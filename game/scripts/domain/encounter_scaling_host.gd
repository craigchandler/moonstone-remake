extends RefCounted

static func manifest(rules: Resource) -> Dictionary:
    var script: Resource=rules.encounter_scaling
    return {String(script.behavior_id):{"api":script.api_version,"version":script.content_version}}

static func valid(result: Variant) -> bool:
    if not result is Dictionary or result.size()!=2:return false
    return typeof(result.get("count"))==TYPE_INT and result.count>=1 and result.count<=60 and typeof(result.get("concurrent"))==TYPE_INT and result.concurrent>=1 and result.concurrent<=4

static func options(rules: Resource, facts: Dictionary) -> Dictionary:
    var script: Resource=rules.encounter_scaling
    if script==null or not script.has_method("decide") or script.get("api_version")!=1:return {}
    var result: Variant=script.decide(facts.duplicate(true))
    return result.duplicate(true) if valid(result) else {}
