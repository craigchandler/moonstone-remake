class_name JourneySession
extends RefCounted

const Scaling=preload("res://scripts/domain/encounter_scaling_host.gd")
const Places=preload("res://scripts/domain/town_locations.gd")
const Identity=preload("res://scripts/domain/knight_identity.gd")
const HOME_VISIT_MESSAGE: String="Home village: lives recover up to three. Leave to rest for a turn."
const LocalParty=preload("res://scripts/session/local_party.gd")
var party: RefCounted
var identity: Dictionary=Identity.initial()
var places: Dictionary={}
const Scrolls=preload("res://scripts/domain/targeted_scrolls.gd")
var dragon_order: int=-1 # Wyrm command retained across map/arena reset until contact.
const Rivals=preload("res://scripts/domain/rival_knights.gd")
var rivals: RefCounted
const Archive = preload("res://scripts/domain/journey_archive.gd")
const World = preload("res://scripts/domain/world_simulation.gd")
const Combat = preload("res://scripts/session/local_session.gd")
const Knight = preload("res://scripts/domain/knight_progression.gd")
const Roller = preload("res://scripts/domain/loot_roller.gd")
const Henge = preload("res://scripts/domain/stonehenge_visit.gd")
const Locations = preload("res://scripts/domain/map_locations.gd")
var quest_rules: Resource=preload("res://content/generated/moonstone_quest.tres")
var quest: Dictionary={}
var henge: Dictionary = {}
var henge_lock: bool = false
var loot_rules: Resource = preload("res://content/generated/classic_loot.tres")
var world: RefCounted
var combat: RefCounted
var rules: Resource
var character_rules: Resource = preload("res://content/classic_character.tres")
var character: RefCounted
var human_players: int = 1 # An AI ally does not increase the human-player count.
var awarded_lairs: Dictionary = {}
var revealed_lairs: Dictionary = {}
var battle_settled: bool = false
var revisit_battles: bool = false
var day: int = 1
var travel_spent: int = 0
var haste: bool = false
var turn_pending: bool = false
var turn_reason: String = ""
var message: String = ""
var mode: StringName = &"competitive"
var reward_seed: int = 1
var lair_loot: Dictionary = {}
var inventory: Dictionary = {"gold": 0, "items": {}}
var loot_open: bool = false
var town_id: String = ""
var town_lock: String = ""
var service: String = ""
var store: RefCounted
var save_message: String = ""
var pending_attack: String = ""
var attack_notice: bool = false
var owned_keys: int = 0
const REGIONAL_KEYS = {"key_forest": {"bit":8,"region":"Great Forest","name":"Forest key"}, "key_wastes": {"bit":4,"region":"Northern Wastes","name":"Wastes key"}, "key_wetlands": {"bit":2,"region":"Wetlands","name":"Wetlands key"}, "key_moors": {"bit":1,"region":"Misty Moors","name":"Moors key"}}

func _init(world_definition: Resource, combat_rules: Resource, seed_value: int = 1) -> void:
    rules = combat_rules
    world = World.new(world_definition)
    restart(seed_value)

func travel(direction: Vector2i) -> bool:
    if party!=null and (party.awaiting or party.game_over):return false
    if rivals.active!=0 or character.lives <= 0 or combat != null or not pending_attack.is_empty() or not town_id.is_empty() or turn_pending or not henge.is_empty() or quest.notice or not quest.ending.is_empty(): return false
    if travel_remaining() <= 0:
        end_turn("travel")
        return false
    var before: Vector2i = world.position
    var entrance: String = world.advance(direction, day - 1, dragon_aim() if not rivals.records.is_empty() else null)
    travel_spent += world.last_step_cost
    if not inside_henge(): henge_lock=false
    if not town_lock.is_empty() and not world.inside_lair(town(town_lock)): town_lock = ""
    if entrance.is_empty():
        if world.definition.confirm_entry and travel_remaining()<=0:
            for row in arrivals():
                if row.kind=="lair":
                    confirm_location(row.id)
                    return combat!=null or loot_open
        if world.position != before and not world.definition.confirm_entry:
            if not henge_lock and inside_henge():
                enter_henge()
                return false
            for site in world.sites():
                if world.cleared.has(site.id) and world.entry_lock != site.id and world.inside_lair(site) and has_treasure(site.id):
                    world.active_lair = site.id
                    enter_cleared_lair()
                    return true
            for place in world.definition.towns:
                if place.id != town_lock and world.inside_lair(place):
                    enter_town(place.id)
                    break
        # A last-step town, loot visit or fight resolves before the turn ends.
        if town_id.is_empty() and travel_remaining() <= 0: end_turn("travel")
        elif world.tick % 50 == 0: persist()
        return false
    if entrance == "roaming_black_knight" and int(inventory.items.get("scroll_of_protection",0)) > 0:
        pending_attack = entrance
        attack_notice = true
        message = "A Black Knight attacks! You can use a Scroll of Protection to avoid battle."
        return true
    start_site_combat()
    return true

