extends "res://scripts/session/journey_session.gd"

# Existing classic panels read this detached projection. Mutating panel actions
# are commands; they never execute campaign policy or simulation on a client.
const RemoteFight=preload("res://scripts/session/duel_replica.gd")
const FirstWorld=preload("res://content/first_journey.tres")
const FirstRules=preload("res://content/foundation_rules.tres")
const Protocol=preload("res://scripts/session/campaign_protocol.gd")
var _connection: WeakRef
var connection: RefCounted:
    get:return _connection.get_ref() if _connection!=null else null
    set(value):_connection=weakref(value) if value!=null else null
var read_only: bool=false
var own_view: bool=false
var latest: Dictionary={}
var battle_number: int=0
var fight_adapter: RefCounted

class FightView extends RefCounted:
    var simulation: RefCounted
    var human_actors: Dictionary={}
    func _init() -> void:simulation=preload("res://scripts/session/duel_replica.gd").new()
    func advance(_direction: Vector2i,_action: String,_additional: Dictionary={}) -> void:pass

func _init() -> void:super(FirstWorld,FirstRules,1)
func request(action: String,args: Dictionary={}) -> bool:
    return connection!=null and not read_only and connection.command(action,args)
func apply(value: Dictionary,personal_only: bool=false) -> bool:
    if not Protocol.valid_view(value):return false
    latest=value.duplicate(true);own_view=personal_only
    var c: Dictionary=value.campaign
    for field in ["identity","places","quest","henge","lair_loot","inventory","awarded_lairs","revealed_lairs"]:set(field,c[field].duplicate(true))
    for field in ["mode","dragon_order","human_players","battle_settled","revisit_battles","day","travel_spent","haste","turn_pending","turn_reason","loot_open","town_id","town_lock","service","pending_attack","attack_notice","owned_keys"]:
        var source: String="options" if field=="revisit_battles" else field
        if field=="revisit_battles":revisit_battles=c.options.revisit_battles
        elif c.has(source):set(field,c[source])
    apply_character(c.character)
    rivals.records.assign(c.rivals.records.duplicate(true));rivals.active=int(c.rivals.active)
    for row in rivals.records:
        if typeof(row.position)==TYPE_DICTIONARY:row.position=Vector2i(int(row.position.x),int(row.position.y))
    world.rival_records=rivals.records
    apply_world(c.world)
    party=LocalParty.new();party.players=value.party.players.duplicate(true)
    for seat in range(4):
        party.personal.append(party.empty_personal())
        party.personal[seat].frog_days=int(value.party.get("frog_days",[0,0,0,0])[seat])
    for field in ["active","turn","awaiting","game_over"]:party.set(field,value.party[field])
    party.update_labels(self)
    message=str(c.get("message",""))
    if personal_only:
        identity=value.personal.identity.duplicate(true);inventory=value.personal.inventory.duplicate(true)
        apply_character(value.personal.character);owned_keys=int(value.personal.keys);quest.stones=int(value.personal.stones)
        town_id="";service="";pending_attack="";places.visit={};loot_open=false;combat=null
    else:apply_combat(value.combat)
    return true
func apply_character(data: Dictionary) -> void:
    for field in ["stats","experience","lives","health","daggers","weapon","armour","life_loss"]:
        if data.has(field):character.set(field,data[field].duplicate(true) if typeof(data[field])==TYPE_DICTIONARY else data[field])
func apply_world(data: Dictionary) -> void:
    world.tick=int(data.tick);world.position=Vector2i(int(data.position.x),int(data.position.y))
    for field in ["cleared","active_lair","entry_lock","last_result","facing","terrain_counter"]:world.set(field,data[field].duplicate(true) if typeof(data[field])==TYPE_DICTIONARY else data[field])
    world.dragon.restore(data.dragon)
    world.dragon_hoard=Vector2i(int(data.dragon_hoard.x),int(data.dragon_hoard.y))
func apply_map(value: Dictionary) -> void:
    if own_view:return
    if typeof(value.get("world"))==TYPE_DICTIONARY:apply_world(value.world)
    if typeof(value.get("markers"))==TYPE_ARRAY:
        for marker in value.markers:
            var row: Dictionary=rivals.find(str(marker.id))
            if not row.is_empty() and typeof(marker.position)==TYPE_VECTOR2I:row.position=marker.position
    travel_spent=int(value.get("travel_spent",travel_spent))
    if typeof(value.get("visit"))==TYPE_DICTIONARY:places.visit=value.visit.duplicate(true)
    if typeof(value.get("henge"))==TYPE_DICTIONARY:henge=value.henge.duplicate(true)
    if typeof(value.get("quest"))==TYPE_DICTIONARY:quest=value.quest.duplicate(true)
func apply_combat(value: Dictionary) -> bool:
    if value.is_empty():combat=null;fight_adapter=null;return true
    if not Protocol.valid_combat(value):return false
    if fight_adapter==null or battle_number!=value.battle:
        battle_number=value.battle;fight_adapter=FightView.new()
    fight_adapter.human_actors=value.humans.duplicate(true)
    fight_adapter.simulation.apply(value.state,value.events)
    combat=fight_adapter
    return true
func persist() -> bool:return true
func travel(_direction: Vector2i) -> bool:return false
func begin_turn() -> bool:return request("begin_turn")
func rest() -> bool:return request("rest")
func confirm_location(id: String) -> bool:return request("enter",{"id":id})
func take_loot(id: String) -> bool:return request("take_loot",{"id":id})
func collect_all_loot() -> void:request("collect_loot")
func prepare_loot() -> bool:return loot_open
func return_to_map(_collect: bool=true) -> bool:return request("leave_loot" if loot_open else "retreat")
func open_service(id: String) -> bool:return request("service",{"id":id})
func leave_town() -> bool:return request("leave_town")
func buy_equipment(id: String) -> bool:return request("buy",{"id":id})
func buy_healing(id: String) -> bool:return request("heal",{"id":id})
func upgrade_stat(stat: String) -> bool:return request("upgrade",{"id":stat})
func use_item(id: String,target: Variant=null) -> bool:return request("item",{"id":id,"target":{"x":target.x,"y":target.y} if typeof(target)==TYPE_VECTOR2I else target})
func resolve_pending_attack(protection: bool) -> bool:return request("protection",{"use":protection})
func advance_henge() -> bool:return request("henge_next")
func offer_henge_item(id: String) -> bool:return request("henge_offer",{"id":id})
func complete_henge() -> bool:return request("henge_skip")
func leave_henge_offering() -> bool:return request("henge_leave_offer")
func leave_henge() -> bool:return request("henge_leave")
func acknowledge_moonstone() -> bool:return request("quest_ack")
func enter_ending() -> bool:return request("ending_start")
func finish_ending() -> bool:return request("ending_finish")
func tick_henge() -> void:pass
func tick_quest() -> void:pass
func tick_ending() -> void:pass
