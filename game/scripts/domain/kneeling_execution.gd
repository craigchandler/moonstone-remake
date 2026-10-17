extends RefCounted

# Death presentation has a finite kneeling interval. No new HP, reward or life
# transaction occurs when an independently collected second strike connects.
static func window(model: RefCounted,victim: Dictionary) -> Vector2i:
    if victim.health>0 or victim.hidden_by!=0 or victim.vanished or victim.down_remaining<=0:return Vector2i.ZERO
    if not model.rules.actor_definitions[victim.kind].execution_vulnerable or victim.visual_kind!="death_knight":return Vector2i.ZERO
    return model.rules.finishes.kneeling_windows.get(victim.defeat_clip,Vector2i.ZERO)

static func available(model: RefCounted,victim: Dictionary) -> bool:
    var interval: Vector2i=window(model,victim)
    return interval.y>0 and victim.down_duration-victim.down_remaining<interval.y

static func can_hit(model: RefCounted,attacker: Dictionary,victim: Dictionary) -> bool:
    if attacker.health<=0 or attacker.team==victim.team:return false
    var definition: Resource=model.rules.actor_definitions[attacker.kind]
    if definition.execution_clip.is_empty() or attacker.action not in definition.execution_moves:return false
    var interval: Vector2i=window(model,victim)
    var elapsed: int=victim.down_duration-victim.down_remaining
    return interval.y>0 and elapsed>=interval.x and elapsed<interval.y

static func target(model: RefCounted,attacker: Dictionary) -> Dictionary:
    var definition: Resource=model.rules.actor_definitions[attacker.kind]
    if definition.execution_ai_move.is_empty():return {}
    var nearest: Dictionary={};var distance: int=100000
    var ids: Array=model.actors.keys();ids.sort()
    for id in ids:
        var candidate: Dictionary=model.actors[id]
        if candidate.team==attacker.team or not available(model,candidate):continue
        var d: int=abs(candidate.x-attacker.x)+abs(candidate.y-attacker.y)
        if d<distance:nearest=candidate;distance=d
    return nearest

static func apply(model: RefCounted,attacker: Dictionary,victim: Dictionary) -> bool:
    if not can_hit(model,attacker,victim):return false
    var clip: String=model.rules.actor_definitions[attacker.kind].execution_clip
    var inherited_facing: int=victim.facing*int(model.rules.finishes.kneeling_facing_signs.get(victim.defeat_clip,1))
    model.knock_down(victim,clip)
    victim.facing=inherited_facing
    victim.visual_kind="death_knight"
    model.events.append({"type":"execution","actor":victim.id,"attacker":attacker.id,"move":attacker.action})
    return true

static func survives_hits(_model: RefCounted,attacker: Dictionary,hits: Array[Dictionary]) -> bool:
    var damage: int=0
    for hit in hits:
        if hit.actor!=attacker.id or hit.get("execution",false):continue
        if hit.move in ["balok_pounce","balok_hop"] and attacker.kind=="knight":return false
        damage+=int(hit.amount)
    return attacker.health>damage