func start_site_combat() -> void:
    if world.active_lair=="valley_guardian" and key_mask()!=15:
        world.finish_lair("ongoing")
        message="Four regional keys are needed to enter the Valley of the Gods."
        persist()
        return
    combat = Combat.new(rules)
    combat.knight_profile = character.combat_profile(inventory.items)
    combat.knight_profile.moon_damage_shift=1 if quest_rules.matches(quest.stones,calendar().moon_phase,true) else 0
    var site: Dictionary = world.lair(world.active_lair)
    world.dragon.reset() # Original arena reset ends the active map flight.
    var rival: Dictionary=rivals.find(world.active_lair)
    if not rival.is_empty():
        combat.rival_profile=rivals.knight(rival).combat_profile(rival.inventory.items)
        combat.rival_profile.moon_damage_shift=1 if quest_rules.matches(rival.stones,calendar().moon_phase,true) else 0
    combat.start(mode, site.encounter, encounter_options(site))
    if party!=null:
        party.configure_combat(self)
    if world.active_lair == "roaming_dragon":
        clear_dragon_order()
    battle_settled = false
    if places.frog_days>0:
        # The local AI ally shares the cursed campaign token. Finish both
        # transient fighters so co-op cannot turn this shortcut into a retreat.
        for actor in combat.simulation.actors.values():
            if actor.team==1:actor.health=0;actor.down_remaining=0
        return_to_map(false)
    persist()

func key_mask() -> int:
    return owned_keys

func offer_region_key(site_id: String) -> void:
    # User-confirmed progression: clear all six lairs, then collect the area's key.
    var site: Dictionary = world.lair(site_id)
    if not site in world.definition.lairs: return
    for key in REGIONAL_KEYS.values():
        if site.region != key.region: continue
        for lair in world.definition.lairs:
            if lair.region == key.region and not awarded_lairs.has(lair.id): return
        if (owned_keys & int(key.bit)) != 0 or (int(places.market.keys)&int(key.bit))!=0:return
        for rival in rivals.records:
            if (int(rival.keys)&int(key.bit))!=0:return
        for pile in lair_loot.values():
            if (int(pile.get("keys",0)) & int(key.bit)) != 0: return
        lair_loot[site_id].keys = int(lair_loot[site_id].get("keys",0)) | int(key.bit)

func encounter_options(site: Dictionary) -> Dictionary:
    var phase: int=calendar().moon_phase
    if not site.has("count"):
        var options:Dictionary={"moon_phase":phase}
        if site.encounter==&"black_knight_fight":
            options["combat_seed"]=maxi(2,(reward_seed ^ (world.position.x<<8) ^ (world.position.y<<16) ^ day) & 0xffffffff)
            options["knight_difficulty"]=mini(7,int(calendar().lunar_counter))
        return options
    var base: Dictionary=rules.encounters[String(site.encounter)]
    var options: Dictionary=Scaling.options(rules,{"creature":String(base.creature),"base_count":int(site.count),
        "strength":int(character.stats.strength),"maximum_hp":character.maximum(inventory.items),
        "weapon_bonus":int(character_rules.weapons[character.effective_weapon(inventory.items)].damage),
        "moon_shift":1 if quest_rules.matches(quest.stones,phase,true) else 0})
    options["moon_phase"]=phase
    if base.has("entry_profile"):options["arena_site"]=String(site.id)
    return options

func dismiss_attack_notice() -> void:
    attack_notice = false

func resolve_pending_attack(use_protection: bool) -> bool:
    if pending_attack.is_empty(): return false
    if use_protection:
        if int(inventory.items.get("scroll_of_protection",0))<=0: return false
        inventory.items.scroll_of_protection -= 1
        if inventory.items.scroll_of_protection==0: inventory.items.erase("scroll_of_protection")
        world.entry_lock = pending_attack
        world.active_lair = ""
        message = "Protection scroll used. The battle was avoided."
    pending_attack = ""
    attack_notice = false
    if not use_protection: start_site_combat()
    elif travel_remaining() <= 0: end_turn("travel")
    persist()
    return true

func begin_rival_encounter(id: String,incoming: bool) -> bool:
    var row: Dictionary=rivals.find(id)
    if row.is_empty() or combat!=null or not pending_attack.is_empty() or character.lives<=0:return false
    if not Locations.touches(world.position,row.position,Vector2i(8,10)):return false
    world.active_lair=id
    if row.loot_ready and has_treasure(id):
        # Unclaimed duel loot stays with that record until collected; never reroll
        # or overwrite it with another duel's reward.
        if incoming:world.active_lair="";return false
        make_completed_encounter();loot_open=true;battle_settled=true;persist();return true
    if row.character.lives<=0:world.active_lair="";return false
    row.loot_ready=false
    if not incoming:travel_spent=travel_allowance()
    world.dragon.reset()
    if incoming and int(inventory.items.get("scroll_of_protection",0))>0:
        pending_attack=id;attack_notice=true
        message="A Black Knight attacks! You can use a Scroll of Protection to avoid battle."
        persist()
    else:start_site_combat()
    return true

func settle_rival() -> void:
    var row: Dictionary=rivals.find(world.active_lair)
    var opponent: Dictionary={}
    for actor in combat.simulation.actors.values():
        if actor.team==2 and actor.kind in ["black_knight","knight"]:opponent=actor;break
    if opponent.is_empty():return
    var kit: RefCounted=rivals.knight(row)
    kit.health=clampi(opponent.health,0,kit.maximum(row.inventory.items))
    kit.daggers=clampi(opponent.daggers,0,int(character_rules.dagger_limit))
    if kit.health<=0:
        kit.lives=maxi(0,kit.lives-1)
        if kit.lives>0:kit.health=kit.maximum(row.inventory.items)
    row.character=kit.snapshot()
    var player_won: bool=combat.simulation.outcome()=="victory"
    var rival_won: bool=combat.simulation.outcome()=="defeat" and opponent.health>0
    if player_won:
        if party!=null:character.experience=mini(65535,character.experience+1)
        row.loot_ready=true
        var pile: Dictionary=lair_loot[row.id]
        transfer_defeat(row.inventory,pile,row,kit.lives==0)
        kit.health=mini(kit.health,kit.maximum(row.inventory.items))
        row.character=kit.snapshot()
    elif rival_won:
        var loser_flags: Dictionary={"keys":owned_keys,"stones":quest.stones}
        transfer_defeat(inventory,row.inventory,loser_flags,character.lives==0)
        for field in ["keys","stones"]:
            row[field]=int(row[field])|int(row.inventory.get(field,0));row.inventory.erase(field)
        owned_keys=loser_flags.keys;quest.stones=loser_flags.stones
        kit.experience=mini(65535,kit.experience+1)
        row.character=kit.snapshot()
        character.health=mini(character.health,character.maximum(inventory.items))
    if kit.lives==0:world.cleared[row.id]=true
    discard_dead_dragon_target()
    if character.lives==0 and party==null:
        rivals.active=0;rivals.clear_path();turn_reason=""

