extends RefCounted

static func prepare(rules: Resource,profile: String,site: String,knights: int) -> Dictionary:
    var script: Resource=rules.entry_placement
    if script==null or script.get("api_version")!=1 or String(script.behavior_id)!=profile:return {}
    var edge: Variant=script.site_edges.get(site,script.default_low_edge)
    if typeof(edge)!=TYPE_INT or edge<30 or edge>200:return {}
    var state: Dictionary={"profile":profile,"api":1,"version":int(script.content_version),
        "low_edge":edge,"counter":int(script.initial_counter)}
    if state.counter<0 or state.counter>3:return {}
    # Original placeAttacker consumes an entry before the creature list. The
    # existing native ally consumes one too; knight starting positions stay put.
    for n in range(knights):
        if next(rules,state)<0:return {}
    return state

static func next(rules: Resource,state: Dictionary) -> int:
    var script: Resource=rules.entry_placement
    if state.is_empty() or script==null or script.get("api_version")!=1:return -1
    if state.get("profile")!=String(script.behavior_id) or state.get("version")!=int(script.content_version) or state.get("api")!=1:return -1
    if typeof(state.get("counter"))!=TYPE_INT or state.counter<0 or state.counter>3:return -1
    if typeof(state.get("low_edge"))!=TYPE_INT or state.low_edge<30 or state.low_edge>200:return -1
    var result: Variant=script.decide({"counter":state.counter,"low_edge":state.low_edge})
    if not result is Dictionary or result.size()!=2:return -1
    if typeof(result.get("counter"))!=TYPE_INT or result.counter<1 or result.counter>3:return -1
    if typeof(result.get("depth"))!=TYPE_INT or result.depth<0 or result.depth>255:return -1
    state.counter=result.counter
    return result.depth
