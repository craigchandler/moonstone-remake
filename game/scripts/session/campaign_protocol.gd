extends RefCounted

const VERSION: int=1
const MAX_PACKET: int=131072
const Wire=preload("res://scripts/session/duel_protocol.gd")
const Simulation=preload("res://scripts/domain/combat_simulation.gd")
const CharacterRules=preload("res://content/classic_character.tres")
const Rules=preload("res://content/foundation_rules.tres")
const BUILD=preload("res://content/campaign_compatibility.json")
const Places=preload("res://scripts/domain/town_locations.gd")
const Henge=preload("res://scripts/domain/stonehenge_visit.gd")
const Session=preload("res://scripts/session/campaign_session.gd")
const ReadModel=preload("res://scripts/session/campaign_projection.gd")
static var actor_shapes: Dictionary={}
static var view_shape: Dictionary={}
static var map_shape: Dictionary={}
static func shapes() -> void:
    if not view_shape.is_empty():return
    var sample: RefCounted=Session.new(1,[0,1])
    view_shape=ReadModel.view(sample,0);map_shape=ReadModel.map_frame(sample)
    view_shape.campaign.places.market.items={}
static func shape(sample: Variant,value: Variant) -> bool:
    if typeof(sample) in [TYPE_STRING,TYPE_STRING_NAME]:return typeof(value) in [TYPE_STRING,TYPE_STRING_NAME]
    if typeof(sample)!=typeof(value):return false
    if typeof(sample)==TYPE_DICTIONARY:
        if not value.has_all(sample.keys()):return false
        for key in sample:
            if not shape(sample[key],value[key]):return false
    elif typeof(sample)==TYPE_ARRAY and not sample.is_empty():
        for row in value:
            if not shape(sample[0],row):return false
    return true
static func hex(value: Variant,length: int) -> bool:
    return typeof(value)==TYPE_STRING and value.length()==length and value.is_valid_hex_number(false)
static func status(value: Dictionary) -> bool:
    if value.get("state") not in ["lobby","paused","playing"] or not hex(value.get("room"),32) or not integer(value.get("count"),1,4) or typeof(value.get("started"))!=TYPE_BOOL or typeof(value.get("notice"))!=TYPE_STRING or typeof(value.get("seats"))!=TYPE_ARRAY or value.seats.size()!=4:return false
    for row in value.seats:
        if typeof(row)!=TYPE_DICTIONARY:return false
        for field in ["connected","reserved","ready"]:
            if typeof(row.get(field))!=TYPE_BOOL:return false
    return true
static func welcome(value: Dictionary) -> bool:
    return value.get("protocol")==VERSION and value.get("build")==fingerprint() and integer(value.get("seat"),0,3) and hex(value.get("room"),32) and hex(value.get("run"),32) and hex(value.get("token"),64) and integer(value.get("commands"),0,0x7fffffff) and integer(value.get("inputs"),0,0x7fffffff) and typeof(value.get("status"))==TYPE_DICTIONARY and status(value.status)
static func scenes(visit: Dictionary,henge: Dictionary,quest: Dictionary) -> bool:
    if not Henge.valid(henge,integer,CharacterRules.items.keys()):return false
    if not quest.has_all(["stones","valley_stone","notice","ending"]) or not integer(quest.stones,0,15) or not integer(quest.valley_stone,0,8) or typeof(quest.notice)!=TYPE_BOOL or typeof(quest.ending)!=TYPE_DICTIONARY or quest.has("seed"):return false
    if not quest.ending.is_empty():
        var end: Dictionary=quest.ending
        if end.get("stage") not in ["message","ready","complete"] or not integer(end.get("tick"),0,4062) or not integer(end.get("knight_kind"),0,3) or not integer(end.get("frame"),45,49) or not integer(end.get("code"),128,255):return false
    if visit.is_empty():return true
    if not shape(Places.visit("healer"),visit) or visit.kind not in ["wizard","healer","mystic","tavern"] or visit.phase not in ["greeting","gift","omen","sheet","donation","reply","tavern","rolling","dice"]:return false
    if visit.result not in ["","item","stat","gold","frog","none","tiny","plain","healed","raise","lower","unchanged"] or not integer(visit.row,0,8) or not integer(visit.tick,0,1000000) or visit.dice.size() not in [0,3]:return false
    for die in visit.dice:
        if not integer(die,0,5):return false
    if visit.result=="item" and (visit.subject not in CharacterRules.items or visit.row>3):return false
    if visit.result=="gold" and visit.row>2:return false
    if visit.result in ["stat","raise","lower"] and visit.subject not in ["strength","constitution","endurance"]:return false
    if visit.kind=="wizard" and visit.phase in ["gift","omen"] and visit.result not in ["item","stat","gold","frog"]:return false
    return true