func transfer_defeat(loser: Dictionary,winner: Dictionary,flags: Dictionary,all_items: bool,include_gold: bool=true) -> void:
    # LAB_001C priority: moonstone/key flags, sharp sword, ring, Acquisition,
    # Protection, Talisman, Hawk, Wyrm, potion, Gem, Haste. One slot while living.
    var moved: bool=false
    for field in ["stones","keys"]:
        var bits: int=int(flags.get(field,0))
        if bits==0:continue
        winner[field]=int(winner.get(field,0))|bits;flags[field]=0;moved=true
        if not all_items:return
    for id in Rivals.TRANSFER:
        var count: int=int(loser.items.get(id,0))
        if count<=0:continue
        var amount: int=mini(count if all_items else 1,255-int(winner.items.get(id,0)))
        if amount<=0:continue
        winner.items[id]=int(winner.items.get(id,0))+amount
        loser.items[id]-=amount
        if loser.items[id]==0:loser.items.erase(id)
        moved=true
        if not all_items:return
    if include_gold and (not moved or all_items):
        # Native bounded purses retain overflow with the loser, rather than the
        # original word/byte wrap. A final defeat also offers remaining gold.
        var amount: int=mini(int(loser.gold) if all_items else (int(loser.gold)>>1),int(character_rules.gold_limit)-int(winner.gold))
        winner.gold+=amount;loser.gold-=amount

func return_to_map(collect_remaining: bool = true) -> bool:
    if combat == null: return false
    if combat.simulation.outcome() == "victory":
        prepare_loot()
        if quest.notice:return false
        if collect_remaining: collect_all_loot()
    settle_battle()
    # Only the actual encounter result can clear a site. Retreats leave it occupied.
    var rival: Dictionary=rivals.find(world.active_lair)
    var accepted: bool = world.finish_lair(combat.simulation.outcome())
    if not rival.is_empty() and rival.character.lives>0:world.cleared.erase(rival.id)
    if accepted:
        combat = null
        loot_open = false
        if party!=null and character.lives<=0:party.end_turn(self)
        elif travel_remaining() <= 0: end_turn("travel")
        persist()
    return accepted

func prepare_loot() -> bool:
    if combat == null or combat.simulation.outcome() != "victory" or world.active_lair.is_empty():
        return false
    settle_battle()
    loot_open = true
    persist()
    return true

func available_loot() -> Dictionary:
    if not loot_open: return {}
    return lair_loot[world.active_lair].duplicate(true)

func take_loot(id: String) -> bool:
    if quest.notice or not loot_open or combat == null or combat.simulation.outcome() != "victory": return false
    var pile: Dictionary = lair_loot[world.active_lair]
    if id in quest_rules.stone_ids:
        var bit: int=1<<quest_rules.stone_ids.find(id)
        if (int(pile.get("stones",0))&bit)==0 or (quest.stones&bit)!=0:return false
        quest.stones|=bit;pile.stones=int(pile.stones)&~bit
    elif REGIONAL_KEYS.has(id):
        var bit: int = REGIONAL_KEYS[id].bit
        if (int(pile.get("keys",0)) & bit) == 0 or (owned_keys & bit) != 0: return false
        owned_keys |= bit
        pile.keys = int(pile.keys) & ~bit
        message = "Collected the " + String(REGIONAL_KEYS[id].name) + "."
    elif id == "gold":
        if pile.gold <= 0: return false
        var amount: int = mini(int(pile.gold), int(character_rules.gold_limit) - int(inventory.gold))
        if amount <= 0: return false
        inventory.gold += amount
        pile.gold -= amount
    else:
        if not loot_rules.items.has(id) or int(pile.items.get(id, 0)) <= 0: return false
        if int(inventory.items.get(id,0))>=255:return false
        inventory.items[id] = int(inventory.items.get(id, 0)) + 1
        if id == "ring_of_protection": character.health += int(character_rules.protection_health)
        pile.items[id] -= 1
        if pile.items[id] == 0: pile.items.erase(id)
    persist()
    return true

func collect_all_loot() -> void:
    if not loot_open or combat == null or combat.simulation.outcome() != "victory": return
    take_loot("gold")
    for id in REGIONAL_KEYS: take_loot(id)
    for id in quest_rules.stone_ids:take_loot(id)
    for id in available_loot().items:
        while int(lair_loot[world.active_lair].items.get(id, 0)) > 0:
            if not take_loot(id): return

