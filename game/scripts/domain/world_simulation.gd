class_name WorldSimulation
extends RefCounted

var definition: Resource
var tick: int = 0
var position: Vector2i
var facing: int = 1
var cleared: Dictionary = {}
var active_lair: String = ""
var entry_lock: String = ""
var last_result: String = ""
var dragon: RefCounted
var dragon_hoard: Vector2i = Vector2i(210, 90)
var terrain_counter: int = 0
var rival_records: Array = [] # Shared native records; empty for historical fixtures.
var rival_labels: Dictionary={} # Rebuilt from local player identities; no rule effect.
var last_step_cost: int = 0 # Current advance's movement event, consumed by session.

func _init(world_definition: Resource) -> void:
    definition = world_definition
    dragon = preload("res://scripts/domain/map_dragon.gd").new(definition.dragon_rules)
    restart()

func restart() -> void:
    rival_labels.clear()
    tick = 0
    position = definition.start_position
    facing = 1
    cleared.clear()
    active_lair = ""
    entry_lock = ""
    last_result = ""
    dragon.reset()
    dragon_hoard = Vector2i(210, 90)
    terrain_counter = 0
    last_step_cost = 0

func advance(direction: Vector2i, completed_rounds: int = 0, dragon_goal: Variant = null) -> String:
    last_step_cost = 0
    if not active_lair.is_empty(): return ""
    tick += 1
    if dragon.advance(completed_rounds, position if dragon_goal==null else dragon_goal, not cleared.has("roaming_dragon")):
        active_lair = "roaming_dragon"
        dragon_hoard = position
        last_result = ""
        return active_lair
    if tick % maxi(1, definition.ticks_per_step) != 0: return ""
    var mask: int = terrain_mask()
    if mask != 0:
        terrain_counter = (terrain_counter + 1) & 0xffff
        if (terrain_counter & mask) != 0: return ""
    direction = Vector2i(clampi(direction.x, -1, 1), clampi(direction.y, -1, 1))
    if direction == Vector2i.ZERO: return ""
    # As in the original, an allowed direction spends one point, including a
    # diagonal or an attempted step against the map edge. Blocked terrain is free.
    last_step_cost = 1
    if direction.x: facing = signi(direction.x)
    var bounds: Rect2i = definition.bounds
    position.x = clampi(position.x + direction.x, bounds.position.x, bounds.end.x - 1)
    position.y = clampi(position.y + direction.y, bounds.position.y, bounds.end.y - 1)
    # A failed/retreated lair stays locked until the knight walks out of its radius.
    # This prevents held movement or returning at the entrance from starting a loop.
    if not entry_lock.is_empty() and not inside_lair(lair(entry_lock)):
        entry_lock = ""
    for site in sites():
        var id: String = site.id
        if not rival_records.is_empty() and id in preload("res://scripts/domain/rival_knights.gd").IDS:continue
        if id == "roaming_dragon": continue # Only the living flight can attack.
        if definition.confirm_entry and id!="roaming_black_knight":continue
        if not cleared.has(id) and id != entry_lock and inside_lair(site):
            active_lair = id
            last_result = ""
            return id
    return ""

func inside_lair(site: Dictionary) -> bool:
    if definition.confirm_entry:
        return not site.is_empty() and preload("res://scripts/domain/map_locations.gd").touches(position,site.position,preload("res://scripts/domain/map_locations.gd").size_for(site))
    return not site.is_empty() and position.distance_squared_to(site.position) <= definition.entry_radius * definition.entry_radius

func terrain_mask() -> int:
    return 0 if definition.travel_rules == null else definition.travel_rules.mask_at(position)

func lair(id: String) -> Dictionary:
    for site in sites():
        if site.id == id: return site
    return {}

func sites() -> Array:
    var result: Array = definition.lairs.duplicate()
    for source in definition.special_encounters:
        var site: Dictionary = source.duplicate(true)
        if source.id == "roaming_dragon":
            site.position = dragon.position if dragon.active else dragon_hoard
        if not rival_records.is_empty() and source.id=="roaming_black_knight":continue
        if source.has("route") and not cleared.has(source.id):
            # A provisional native route; original roaming/turn AI remains separate.
            var route: Array = source.route
            var phase: int = tick / 200
            var progress: int = tick % 200
            var a: Vector2i = route[phase % route.size()]
            var b: Vector2i = route[(phase + 1) % route.size()]
            site.position = Vector2i(a.x + (b.x-a.x)*progress/200, a.y + (b.y-a.y)*progress/200)
        result.append(site)
    for index in range(rival_records.size()):
        var row: Dictionary=rival_records[index]
        result.append({"id":row.id,"name":rival_labels.get(row.id,"Black Knight %s" % ["I","II","III"][index]),"position":row.position,"encounter":&"black_knight_fight","region":"Wandering","experience":0,"marker":"K"})
    return result

func finish_lair(result: String) -> bool:
    if active_lair.is_empty() or result not in ["victory", "defeat", "draw", "ongoing"]:
        return false
    if result == "victory": cleared[active_lair] = true
    entry_lock = active_lair
    active_lair = ""
    last_result = "retreated" if result == "ongoing" else result
    return true

func complete() -> bool:
    return definition.lairs.all(func(site: Dictionary) -> bool: return cleared.has(site.id))

func snapshot() -> Dictionary:
    return {"schema": 3, "content": String(definition.content_id), "tick": tick,
        "position": {"x": position.x, "y": position.y}, "facing": facing,
        "cleared": cleared.duplicate(true), "active_lair": active_lair,
        "entry_lock": entry_lock, "last_result": last_result,
        "dragon": dragon.snapshot(), "dragon_hoard": {"x": dragon_hoard.x, "y": dragon_hoard.y},
        "terrain_counter": terrain_counter}
