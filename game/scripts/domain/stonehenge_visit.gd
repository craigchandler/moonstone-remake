extends RefCounted

# Mechanics are independent of the classic drawings. Source: hunk2:142,
# hunk42:516, rules/rituals.cpp danuBlessing. Fade/loading clocks are provisional.
const POSITION = Vector2i(88,155)
const RITUAL_TICKS = 528
const PRELUDE_TICKS = 50

static func valid(value: Variant, integer: Callable, item_ids: Array) -> bool:
    if typeof(value)!=TYPE_DICTIONARY: return false
    if value.is_empty(): return true
    if value.size()!=3 or value.get("phase") not in ["greeting","offering","prelude","ritual","temple"]: return false
    if typeof(value.get("offered"))!=TYPE_STRING: return false
    var phase: String=value.phase
    if phase in ["greeting","offering"] and value.offered!="": return false
    if phase in ["prelude","ritual"] and not value.offered in item_ids: return false
    if phase=="temple" and value.offered!="" and not value.offered in item_ids: return false
    var limit: int=PRELUDE_TICKS-1 if phase=="prelude" else (RITUAL_TICKS-1 if phase=="ritual" else 0)
    return integer.call(value.get("tick"),0,limit)