func restart(seed_value: int = -1, enable_revisit_battles: bool = false, chosen_identity: Dictionary = {}) -> bool:
    if not chosen_identity.is_empty() and not Identity.valid(chosen_identity):return false
    party=null
    human_players=1
    identity=Identity.initial() if chosen_identity.is_empty() else chosen_identity.duplicate(true)
    identity.kind=int(identity.kind)
    if seed_value >= 0: reward_seed = maxi(2, seed_value & 0xffffffff)
    world.restart()
    # Confirmed solo selection starts at that knight's own village. Historical
    # unnamed fixtures retain the definition start; Continue restores saved coordinates.
    if not chosen_identity.is_empty():world.position=Locations.home(identity.kind).position.clamp(world.definition.bounds.position,world.definition.bounds.end-Vector2i.ONE)
    dragon_order=-1
    combat = null
    loot_open = false
    rivals=Rivals.new(world.definition,character_rules,loot_rules,reward_seed)
    world.rival_records=rivals.records
    character = Knight.new(character_rules)
    places=Places.initial(self)
    inventory = {"gold": int(character_rules.starting_gold), "items": {}}
    owned_keys = 0
    quest={"seed":maxi(2,(reward_seed^0x53544f4e)&0xffffffff),"stones":0,"valley_stone":0,"notice":false,"ending":{}}
    awarded_lairs.clear()
    revealed_lairs.clear()
    battle_settled = false
    revisit_battles = enable_revisit_battles
    day = 1
    travel_spent = 0
    haste = false
    turn_pending = false
    turn_reason = ""
    message = ""
    town_id = ""
    town_lock = ""
    service = ""
    henge = {}
    henge_lock = false
    pending_attack = ""
    attack_notice = false
    lair_loot.clear()
    var roller: RefCounted = Roller.new(loot_rules, reward_seed)
    for site in world.sites():
        lair_loot[site.id] = roller.roll_lair()
        lair_loot[site.id].keys = 0
        if site.id=="roaming_dragon":lair_loot[site.id].stones=0
        if not rivals.find(site.id).is_empty():lair_loot[site.id]={"gold":0,"items":{},"kind":4,"keys":0,"stones":0}
    # Source Valley victory grants a moonstone directly, not a random chest.
    # Keep the original generation order for all other chest rolls.
    lair_loot.valley_guardian={"gold":0,"items":{},"kind":4,"keys":0}
    persist()

    return true

func start_local_party(roster: Array,seed_value: int,enable_revisit: bool=false) -> bool:
    if not world.definition.rival_turns or not LocalParty.valid_players(roster,Archive.integer):return false
    var previous_store: RefCounted=store
    store=null # Do not commit an intermediate solo campaign during setup.
    restart(seed_value,enable_revisit)
    mode=&"competitive"
    party=LocalParty.new();party.configure(self,roster)
    store=previous_store
    return persist()

func snapshot() -> Dictionary:
    return {"schema": 16, "content": "journey.campaign.v14", "identity":identity.duplicate(true), "places":places.duplicate(true), "dragon_order":dragon_order, "rivals":rivals.snapshot(), "options":{"revisit_battles":revisit_battles}, "world": world.snapshot(), "quest":quest.duplicate(true),
        "henge": henge.duplicate(true), "henge_lock": henge_lock,
        "mode": String(mode), "reward_seed": reward_seed, "loot_open": loot_open,
        "inventory": inventory.duplicate(true), "lair_loot": lair_loot.duplicate(true),
        "character": character.snapshot(), "awarded_lairs": awarded_lairs.duplicate(true),
        "revealed_lairs": revealed_lairs.duplicate(true), "battle_settled": battle_settled,
        "human_players": human_players, "day": day, "travel_spent": travel_spent, "haste": haste,
        "town_id": town_id, "town_lock": town_lock, "service": service,
        "pending_attack": pending_attack, "attack_notice": attack_notice, "owned_keys": owned_keys,
        "turn_pending": turn_pending, "turn_reason": turn_reason}

func settle_battle() -> void:
    if combat == null or battle_settled: return
    var player: Dictionary = combat.simulation.actors[1]
    character.health = clampi(int(player.health), 0, character.maximum(inventory.items))
    character.daggers = clampi(int(player.daggers), 0, int(character_rules.dagger_limit))
    if character.health <= 0:
        character.lives = maxi(0, character.lives - int(world.lair(world.active_lair).get("life_cost",1)))
        # Temporary recovery between attempts until towns/resurrection are added.
        if character.lives > 0: character.health = character.maximum(inventory.items)
    var party_valley_survivor: bool=world.active_lair=="valley_guardian" and mode==&"cooperative" and character.lives>0
    if combat.simulation.outcome() == "victory" and (player.health > 0 or party_valley_survivor):
        var first_win: bool=not awarded_lairs.has(world.active_lair)
        if not rivals.find(world.active_lair).is_empty():first_win=false
        if first_win or repeat_lair_battle(world.active_lair):
            character.experience = mini(65535,character.experience+int(world.lair(world.active_lair).get("experience",character_rules.lair_experience)))
        if first_win:
            awarded_lairs[world.active_lair] = true
            if world.active_lair=="valley_guardian":award_moonstone()
            offer_region_key(world.active_lair)
    if world.active_lair=="roaming_dragon":
        if combat.simulation.outcome()=="defeat":dragon_takes_human()
        elif combat.simulation.outcome()=="victory":clear_dragon_order()
    if not rivals.find(world.active_lair).is_empty():settle_rival()
    battle_settled = true

