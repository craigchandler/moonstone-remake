extends RefCounted

# Plain campaign identity, separate from stats, input ownership and artwork.
const NAME_MAX: int=13
const COLOURS=["Blue","Yellow","Green","Red"]
const DEFAULT_NAMES=["SIR_RICHARD","SIR_GODBER","SIR_JEFFREY","SIR_EDWARD"]
const SOURCE_START=Vector2i(15,100) # Solo record0, resetGame; selection changes kind, not position.

static func initial() -> Dictionary:return {"kind":0,"name":"SIR KNIGHT"}

static func valid(value: Variant) -> bool:
    if typeof(value)!=TYPE_DICTIONARY or value.size()!=2:return false
    var kind: Variant=value.get("kind")
    if typeof(kind) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(kind)) or float(kind)!=floor(float(kind)) or kind<0 or kind>3:return false
    var name: Variant=value.get("name")
    if typeof(name)!=TYPE_STRING or name.is_empty() or name.length()>NAME_MAX or name!=name.strip_edges():return false
    for ch in name:
        if ch.unicode_at(0)<32 or ch.unicode_at(0)>126:return false
    return true
