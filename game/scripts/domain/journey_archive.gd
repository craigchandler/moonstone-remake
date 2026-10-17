class_name JourneyArchive
extends RefCounted

const Math = preload("res://scripts/domain/character_math.gd")

# JSON data only. Validate completely before a live journey is changed.
static func integer(value: Variant, low: int, high: int) -> bool:
    return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) == floor(float(value)) and float(value) >= low and float(value) <= high

static func flags(value: Variant, ids: Array) -> bool:
    if typeof(value) != TYPE_DICTIONARY or value.size() > ids.size(): return false
    for id in value:
        if not id in ids or typeof(value[id]) != TYPE_BOOL or not value[id]: return false
    return true

static func counts(value: Variant, ids: Array, limit: int) -> bool:
    if typeof(value) != TYPE_DICTIONARY or value.size() > ids.size(): return false
    for id in value:
        if not id in ids or not integer(value[id], 1, limit): return false
    return true

static func duel_pile(raw: Variant, character_rules: Resource, loot_rules: Resource) -> Dictionary:
    if typeof(raw) != TYPE_DICTIONARY or raw.size() != 5:
        return {}
    var result: Dictionary = raw.duplicate(true)
    var limits: Dictionary = {"gold": character_rules.gold_limit, "kind": 4, "keys": 15, "stones": 15}
    for field in limits:
        if not integer(result.get(field), 1 if field == "kind" else 0, limits[field]):
            return {}
        result[field] = int(result[field])
    if not counts(result.get("items"), loot_rules.items.keys(), 255):
        return {}
    for id in result.items:
        result.items[id] = int(result.items[id])
    return result