func on_map() -> bool:
    if party!=null and (party.awaiting or party.game_over):return false
    return (rivals.active==0 or not pending_attack.is_empty()) and not quest.notice and quest.ending.is_empty() and henge.is_empty() and not turn_pending and combat == null and (world.active_lair.is_empty() or not pending_attack.is_empty()) and character.lives > 0

func upgrade_cost() -> int:
    return int(character_rules.stat_costs[clampi(human_players, 1, 4) - 1])

func looting() -> bool:
    # Character actions are safe only after this victory's kit and XP settle.
    return loot_open and battle_settled and combat != null and combat.simulation.outcome()=="victory" and not world.active_lair.is_empty() and not quest.notice and quest.ending.is_empty() and henge.is_empty() and character.lives>0 and character.health>0

func upgrade_stat(stat: String) -> bool:
    var henge_temple: bool=henge.get("phase","")=="temple"
    if not looting() and not henge_temple and (not on_map() or service != "temple" or town_id.is_empty()):
        message = "Raise abilities while looting or at the temple in Highwood."
        return false
    var success: bool = character.upgrade(stat, upgrade_cost(), inventory.items)
    message = "%s increased." % stat.capitalize() if success else "Need %d experience and a stat below %d." % [upgrade_cost(), character_rules.stat_limit]
    if success: persist()
    return success

func buy_equipment(id: String) -> bool:
    if not on_map() or service != "smith" or town_id.is_empty():
        message = "Visit a town smith to buy equipment."
        return false
    var row: Dictionary = {}
    var kind: String = ""
    if character_rules.weapons.has(id):
        row = character_rules.weapons[id]
        kind = "weapon"
        if int(row.rank) <= int(character_rules.weapons[character.effective_weapon(inventory.items)].rank):
            message = "Your current sword is as good or better."
            return false
    elif character_rules.armours.has(id):
        row = character_rules.armours[id]
        kind = "armour"
        if int(row.rank) <= int(character_rules.armours[character.armour].rank):
            message = "Your current armour is as good or better."
            return false
    elif id == "dagger":
        row = {"name": "Throwing dagger", "price": int(character_rules.dagger_price)}
        if character.daggers >= int(character_rules.dagger_limit):
            message = "Already carrying the maximum daggers."
            return false
    else: return false
    var price: int = int(row.price)
    if price <= 0 or int(inventory.gold) < price:
        message = "Not enough gold."
        return false
    inventory.gold -= price
    if kind == "weapon": character.weapon = id
    elif kind == "armour":
        var previous_maximum: int = character.maximum(inventory.items)
        character.armour = id
        character.health += character.maximum(inventory.items) - previous_maximum
    else: character.daggers += 1
    message = "Bought " + String(row.name) + "."
    persist()
    return true

func use_item(id: String, target: Variant = null) -> bool:
    if (not on_map() and not looting()) or int(inventory.items.get(id, 0)) <= 0 or not character_rules.items.has(id): return false
    var effect: String = character_rules.items[id].effect
    if not pending_attack.is_empty():
        return resolve_pending_attack(true) if id=="scroll_of_protection" else false
    if effect=="rival":
        if not Scrolls.acquire(self,target):return false
    elif effect=="dragon_target":
        if not Scrolls.send_wyrm(self,target):return false
    elif effect == "heal":
        if not character.heal(inventory.items):
            message = "Health and lives are already full. Potion kept."
            return false
        message = "Healing potion used."
    elif effect == "haste":
        if haste:
            message = "Haste already lasts for this turn. Scroll kept."
            return false
        haste = true
        message = "This turn's travel allowance doubled."
    elif effect == "reveal":
        if typeof(target) != TYPE_STRING or not lair_loot.has(target) or world.cleared.has(target): return false
        revealed_lairs[target] = true
        message = "Treasure revealed. No reward claimed."
    elif effect == "teleport":
        var leaving_place: bool=not town_id.is_empty()
        if typeof(target) != TYPE_VECTOR2I or not world.definition.bounds.has_point(target) or target == world.position: return false
        if party!=null:party.transaction_depth+=1
        # Leaving by magic closes this result without collecting its remainder.
        # Do this before moving so a lair cannot stay active at the destination.
        if looting() and not return_to_map(false):
            if party!=null:party.finish_transaction(self)
            return false
        world.position = target
        town_id = ""
        service = ""
        town_lock = ""
        places.visit={}
        if leaving_place:end_turn("town")
        message = "Arrived at the chosen destination."
    else:
        if effect in ["passive","dragon_passive"]: message = "Automatically active while carried."
        elif id=="scroll_of_protection": message = "Use protection before an incoming knight battle. Scroll kept."
        else: message = "This item's targeting interaction is not implemented yet. Item kept."
        return false
    inventory.items[id] -= 1
    if inventory.items[id] <= 0: inventory.items.erase(id)
    if effect=="teleport" and party!=null:party.finish_transaction(self)
    else:persist()
    return true

func travel_allowance() -> int:
    return character.endurance() * int(character_rules.travel_per_endurance) * (2 if haste else 1)

func travel_remaining() -> int:
    return maxi(0, travel_allowance() - travel_spent)

func rest() -> bool:
    if not town_id.is_empty(): return false
    return end_turn("rest")

func calendar() -> Dictionary:
    # A round completes only after the three rival slots return to the human.
    # Historical single-knight fixtures explicitly omit those slots.
    var completed: int = day - 1
    var lunar: int = completed / int(world.definition.dragon_rules.rounds_per_counter)
    return {"round": day, "completed_rounds": completed, "lunar_counter": lunar,
        "moon_phase": lunar % 8, "moon_subcount": completed % int(world.definition.dragon_rules.rounds_per_counter)}