static func valid_map(value: Dictionary) -> bool:
    shapes()
    return shape(map_shape,value) and integer(value.get("epoch"),1,0x7fffffff) and integer(value.get("tick"),0,0x7fffffff) and value.markers.size()==3 and scenes(value.visit,value.henge,value.quest) and Wire.primitive(value)

static func fingerprint() -> String:
    if OS.has_feature("editor"):
        for path in BUILD.data.files:
            if FileAccess.get_sha256("res://"+path)!=BUILD.data.files[path]:return ""
    return String(BUILD.data.digest)
static func encode(value: Dictionary) -> PackedByteArray:return var_to_bytes(value).compress(FileAccess.COMPRESSION_DEFLATE)
static func decode(bytes: PackedByteArray) -> Dictionary:
    if bytes.is_empty() or bytes.size()>MAX_PACKET:return {}
    var raw: PackedByteArray=bytes.decompress_dynamic(MAX_PACKET,FileAccess.COMPRESSION_DEFLATE)
    if raw.is_empty():return {}
    var value: Variant=bytes_to_var(raw)
    return value if typeof(value)==TYPE_DICTIONARY and Wire.primitive(value) else {}
static func integer(value: Variant,low: int,high: int) -> bool:return typeof(value)==TYPE_INT and value>=low and value<=high
static func packet(value: Dictionary) -> bool:
    return value.size()==2 and typeof(value.get("type"))==TYPE_STRING and value.type.length()<=24 and typeof(value.get("body"))==TYPE_DICTIONARY
static func valid_combat(value: Dictionary) -> bool:
    if value.is_empty():return true
    if not integer(value.get("epoch"),1,0x7fffffff) or not integer(value.get("battle"),1,0x7fffffff) or not integer(value.get("tick"),0,0x7fffffff):return false
    if typeof(value.get("state"))!=TYPE_DICTIONARY or typeof(value.get("events"))!=TYPE_ARRAY or typeof(value.get("humans"))!=TYPE_DICTIONARY:return false
    var state: Dictionary=value.state
    if state.get("schema")!=25 or state.get("mode")!="competitive" or typeof(state.get("actors"))!=TYPE_DICTIONARY or state.actors.size()<1 or state.actors.size()>32 or typeof(state.get("projectiles"))!=TYPE_ARRAY or typeof(state.get("rat_perch"))!=TYPE_DICTIONARY or not integer(state.get("tick"),0,0x7fffffff) or not integer(state.get("spawn_remaining"),0,256):return false
    for id in state.actors:
        var actor: Variant=state.actors[id]
        if not integer(id,1,512) or typeof(actor)!=TYPE_DICTIONARY or actor.get("id")!=id or actor.get("kind") not in Rules.actor_definitions:return false
        var kind: String=actor.kind
        if not actor_shapes.has(kind):
            var sim: RefCounted=Simulation.new(Rules)
            actor_shapes[kind]=sim.make_actor(id,0,2,kind,Vector2i(100,150),1)
        if not shape(actor_shapes[kind],actor) or not integer(actor.get("owner"),0,4) or actor.get("team") not in [1,2] or actor.get("facing") not in [-1,1]:return false
        for field in ["health","maximum","x","y","remaining","down_remaining","daggers","spawn_index","flash"]:
            if actor.has(field) and typeof(actor[field])!=TYPE_INT:return false
    for id in value.humans:
        if not state.actors.has(id) or not integer(value.humans[id],1,4) or state.actors[id].owner!=value.humans[id]:return false
    for event in value.events:
        if typeof(event)!=TYPE_DICTIONARY or typeof(event.get("type"))!=TYPE_STRING:return false
    for projectile in state.projectiles:
        if typeof(projectile)!=TYPE_DICTIONARY or not projectile.has_all(["id","x","y"]):return false
        for field in ["id","x","y"]:
            if typeof(projectile[field])!=TYPE_INT:return false
    return Wire.primitive(value)