static func validate(raw: Variant, definition: Resource, character_rules: Resource, loot_rules: Resource, extra_chests: Array = [], party_context: bool = false) -> Dictionary:
    if typeof(raw) != TYPE_DICTIONARY: return {}
    var d: Dictionary = raw.duplicate(true)
    var legacy: bool = d.get("schema")==3 and d.get("content")=="journey.campaign.v1"
    var previous: bool = d.get("schema")==4 and d.get("content")=="journey.campaign.v2"
    var towns_build: bool = d.get("schema")==5 and d.get("content")=="journey.campaign.v3"
    var flight_build: bool = d.get("schema")==6 and d.get("content")=="journey.campaign.v4"
    var old_flight: bool = legacy or previous or towns_build
    var old_turns: bool = old_flight or flight_build
    var turns_build: bool=d.get("schema")==7 and d.get("content")=="journey.campaign.v5"
    var henge_build: bool=d.get("schema")==8 and d.get("content")=="journey.campaign.v6"
    var old_quest: bool=old_turns or turns_build or henge_build
    var quest_build: bool=d.get("schema")==9 and d.get("content")=="journey.campaign.v7"
    var ending_build: bool=d.get("schema")==10 and d.get("content")=="journey.campaign.v8"
    var previous_rivals: bool=d.get("schema")==11 and d.get("content")=="journey.campaign.v9"
    var migrate_rivals: bool=old_quest or quest_build or ending_build or previous_rivals
    var rival_build: bool=d.get("schema")==12 and d.get("content")=="journey.campaign.v10"
    var scrolls_build: bool=d.get("schema")==13 and d.get("content")=="journey.campaign.v11"
    var migrate_places: bool=migrate_rivals or rival_build or scrolls_build
    var previous_ending: bool=d.get("schema")==14 and d.get("content")=="journey.campaign.v12"
    var full_ending_build: bool=d.get("schema")==15 and d.get("content")=="journey.campaign.v13"
    var migrate_identity: bool=migrate_places or previous_ending or full_ending_build
    if not migrate_identity and (d.get("schema")!=16 or d.get("content")!="journey.campaign.v14"): return {}
    const Identity=preload("res://scripts/domain/knight_identity.gd")
    if migrate_identity:d.identity=Identity.initial()
    if not Identity.valid(d.get("identity")):return {}
    d.identity.kind=int(d.identity.kind)
    if old_quest or quest_build or ending_build:d.options={"revisit_battles":false}
    if typeof(d.get("options"))!=TYPE_DICTIONARY or d.options.size()!=1 or typeof(d.options.get("revisit_battles"))!=TYPE_BOOL:return {}
    if d.get("phase") not in (["map","loot"] if legacy else ["map","loot","attack"]): return {}
    if d.get("mode") not in ["competitive", "cooperative"]: return {}
    if not integer(d.get("reward_seed"), 2, 0xffffffff) or not integer(d.get("human_players"), 1, 4): return {}
    if not integer(d.get("day"), 1, 1000000) or not integer(d.get("travel_spent"), 0, 2048): return {}
    for field in ["haste", "loot_open", "battle_settled"]:
        if typeof(d.get(field)) != TYPE_BOOL: return {}
    var ids: Array = []
    for site in definition.lairs: ids.append(site.id)
    for site in definition.special_encounters: ids.append(site.id)
    const Rivals=preload("res://scripts/domain/rival_knights.gd")
    if definition.rival_turns:
        for id in Rivals.IDS:
            if id not in ids:ids.append(id)
    var towns: Dictionary = {}
    for town in definition.towns: towns[town.id] = town
    for id in ["home","wizard"]:towns[id]=preload("res://scripts/domain/map_locations.gd").place(id)
    towns.home=preload("res://scripts/domain/map_locations.gd").home(d.identity.kind)
    for field in ["town_id", "town_lock", "service"]:
        if typeof(d.get(field)) != TYPE_STRING: return {}
    if d.town_id != "" and not towns.has(d.town_id): return {}
    if d.town_lock != "" and not towns.has(d.town_lock): return {}
    if d.service != "" and (d.town_id == "" or not d.service in towns[d.town_id].services): return {}
    if typeof(d.get("world")) != TYPE_DICTIONARY: return {}
    var w: Dictionary = d.world
    if typeof(w.get("cleared"))!=TYPE_DICTIONARY:return {}
    if w.get("schema") != (1 if old_flight else (2 if flight_build else 3)): return {}
    if legacy:
        if w.get("content")!="journey.v5": return {}
        if typeof(d.get("lair_loot"))!=TYPE_DICTIONARY or d.lair_loot.size()!=definition.lairs.size(): return {}
        var roller = preload("res://scripts/domain/loot_roller.gd").new(loot_rules,int(d.reward_seed)^0x43524541)
        for site in definition.special_encounters: d.lair_loot[site.id]=roller.roll_lair()
        w.content=String(definition.content_id)
        d.schema=4
        d.content="journey.campaign.v2"
        d.pending_attack=""
        d.attack_notice=false
    elif w.get("content") != ("journey.v6" if old_flight else ("journey.v7" if flight_build else String(definition.content_id))): return {}
    if legacy or previous:
        if typeof(d.get("lair_loot")) != TYPE_DICTIONARY or typeof(d.get("awarded_lairs")) != TYPE_DICTIONARY: return {}
        d.schema = 5
        d.content = "journey.campaign.v3"
        d.owned_keys = 0
        for pile in d.lair_loot.values():
            if typeof(pile) != TYPE_DICTIONARY: return {}
            pile.keys = 0
        # Previous builds had no key possessions. Completed areas receive a
        # recoverable key in their final site's chest, never invented ownership.
        for pair in [["Great Forest",8],["Northern Wastes",4],["Wetlands",2],["Misty Moors",1]]:
            var last: String = ""
            var complete: bool = true
            for site in definition.lairs:
                if site.region != pair[0]: continue
                last = site.id
                if typeof(d.get("awarded_lairs")) != TYPE_DICTIONARY or not d.awarded_lairs.has(site.id): complete=false
            if complete and not last.is_empty() and d.lair_loot.has(last) and typeof(d.lair_loot[last])==TYPE_DICTIONARY:
                d.lair_loot[last].keys |= int(pair[1])
    if old_flight:
        # No flight existed in these builds. Begin an eligible future pass at
        # the edge; never reroll a chest or resurrect a defeated dragon.
        w.dragon = preload("res://scripts/domain/map_dragon.gd").new(definition.dragon_rules).snapshot()
        w.dragon_hoard = {"x":210,"y":90}
        w.schema = 2
        w.content = String(definition.content_id)
        d.schema = 6
        d.content = "journey.campaign.v4"
    if old_turns:
        # Preserve prior round/day and all flight/kit/reward data. No turn is
        # spent or healed merely because an older checkpoint was loaded.
        w.terrain_counter = 0
        w.schema = 3
        w.content = String(definition.content_id)
        d.schema = 7
        d.content = "journey.campaign.v5"
        d.turn_pending = false
        d.turn_reason = ""
    if old_turns or turns_build:
        if typeof(d.get("character"))!=TYPE_DICTIONARY: return {}
        d.character.life_loss=0
        d.henge={}
        d.henge_lock=false
        d.schema=8
        d.content="journey.campaign.v6"
    const Henge=preload("res://scripts/domain/stonehenge_visit.gd")
    if typeof(d.get("henge_lock"))!=TYPE_BOOL or not Henge.valid(d.get("henge"),integer,loot_rules.items.keys()): return {}
    if not d.henge.is_empty():
        d.henge.tick=int(d.henge.tick)
        if d.henge_lock or d.phase!="map" or d.town_id!="" or d.service!="" or d.turn_pending or d.loot_open or d.pending_attack!="": return {}
        if typeof(w.get("position"))!=TYPE_DICTIONARY or not integer(w.position.get("x"),0,320) or not integer(w.position.get("y"),0,200): return {}
        var henge_point:=Vector2i(int(w.position.x),int(w.position.y))
        if definition.confirm_entry:
            if not preload("res://scripts/domain/map_locations.gd").touches(henge_point,Henge.POSITION,Vector2i(18,12)):return {}
        elif henge_point.distance_squared_to(Henge.POSITION)>definition.entry_radius*definition.entry_radius:return {}
        if w.get("active_lair")!="" or typeof(w.get("dragon"))!=TYPE_DICTIONARY or w.dragon.get("active")!=false: return {}
    if not integer(w.get("terrain_counter"),0,65535): return {}
    w.terrain_counter = int(w.terrain_counter)
    if migrate_rivals:
        d.rivals=Rivals.new(definition,character_rules,loot_rules,int(d.reward_seed)).snapshot()
        if typeof(d.get("lair_loot"))!=TYPE_DICTIONARY:return {}
        if definition.rival_turns:
            for id in Rivals.IDS:
                if id!="roaming_black_knight":d.lair_loot[id]={"gold":0,"items":{},"kind":4,"keys":0,"stones":0}
                elif typeof(d.lair_loot.get(id))!=TYPE_DICTIONARY:return {}
                else:d.lair_loot[id].stones=0
            if typeof(w.get("cleared"))!=TYPE_DICTIONARY:return {}
            if w.cleared.has("roaming_black_knight"):
                d.rivals.records[0].character.lives=0;d.rivals.records[0].character.health=0
            d.rivals.records[0].loot_ready=w.cleared.has("roaming_black_knight") or (d.phase=="loot" and w.active_lair=="roaming_black_knight")
    if migrate_rivals or rival_build:
        d.dragon_order=-1
        if typeof(d.get("lair_loot"))!=TYPE_DICTIONARY or typeof(d.lair_loot.get("roaming_dragon"))!=TYPE_DICTIONARY:return {}
        d.lair_loot.roaming_dragon.stones=0
    if not integer(d.get("dragon_order"),-1,3) or d.dragon_order==0:return {}
    d.dragon_order=int(d.dragon_order)
    if not Rivals.valid(d.get("rivals"),definition,character_rules,loot_rules,integer,party_context):return {}
    if d.dragon_order>0 and (not definition.rival_turns or d.rivals.records[d.dragon_order-1].character.lives<=0 or w.cleared.has("roaming_dragon") or int(d.day)-1<definition.dragon_rules.spawn_counter*definition.dragon_rules.rounds_per_counter):return {}
    var running: bool=d.rivals.active!=0
    if typeof(d.get("turn_pending"))!=TYPE_BOOL or d.get("turn_reason") not in ["","rest","travel","town","stonehenge"]: return {}
    if running and (d.turn_pending or d.town_id!="" or not d.henge.is_empty()):return {}
    if d.turn_pending:
        if d.turn_reason=="" or d.phase!="map" or d.town_id!="" or d.travel_spent!=0 or d.haste or d.day<=1: return {}
    elif (d.turn_reason!="")!=running: return {}
    if not dragon_state(w.get("dragon"), definition.dragon_rules,3 if definition.rival_turns else 0): return {}
    if w.dragon.active and w.dragon.target>0 and d.rivals.records[w.dragon.target-1].character.lives<=0:return {}
    if w.dragon.active and d.dragon_order>0 and w.dragon.target!=d.dragon_order:return {}
    if typeof(w.get("dragon_hoard")) != TYPE_DICTIONARY: return {}
    var hoard: Dictionary = w.dragon_hoard
    if not integer(hoard.get("x"), definition.bounds.position.x, definition.bounds.end.x-1) or not integer(hoard.get("y"), definition.bounds.position.y, definition.bounds.end.y-1): return {}
    w.dragon_hoard = {"x":int(hoard.x),"y":int(hoard.y)}
    if not integer(d.get("owned_keys"),0,15): return {}
    d.owned_keys = int(d.owned_keys)
    var key_locations: int = d.owned_keys
    var stone_locations: int = 0
    if not old_quest:
        var quest: Variant = d.get("quest")
        if typeof(quest) != TYPE_DICTIONARY or not integer(quest.get("stones"), 0, 15):
            return {}
        stone_locations = int(quest.stones)
    for row in d.rivals.records:
        if (key_locations&row.keys)!=0 or (stone_locations&row.stones)!=0:return {}
        key_locations|=row.keys;stone_locations|=row.stones
    if not integer(w.get("tick"), 0, 0x7fffffff) or not integer(w.get("facing"), -1, 1) or w.facing == 0: return {}
    if typeof(w.get("position")) != TYPE_DICTIONARY: return {}
    var p: Dictionary = w.position
    if not integer(p.get("x"), definition.bounds.position.x, definition.bounds.end.x - 1) or not integer(p.get("y"), definition.bounds.position.y, definition.bounds.end.y - 1): return {}
    if not flags(w.get("cleared"), ids) or not flags(d.get("awarded_lairs"), ids) or not flags(d.get("revealed_lairs"), ids): return {}
    if w.dragon.active and (int(d.day)-1 < definition.dragon_rules.spawn_counter * definition.dragon_rules.rounds_per_counter or w.cleared.has("roaming_dragon") or d.phase!="map" or d.town_id!=""): return {}
    for field in ["active_lair", "entry_lock"]:
        if typeof(w.get(field)) != TYPE_STRING or (w[field] != "" and not w[field] in ids): return {}
    if w.get("last_result") not in ["", "victory", "defeat", "draw", "retreated"]: return {}
    if typeof(d.get("pending_attack"))!=TYPE_STRING or d.pending_attack not in ([""]+Rivals.IDS if definition.rival_turns else ["","roaming_black_knight"]) or typeof(d.get("attack_notice"))!=TYPE_BOOL: return {}
    if d.phase == "attack":
        if d.pending_attack=="" or w.active_lair!=d.pending_attack or d.loot_open or d.battle_settled or d.town_id!="": return {}
    elif d.pending_attack!="" or d.attack_notice: return {}
    if d.phase == "loot":
        if w.active_lair == "" or not d.loot_open or not d.battle_settled or d.town_id != "": return {}
    elif d.phase!="attack" and (w.active_lair != "" or d.loot_open or d.battle_settled): return {}
    for id in d.awarded_lairs:
        if not w.cleared.has(id) and not (d.phase == "loot" and w.active_lair == id): return {}
    if d.town_id != "":
        var town_point:=Vector2i(int(p.x),int(p.y))
        var place: Dictionary=towns[d.town_id]
        if definition.confirm_entry:
            if not preload("res://scripts/domain/map_locations.gd").touches(town_point,place.position,preload("res://scripts/domain/map_locations.gd").size_for(place)):return {}
        elif town_point.distance_squared_to(place.position)>definition.entry_radius*definition.entry_radius:return {}
    if typeof(d.get("inventory")) != TYPE_DICTIONARY: return {}
    var inv: Dictionary = d.inventory
    if not integer(inv.get("gold"), 0, character_rules.gold_limit) or not counts(inv.get("items"), loot_rules.items.keys(), 255): return {}
    if d.phase=="attack" and int(inv.items.get("scroll_of_protection",0))<1: return {}
    if typeof(d.get("lair_loot")) != TYPE_DICTIONARY or d.lair_loot.size() != ids.size(): return {}
    for id in ids:
        if typeof(d.lair_loot.get(id)) != TYPE_DICTIONARY: return {}
        var pile: Dictionary = d.lair_loot[id]
        if not integer(pile.get("keys"),0,15): return {}
        if (key_locations & int(pile.keys)) != 0: return {}
        key_locations |= int(pile.keys)
        pile.keys = int(pile.keys)
        var rival_pile: bool=(definition.rival_turns and id in Rivals.IDS) or id=="roaming_dragon"
        if rival_pile:
            if not integer(pile.get("stones"),0,15) or (stone_locations&int(pile.stones))!=0:return {}
            pile.stones=int(pile.stones);stone_locations|=pile.stones
        if not integer(pile.get("kind"), 1, 4) or not integer(pile.get("gold"), 0, character_rules.gold_limit if rival_pile else 31) or not counts(pile.get("items"), loot_rules.items.keys(), 255 if rival_pile else 3): return {}
        var count: int = 0
        for item in pile.items:
            pile.items[item] = int(pile.items[item])
            count += pile.items[item]
        if not rival_pile and (count > (3 if pile.kind == 2 else (2 if pile.kind == 3 else 0)) or (pile.kind in [2,4] and pile.gold != 0)): return {}
        pile.gold = int(pile.gold)
        pile.kind = int(pile.kind)
    if typeof(d.get("character")) != TYPE_DICTIONARY: return {}
    var c: Dictionary = d.character
    if not integer(c.get("life_loss"),0,255): return {}
    c.life_loss=int(c.life_loss)
    if typeof(c.get("stats")) != TYPE_DICTIONARY or c.stats.size() != 3: return {}
    for name in ["strength", "constitution", "endurance"]:
        if not integer(c.stats.get(name), 1, character_rules.stat_limit): return {}
        c.stats[name] = int(c.stats[name])
    if not character_rules.weapons.has(c.get("weapon")) or c.weapon == "sword_of_sharpness" or not character_rules.armours.has(c.get("armour")): return {}
    var maximum: int = Math.maximum_health(character_rules, c.stats.constitution, c.armour, inv.items)
    for field in ["health", "lives", "daggers", "experience"]:
        var cap: int = {"health": maximum, "lives": character_rules.life_limit, "daggers": character_rules.dagger_limit, "experience": 65535}[field]
        if not integer(c.get(field), 0, cap): return {}
        c[field] = int(c[field])
    if (c.lives == 0) != (c.health == 0): return {}
    if not d.henge.is_empty() and c.lives==0: return {}
    if d.turn_pending and c.lives==0: return {}
    for id in inv.items: inv.items[id] = int(inv.items[id])
    inv.gold = int(inv.gold)
    for field in ["schema", "human_players", "reward_seed", "day", "travel_spent"]: d[field] = int(d[field])
    w.tick = int(w.tick)
    w.schema = 3
    w.facing = int(w.facing)
    w.position = {"x": int(p.x), "y": int(p.y)}
    const Quest=preload("res://scripts/domain/moonstone_quest.gd")
    if old_quest:Quest.migrate(d,loot_rules)
    if quest_build and typeof(d.get("quest"))==TYPE_DICTIONARY and typeof(d.quest.get("ending"))==TYPE_DICTIONARY and not d.quest.ending.is_empty():
        if d.quest.ending.get("stage") not in ["message","ready"] or not integer(d.quest.ending.get("tick"),0,20):return {}
        if d.quest.ending.stage=="ready":
            if d.quest.ending.tick!=20:return {}
            d.quest.ending.tick=0 # Previous durable handoff has not played a frame.
    const Places=preload("res://scripts/domain/town_locations.gd")
    if migrate_places:
        d.places=Places.initial_from(int(d.reward_seed),loot_rules)
        if d.town_id=="wizard":
            d.places.visit=Places.visit("wizard");d.places.visit.phase="sheet"
        elif d.service in ["healer","mystic","tavern"]:d.places.visit=Places.visit(d.service)
    if not Places.valid(d,integer,loot_rules):return {}
    if (key_locations&d.places.market.keys)!=0 or (stone_locations&d.places.market.stones)!=0:return {}
    key_locations |= int(d.places.market.keys)
    stone_locations |= int(d.places.market.stones)
    var extra_stones: int = 0
    for raw_pile in extra_chests:
        var pile: Dictionary = duel_pile(raw_pile, character_rules, loot_rules)
        if pile.is_empty() or (key_locations & pile.keys) != 0 or (stone_locations & pile.stones) != 0:
            return {}
        key_locations |= pile.keys
        stone_locations |= pile.stones
        extra_stones |= pile.stones
    # Retain the opening clock; old completed films stay completed. Check old
    # limits before converting so migration cannot legitimise a malformed clock.
    if (migrate_places or previous_ending) and typeof(d.get("quest"))==TYPE_DICTIONARY and typeof(d.quest.get("ending"))==TYPE_DICTIONARY and not d.quest.ending.is_empty():
        var ending: Dictionary=d.quest.ending
        if not integer(ending.get("tick"),0,940):return {}
        if ending.get("stage")=="ready" and ending.tick>=940:return {}
        if ending.get("stage")=="complete":
            if ending.tick!=940:return {}
            ending.tick=Quest.ENDING_TICKS
    d.schema=16
    d.content="journey.campaign.v14"
    if not Quest.valid(d,integer,definition,extra_stones):return {}
    return d

static func dragon_state(value: Variant, rules: Resource, max_target: int=0) -> bool:
    if typeof(value) != TYPE_DICTIONARY or value.size()!=9 or typeof(value.get("active"))!=TYPE_BOOL: return false
    for field in ["x","y","speed_x","facing","phase","timer","subtick","target"]:
        var limits: Array = {"x":[-200,500],"y":[0,rules.vertical_wrap],"speed_x":[-rules.speed.x,rules.speed.x],"facing":[1,3],"phase":[0,15],"timer":[0,rules.cycle],"subtick":[0,rules.step_ticks-1],"target":[0,max_target]}[field]
        if not integer(value.get(field), limits[0], limits[1]): return false
        value[field] = int(value[field])
    if value.speed_x not in [-rules.speed.x,rules.speed.x] or value.facing != (3 if value.speed_x>0 else 1): return false
    if not value.active and value != preload("res://scripts/domain/map_dragon.gd").new(rules).snapshot(): return false
    return true