func end_turn(reason: String) -> bool:
    if not on_map() or not pending_attack.is_empty() or not town_id.is_empty() or reason not in ["rest","travel","town","stonehenge"]: return false
    if party!=null:party.end_turn(self);return true
    if not rivals.records.is_empty():
        turn_reason=reason
        rivals.start()
        world.dragon.reset()
        message="The other knights are taking their turns."
        persist()
        return true
    complete_round(reason)
    return true

func complete_round(reason: String = "") -> void:
    if not reason.is_empty():turn_reason=reason
    day += 1
    rivals.upkeep(day-1)
    places.recency=maxi(0,int(places.recency)-10)
    places.frog_days=maxi(0,int(places.frog_days)-1)
    haste = false
    travel_spent = 0
    character.rest(inventory.items)
    turn_pending = true
    message = "Round %d. Travel renewed; some health recovered." % day
    persist()

func clear_dragon_order() -> void:
    dragon_order = -1
    if party != null:
        party.wyrm_target = -1

func discard_dead_dragon_target() -> void:
    if party!=null and party.wyrm_target>=0 and party.record(self,party.wyrm_target).character.lives<=0:clear_dragon_order()
    if dragon_order>0 and rivals.records[dragon_order-1].character.lives<=0:clear_dragon_order()
    if world.dragon.active and world.dragon.target>0 and rivals.records[world.dragon.target-1].character.lives<=0:world.dragon.reset()

func dragon_aim() -> Vector2i:
    discard_dead_dragon_target()
    var flight: RefCounted=world.dragon
    if not flight.active and not world.cleared.has("roaming_dragon") and calendar().completed_rounds>=int(flight.rules.spawn_counter)*int(flight.rules.rounds_per_counter):
        var selected: int=dragon_order
        if party!=null and party.wyrm_target>=0:
            selected=0 if party.wyrm_target==party.active else party.others().find(party.wyrm_target)+1
        if selected<0:
            # Reference dragonPickTarget draws among all four living records.
            # Native saved AI RNG is independent of pre-rolled lair rewards.
            for attempt in range(4096):
                var candidate: int=rivals.random.next_value()&3
                if candidate==0 and character.lives>0 or candidate>0 and rivals.records[candidate-1].character.lives>0:
                    selected=candidate;break
        flight.target=maxi(0,selected)
    return world.position if flight.target==0 else rivals.records[flight.target-1].position

func advance_rival_turn() -> void:
    var slot: int=rivals.active
    if slot==0:return
    rivals.advance(self)
    if rivals.active!=slot or combat!=null or not pending_attack.is_empty():return
    var caught: bool=world.dragon.advance(day-1,dragon_aim(),not world.cleared.has("roaming_dragon"),slot)
    if not caught:return
    var row: Dictionary=rivals.records[slot-1]
    var kit: RefCounted=rivals.knight(row)
    kit.lives=maxi(0,kit.lives-1)
    dragon_takes(row.inventory,row,kit.lives==0)
    kit.health=mini(kit.health,kit.maximum(row.inventory.items)) if kit.lives>0 else 0
    row.character=kit.snapshot()
    if kit.lives==0:world.cleared[row.id]=true
    message="The Dragon caught "+String(world.lair(row.id).name)+"."
    clear_dragon_order()
    world.dragon.reset()
    rivals.finish_slot(self)
    persist()

func dragon_takes(loser: Dictionary,flags: Dictionary,final_defeat: bool) -> void:
    var pile: Dictionary=lair_loot.roaming_dragon
    # Dragon settlement takes half gold in addition to a priority object/flag.
    # Retain overflow instead of the original signed-word/byte wrap quirks.
    var amount: int=mini(int(loser.gold)>>1,int(character_rules.gold_limit)-int(pile.gold))
    loser.gold-=amount;pile.gold+=amount
    transfer_defeat(loser,pile,flags,final_defeat,false)

func dragon_takes_human() -> void:
    var flags: Dictionary={"keys":owned_keys,"stones":quest.stones}
    dragon_takes(inventory,flags,character.lives==0)
    owned_keys=flags.keys;quest.stones=flags.stones
    character.health=mini(character.health,character.maximum(inventory.items))
    clear_dragon_order()

func begin_turn() -> bool:
    if party!=null:return party.begin_turn(self)
    if not turn_pending: return false
    turn_pending = false
    turn_reason = ""
    message = "Round %d begins." % day
    if places.frog_days>0:
        end_turn("rest")
        message="Math's frog spell keeps you from acting today."
    persist()
    return true

func town(id: String) -> Dictionary:
    for place in world.definition.towns:
        if place.id == id: return place
    if id=="home":return Locations.home(identity.kind)
    if id=="wizard":return Locations.place(id)
    return {}

func arrivals() -> Array[Dictionary]:
    var empty: Array[Dictionary]=[]
    if on_map() and town_id.is_empty():return Locations.arrivals(self)
    return empty

func confirm_location(id: String) -> bool:
    if not on_map() or turn_pending or not town_id.is_empty() or not pending_attack.is_empty():return false
    var available: Array[Dictionary]=arrivals()
    if not available.any(func(row: Dictionary) -> bool:return row.id==id):return false
    if not rivals.find(id).is_empty():return begin_rival_encounter(id,false)
    if id=="stonehenge":
        henge_lock=false
        return enter_henge()
    if id in ["home","wizard","highwood","waterdeep"]:return enter_town(id)
    world.active_lair=id
    if world.cleared.has(id):
        enter_cleared_lair()
    else:start_site_combat()
    return true