static func valid_view(value: Dictionary) -> bool:
    shapes()
    if not shape(view_shape,value):return false
    if value.get("schema")!=1 or not integer(value.get("epoch"),1,0x7fffffff) or not integer(value.get("revision"),1,0x7fffffff) or not integer(value.get("tick"),0,0x7fffffff) or typeof(value.get("paused"))!=TYPE_BOOL or typeof(value.get("campaign"))!=TYPE_DICTIONARY or typeof(value.get("party"))!=TYPE_DICTIONARY or typeof(value.get("personal"))!=TYPE_DICTIONARY or typeof(value.get("combat"))!=TYPE_DICTIONARY:return false
    if value.get("phase") not in ["game_over","ending","quest","henge","loot","result","battle_ready","battle","attack","town","computer","turn_ready","map"]:return false
    var p: Dictionary=value.party
    if typeof(p.get("players"))!=TYPE_ARRAY or p.players.size()!=4 or not integer(p.get("active"),0,3) or not integer(p.get("turn"),0,3) or typeof(p.get("awaiting"))!=TYPE_BOOL or typeof(p.get("game_over"))!=TYPE_BOOL:return false
    for seat in range(4):
        var row: Variant=p.players[seat]
        if typeof(row)!=TYPE_DICTIONARY or typeof(row.get("human"))!=TYPE_BOOL or typeof(row.get("identity"))!=TYPE_DICTIONARY or row.identity.get("kind")!=seat or typeof(row.identity.get("name"))!=TYPE_STRING or row.identity.name.length()>40:return false
    var c: Dictionary=value.campaign
    for field in ["identity","world","character","inventory","places","rivals","quest","henge","lair_loot","awarded_lairs","revealed_lairs"]:
        if typeof(c.get(field))!=TYPE_DICTIONARY:return false
    if c.has("reward_seed") or c.places.has("seed") or c.rivals.has("seed") or c.quest.has("seed"):return false
    if not c.world.has_all(["tick","position","active_lair","entry_lock","cleared","last_result","facing","terrain_counter","dragon","dragon_hoard"]) or typeof(c.world.position)!=TYPE_DICTIONARY:return false
    for field in ["identity","character","inventory"]:
        if typeof(value.personal.get(field))!=TYPE_DICTIONARY:return false
    if not c.character.has_all(["stats","experience","lives","health","daggers","weapon","armour","life_loss"]) or not c.places.has_all(["market","visit","recency","frog_days"]):return false
    if c.rivals.records.size()!=3 or p.frog_days.size()!=4:return false
    for person in [c, value.personal]+c.rivals.records:
        if person.character.weapon not in CharacterRules.weapons or person.character.armour not in CharacterRules.armours:return false
        for stat in person.character.stats.values():
            if not integer(stat,1,5):return false
        for id in person.inventory.items:
            if id not in CharacterRules.items:return false
        for amount in person.inventory.items.values():
            if not integer(amount,0,255):return false
    return scenes(c.places.visit,c.henge,c.quest) and valid_combat(value.combat) and Wire.primitive(value)
