extends RefCounted

const VERSION: int = 2
const MAX_PACKET: int = 65536
const INPUT_DELAY: int = 3
const INPUT_TTL: int = 10
const BUILD = preload("res://content/network_compatibility.json")
const ACTIONS = ["idle","block","swing","heavy","lunge","reverse","upward","dagger"]

static func fingerprint() -> String:
    if OS.has_feature("editor"):
        for path in BUILD.data.files:
            if FileAccess.get_sha256("res://"+path)!=BUILD.data.files[path]:return ""
    return String(BUILD.data.digest)

static func primitive(value: Variant, depth: int = 0) -> bool:
    if depth > 10: return false
    match typeof(value):
        TYPE_NIL,TYPE_BOOL,TYPE_VECTOR2I,TYPE_VECTOR2,TYPE_RECT2: return true
        TYPE_INT: return abs(value) <= 0xffffffff
        TYPE_FLOAT: return is_finite(value) and absf(value) < 10000000000.0
        TYPE_STRING,TYPE_STRING_NAME: return value.length() <= 160
        TYPE_ARRAY:
            if value.size() > 256: return false
            for item in value:
                if not primitive(item,depth+1): return false
            return true
        TYPE_DICTIONARY:
            if value.size() > 160: return false
            for key in value:
                if typeof(key) not in [TYPE_STRING,TYPE_STRING_NAME,TYPE_INT] or not primitive(value[key],depth+1): return false
            return true
    return false

static func encode(value: Dictionary) -> PackedByteArray:
    return var_to_bytes(value).compress(FileAccess.COMPRESSION_DEFLATE)

static func decode(bytes: PackedByteArray) -> Dictionary:
    if bytes.is_empty() or bytes.size() > MAX_PACKET: return {}
    var raw: PackedByteArray=bytes.decompress_dynamic(MAX_PACKET,FileAccess.COMPRESSION_DEFLATE)
    if raw.is_empty():return {}
    var value: Variant = bytes_to_var(raw) # Object decoding is deliberately disabled.
    return value if typeof(value)==TYPE_DICTIONARY and primitive(value) else {}

static func intent(value: Dictionary, round_id: int, tick: int, previous: int) -> bool:
    if value.size()!=6 or not value.has_all(["round","sequence","dx","dy","action","seen"]): return false
    for key in ["round","sequence","dx","dy","seen"]:
        if typeof(value[key])!=TYPE_INT: return false
    return value.round==round_id and value.sequence>previous and value.sequence<=previous+1000 and value.sequence<=0x7fffffff and abs(value.dx)<=1 and abs(value.dy)<=1 and value.seen>=0 and value.seen<=tick and typeof(value.action)==TYPE_STRING and value.action in ACTIONS

static func state_hash(state: Dictionary) -> String:
    var hash:=HashingContext.new()
    hash.start(HashingContext.HASH_SHA256);hash.update(var_to_bytes(state))
    return hash.finish().hex_encode()