func repeat_lair_battle(id: String) -> bool:
    return revisit_battles and world.cleared.has(id) and has_treasure(id) and world.definition.lairs.any(func(site: Dictionary) -> bool:return site.id==id)

func enter_cleared_lair() -> void:
    if repeat_lair_battle(world.active_lair):
        start_site_combat()
        return
    make_completed_encounter()
    loot_open=true
    battle_settled=true
    persist()

func enter_town(id: String) -> bool:
    var place: Dictionary = town(id)
    if not on_map() or not town_id.is_empty() or place.is_empty() or not world.inside_lair(place): return false
    town_id = id
    world.dragon.reset() # Place visits restart the next pass from the map edge.
    service = ""
    message = "Welcome to " + String(place.name) + "."
    if id=="home":
        character.lives=mini(3,character.lives+1) if character.lives<3 else character.lives
        service="temple"
        message=HOME_VISIT_MESSAGE
    elif id=="wizard":
        service="temple"
        Places.open(self,"wizard")
        message="Math the wizard welcomes you."
    persist()
    return true

func open_service(id: String) -> bool:
    if not on_map() or town_id.is_empty() or not id in town(town_id).services: return false
    service = id
    if id in ["healer","mystic","tavern"]:Places.open(self,id)
    elif town_id!="wizard":places.visit={}
    persist()
    return true

func leave_town() -> bool:
    if town_id.is_empty() or combat != null: return false
    places.visit={}
    town_lock = town_id
    town_id = ""
    service = ""
    end_turn("town")
    return true

func buy_healing(id: String) -> bool:
    if not on_map() or town_id.is_empty() or service != "healer": return false
    var price: int = int(character_rules.healer_health_price) if id == "heal_health" else int(character_rules.healer_life_price)
    if id == "heal_health":
        if character.health >= character.maximum(inventory.items):
            message = "Already at full health."
            return false
    elif id == "heal_life":
        if character.health != character.maximum(inventory.items) or character.lives >= int(character_rules.life_limit):
            message = "Restore full health first; lives stop at five."
            return false
    else: return false
    if inventory.gold < price:
        message = "Not enough gold for the healer."
        return false
    inventory.gold -= price
    if id == "heal_health": character.health = character.maximum(inventory.items)
    else: character.lives += 1
    message = "Health restored." if id == "heal_health" else "One life restored."
    persist()
    return true

func checkpoint() -> Dictionary:
    if combat != null and not battle_settled and combat.simulation.outcome() != "ongoing":
        settle_battle()
        if combat.simulation.outcome() == "victory": loot_open = true
    var data: Dictionary = snapshot()
    data.phase = "attack" if not pending_attack.is_empty() else ("loot" if loot_open else "map")
    if not loot_open and pending_attack.is_empty():
        if not data.world.active_lair.is_empty():
            data.world.entry_lock = data.world.active_lair
            data.world.active_lair = ""
            data.world.last_result = "retreated"
        data.battle_settled = false
    return party.wrap(self,data) if party!=null else data

func validate_checkpoint(data: Variant) -> Dictionary:
    if typeof(data)==TYPE_DICTIONARY and data.get("schema")==17:return LocalParty.validate(data,validate_solo_checkpoint,Archive.integer)
    return validate_solo_checkpoint(data)

func validate_solo_checkpoint(data: Variant, extra_chests: Array = [], party_context: bool = false) -> Dictionary:
    return Archive.validate(data, world.definition, character_rules, loot_rules, extra_chests, party_context)

func restore_checkpoint(data: Variant) -> bool:
    var d: Dictionary = validate_checkpoint(data)
    if d.is_empty(): return false
    var party_data: Dictionary={}
    if d.schema==17:party_data=d.party;d=d.campaign
    party=null
    # All checks finish before this first mutation; no object deserialisation.
    places=d.places.duplicate(true)
    identity=d.identity.duplicate(true)
    dragon_order=d.dragon_order
    rivals.restore(d.rivals)
    world.rival_records=rivals.records
    mode = StringName(d.mode)
    revisit_battles = d.options.revisit_battles
    reward_seed = d.reward_seed
    human_players = d.human_players
    day = d.day
    travel_spent = d.travel_spent
    haste = d.haste
    turn_pending = d.turn_pending
    turn_reason = d.turn_reason
    town_id = d.town_id
    town_lock = d.town_lock
    service = d.service
    inventory = d.inventory.duplicate(true)
    lair_loot = d.lair_loot.duplicate(true)
    owned_keys = int(d.owned_keys)
    quest=d.quest.duplicate(true)
    awarded_lairs = d.awarded_lairs.duplicate(true)
    revealed_lairs = d.revealed_lairs.duplicate(true)
    character = Knight.new(character_rules)
    henge=d.henge.duplicate(true)
    henge_lock=d.henge_lock
    for field in ["stats", "experience", "lives", "health", "daggers", "weapon", "armour", "life_loss"]:
        character.set(field, d.character[field].duplicate(true) if typeof(d.character[field]) == TYPE_DICTIONARY else d.character[field])
    world.tick = d.world.tick
    world.position = Vector2i(d.world.position.x, d.world.position.y)
    world.facing = d.world.facing
    world.cleared = d.world.cleared.duplicate(true)
    world.active_lair = d.world.active_lair
    world.entry_lock = d.world.entry_lock
    world.last_result = d.world.last_result
    world.terrain_counter = d.world.terrain_counter
    world.last_step_cost = 0
    world.dragon.restore(d.world.dragon)
    world.dragon_hoard = Vector2i(d.world.dragon_hoard.x, d.world.dragon_hoard.y)
    battle_settled = d.battle_settled
    loot_open = d.loot_open
    combat = null
    pending_attack = d.pending_attack
    attack_notice = d.attack_notice
    if loot_open:
        # Recreate only the completed encounter adapter for the loot UI. Live fights
        # resume from their entrance checkpoint instead of restoring animation state.
        make_completed_encounter()
    world.rival_labels.clear()
    if not party_data.is_empty():party=LocalParty.new();party.restore(party_data);party.update_labels(self)
    message = "Journey continued."
    return true

