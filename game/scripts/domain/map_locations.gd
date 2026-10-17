extends RefCounted

# Retail map nodes hunk2:100. Coordinates are sprite top left, not a dot/feet.
const PLACES: Array[Dictionary]=[
    {"id":"home","name":"Home castle","sprite":21,"position":Vector2i(18,11),"size":Vector2i(24,19),"services":["temple"]},
    {"id":"village_yellow","name":"Yellow knight's home","sprite":22,"position":Vector2i(286,11),"size":Vector2i(24,14)},
    {"id":"village_green","name":"Green knight's home","sprite":23,"position":Vector2i(0,187),"size":Vector2i(23,11)},
    {"id":"village_red","name":"Red knight's home","sprite":24,"position":Vector2i(303,192),"size":Vector2i(15,8)},
    {"id":"highwood","name":"Highwood","sprite":25,"position":Vector2i(82,28),"size":Vector2i(25,32)},
    {"id":"waterdeep","name":"Waterdeep","sprite":26,"position":Vector2i(277,143),"size":Vector2i(32,28)},
    {"id":"valley_guardian","name":"Valley of the Gods","sprite":28,"position":Vector2i(152,97),"size":Vector2i(13,10)},
    {"id":"stonehenge","name":"Stonehenge","sprite":27,"position":Vector2i(88,155),"size":Vector2i(18,12)},
    {"id":"wizard","name":"Math the wizard's tower","sprite":30,"position":Vector2i(217,11),"size":Vector2i(7,20),"services":["temple"]}
]

static func place(id: String) -> Dictionary:
    for row in PLACES:
        if row.id==id:return row
    return {}

static func home(kind: int) -> Dictionary:
    var row: Dictionary=PLACES[clampi(kind,0,3)].duplicate(true)
    row.id="home";row.name="Home castle";row.services=["temple"]
    return row

static func touches(position: Vector2i,point: Vector2i,size: Vector2i) -> bool:
    # Original boxesTouch includes coincident edges. Knight map cel0 is8x10.
    return position.x<=point.x+size.x and position.x+8>=point.x and position.y<=point.y+size.y and position.y+10>=point.y

static func size_for(site: Dictionary) -> Vector2i:
    if site.has("size"):return site.size
    var node: Dictionary=place(site.id)
    if not node.is_empty():return node.size
    return Vector2i(8,10) if site.get("id","") in preload("res://scripts/domain/rival_knights.gd").IDS else Vector2i(9,5)

static func arrivals(journey: RefCounted) -> Array[Dictionary]:
    var result: Array[Dictionary]=[]
    for index in range(PLACES.size()):
        if index<4 and index!=journey.identity.kind:continue
        var node: Dictionary=home(journey.identity.kind) if index<4 else PLACES[index]
        if touches(journey.world.position,node.position,node.size):
            if node.id=="valley_guardian" and journey.world.cleared.has(node.id) and not journey.has_treasure(node.id):continue
            result.append({"id":node.id,"name":node.name,"kind":"lair" if node.id=="valley_guardian" else "place"})
    for site in journey.world.definition.lairs:
        if journey.world.cleared.has(site.id) and not journey.has_treasure(site.id):continue
        if touches(journey.world.position,site.position,Vector2i(9,5)):
            result.append({"id":site.id,"name":site.name,"kind":"lair"})
    var hoard: Dictionary=journey.world.lair("roaming_dragon")
    if journey.world.cleared.has(hoard.id) and journey.has_treasure(hoard.id) and touches(journey.world.position,hoard.position,Vector2i(9,5)):
        result.append({"id":hoard.id,"name":"Dragon's remaining treasure","kind":"lair"})
    for rival in journey.rivals.records:
        if (rival.character.lives>0 or journey.has_treasure(rival.id)) and touches(journey.world.position,rival.position,Vector2i(8,10)):
            result.append({"id":rival.id,"name":journey.world.lair(rival.id).name,"kind":"knight"})
    return result
