extends RefCounted

# Semantic native IDs stay stable across saves. Reference use slots are0x0E
# (Acquisition/exchange8),0x0C(Hawk),0x10(Wyrm/exchange11).
static func targets(journey: RefCounted) -> Array[Dictionary]:
    var result: Array[Dictionary]=[]
    for row in journey.rivals.records:
        if row.character.lives>0:result.append(row)
    return result

static func objects(journey: RefCounted,row: Dictionary) -> Array[String]:
    var result: Array[String]=[]
    for id in journey.loot_rules.items:
        if int(row.inventory.items.get(id,0))>0:result.append(id)
    for id in journey.REGIONAL_KEYS:
        if int(row.keys)&int(journey.REGIONAL_KEYS[id].bit):result.append(id)
    for bit in range(4):
        if int(row.stones)&(1<<bit):result.append(journey.quest_rules.stone_ids[bit])
    return result

static func acquire(journey: RefCounted,selection: Variant) -> bool:
    if typeof(selection)!=TYPE_DICTIONARY or selection.size()!=2 or typeof(selection.get("rival"))!=TYPE_STRING or typeof(selection.get("item"))!=TYPE_STRING:return false
    var row: Dictionary=journey.rivals.find(selection.rival)
    if row.is_empty() or row.character.lives<=0:return false
    var id: String=selection.item
    if not id in objects(journey,row):
        journey.message="That object is no longer carried. Scroll kept."
        return false
    if journey.REGIONAL_KEYS.has(id):
        var bit: int=journey.REGIONAL_KEYS[id].bit
        if journey.owned_keys&bit:return false
        row.keys=int(row.keys)&~bit;journey.owned_keys|=bit
    elif id in journey.quest_rules.stone_ids:
        var bit: int=1<<journey.quest_rules.stone_ids.find(id)
        if journey.quest.stones&bit:return false
        row.stones=int(row.stones)&~bit;journey.quest.stones|=bit
    else:
        if int(journey.inventory.items.get(id,0))>=255:
            journey.message="Your pack cannot hold another. Scroll kept."
            return false
        journey.rivals.consume(row,id)
        journey.inventory.items[id]=int(journey.inventory.items.get(id,0))+1
        if id=="ring_of_protection":journey.character.health+=int(journey.character_rules.protection_health)
        var kit: RefCounted=journey.rivals.knight(row)
        kit.health=mini(kit.health,kit.maximum(row.inventory.items));row.character=kit.snapshot()
    journey.message="The chosen object is now in your pack."
    return true

static func send_wyrm(journey: RefCounted,id: Variant) -> bool:
    if typeof(id)!=TYPE_STRING:return false
    var row: Dictionary=journey.rivals.find(id)
    if row.is_empty() or row.character.lives<=0:return false
    var flight: RefCounted=journey.world.dragon
    if journey.world.cleared.has("roaming_dragon"):
        journey.message="The Dragon has been defeated. Scroll kept."
        return false
    if journey.calendar().completed_rounds<int(flight.rules.spawn_counter)*int(flight.rules.rounds_per_counter):
        journey.message="The Dragon has not appeared yet. Scroll kept."
        return false
    var slot: int=journey.rivals.records.find(row)+1
    if journey.dragon_order==slot or (flight.active and flight.target==slot):
        journey.message="The Dragon is already pursuing that knight. Scroll kept."
        return false
    journey.dragon_order=slot
    if flight.active:flight.target=slot
    journey.message="The Dragon will pursue the chosen knight."
    return true