func persist() -> bool:
    if party!=null and party.transaction_depth>0:return true
    if store == null: return true
    var success: bool = store.save_checkpoint(checkpoint())
    save_message = store.message
    if not success: message = save_message
    return success

func has_treasure(id: String) -> bool:
    var pile: Dictionary = lair_loot[id]
    return pile.gold > 0 or not pile.items.is_empty() or int(pile.get("keys",0)) != 0 or int(pile.get("stones",0))!=0

func make_completed_encounter() -> void:
    world.dragon.reset()
    combat = Combat.new(rules)
    combat.knight_profile = character.combat_profile(inventory.items)
    combat.start(mode, world.lair(world.active_lair).encounter)
    combat.simulation.spawn_remaining = 0
    for actor in combat.simulation.actors.values():
        if actor.team == 2: actor.health = 0
    combat.simulation.actors[1].health = maxi(1, character.health)

func inside_henge() -> bool:
    if world.definition.confirm_entry:return Locations.touches(world.position,Henge.POSITION,Vector2i(18,12))
    return world.position.distance_squared_to(Henge.POSITION)<=world.definition.entry_radius*world.definition.entry_radius

func enter_henge() -> bool:
    if not on_map() or not town_id.is_empty() or not inside_henge() or henge_lock: return false
    if quest_rules.matches(quest.stones,calendar().moon_phase):
        var frame: int=quest_rules.moon_frames[calendar().moon_phase]
        quest.ending={"stage":"message","tick":0,"frame":frame,"knight_kind":identity.kind,"code":quest_rules.ending_code(frame,identity.kind)}
        world.dragon.reset()
        persist()
        return true
    henge={"phase":"greeting","tick":0,"offered":""}
    world.dragon.reset()
    message=""
    persist()
    return true

func advance_henge() -> bool:
    if henge.get("phase","")!="greeting": return false
    henge.phase="offering"
    persist()
    return true

func offer_henge_item(id: String) -> bool:
    if henge.get("phase","")!="offering" or not loot_rules.items.has(id) or int(inventory.items.get(id,0))<1: return false
    # The original's second decrement uses a sound channel as an inventory slot.
    # Consume one deliberate selection and recalculate passive bonuses safely.
    inventory.items[id]-=1
    if inventory.items[id]==0: inventory.items.erase(id)
    character.health=mini(character.health,character.maximum(inventory.items))
    henge={"phase":"prelude","tick":0,"offered":id}
    persist()
    return true

func tick_henge() -> void:
    var phase: String=henge.get("phase","")
    if phase not in ["prelude","ritual"]: return
    henge.tick+=1
    if phase=="prelude" and henge.tick>=Henge.PRELUDE_TICKS:
        henge.phase="ritual";henge.tick=0
        persist()
    elif phase=="ritual" and henge.tick>=Henge.RITUAL_TICKS: complete_henge()

func complete_henge() -> bool:
    if henge.get("phase","") not in ["prelude","ritual"]: return false
    character.lives=mini(int(character_rules.life_limit),character.lives+1)
    character.health=character.maximum(inventory.items)
    character.life_loss=0
    henge.phase="temple";henge.tick=0
    persist() # Reward and completed stage are one checkpoint.
    return true

func leave_henge_offering() -> bool:
    if henge.get("phase","")!="offering": return false
    henge.phase="temple"
    persist()
    return true

func leave_henge() -> bool:
    if henge.get("phase","")!="temple": return false
    henge={};henge_lock=true
    return end_turn("stonehenge")

func award_moonstone() -> bool:
    if quest.valley_stone!=0 or not awarded_lairs.has("valley_guardian"):return false
    var roller: RefCounted=Roller.new(loot_rules,quest.seed)
    var value: int=roller.next_value()
    quest.seed=roller.state
    quest.valley_stone=1<<(value&3)
    quest.stones|=int(quest.valley_stone)
    quest.notice=true
    owned_keys=0
    return true

func acknowledge_moonstone() -> bool:
    if not quest.notice:return false
    quest.notice=false
    persist()
    return true

func tick_quest() -> void:
    if quest.ending.get("stage","")=="message":quest.ending.tick=mini(20,int(quest.ending.tick)+1)

func enter_ending() -> bool:
    if quest.ending.get("stage","")!="message" or quest.ending.tick<20:return false
    quest.ending.stage="ready"
    quest.ending.tick=0
    persist()
    return true

func tick_ending() -> void:
    if quest.ending.get("stage","")!="ready":return
    quest.ending.tick+=1
    if quest.ending.tick>=preload("res://scripts/domain/moonstone_quest.gd").ENDING_TICKS:
        finish_ending()
    elif quest.ending.tick%50==0:persist()

func finish_ending() -> bool:
    if quest.ending.get("stage","")!="ready":return false
    quest.ending.stage="complete"
    quest.ending.tick=preload("res://scripts/domain/moonstone_quest.gd").ENDING_TICKS
    persist()
    return true
