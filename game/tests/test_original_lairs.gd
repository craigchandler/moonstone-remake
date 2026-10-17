extends SceneTree

const Journey=preload("res://scripts/session/journey_session.gd")
const Roller=preload("res://scripts/domain/loot_roller.gd")
var definition: Resource=preload("res://content/first_journey.tres")
var rules: Resource=preload("res://content/foundation_rules.tres")
var failures: int=0

func check(ok: bool,label: String) -> void:
    if not ok:
        failures+=1
        push_error(label)

func fresh() -> RefCounted:
    return Journey.new(definition,rules,0x4d4f4f4e)

func win(journey: RefCounted) -> void:
    journey.combat.simulation.spawn_remaining=0
    for actor in journey.combat.simulation.actors.values():
        if actor.team==2: actor.health=0

func _initialize() -> void:
    var source=JSON.parse_string(FileAccess.get_file_as_string("res://content/generated/original_lairs.json"))
    check(source.size()==24 and definition.lairs.size()==24,"all 24 original lairs")
    var regions: Dictionary={}
    var encountered: Dictionary={}
    for i in range(24):
        var site: Dictionary=definition.lairs[i]
        var retail: Dictionary=source[i]
        check(site.id==retail.id and site.position==Vector2i(retail.x,retail.y) and site.encounter==retail.encounter and site.count==retail.count and site.region_code==retail.region_code,"retail position/kind/count/region: "+site.id)
        regions[site.region]=int(regions.get(site.region,0))+1
        encountered[site.encounter]=true
        var journey: RefCounted=fresh()
        journey.world.position=site.position-Vector2i(8,0)
        for step in range(64):
            journey.travel(Vector2i.RIGHT)
            if journey.confirm_location(site.id):break
        check(journey.world.active_lair==site.id and journey.combat!=null,"walking starts the correct original site: "+site.id)
        if journey.combat==null: continue
        check(String(journey.combat.simulation.encounter)==site.encounter,"correct combat routed: "+site.id)
        var options: Dictionary=journey.encounter_options(site)
        check(journey.combat.simulation.encounter_settings.count==options.count,"original count with reference scaling: "+site.id)
        var loot: Dictionary=journey.lair_loot[site.id].duplicate(true)
        win(journey)
        journey.prepare_loot()
        var checkpoint: Dictionary=journey.checkpoint()
        var resumed: RefCounted=fresh()
        check(resumed.restore_checkpoint(checkpoint) and resumed.available_loot()==loot,"all creature loot contexts save exactly: "+site.id)
        resumed.return_to_map()
        check(resumed.world.cleared.has(site.id) and resumed.character.experience==1,"single lair reward: "+site.id)
    check(regions.size()==4 and regions.values().all(func(n: int) -> bool:return n==6),"six sites in every original region")
    check(encountered.size()==8,"all eight lair creature/weapon types occur")
    # Old campaign saves migrate without rerolling chests or losing character data.
    var old: RefCounted=Journey.new(load("res://scripts/content/world_definition.gd").new(),rules,12)
    old.inventory.gold=91
    old.inventory.items={"ring_of_protection":2,"scroll_of_protection":1}
    old.character.stats.strength=3
    old.character.experience=2
    var previous: Dictionary=old.checkpoint()
    previous.schema=3
    previous.content="journey.campaign.v1"
    previous.world.content="journey.v5"
    previous.world.schema=1
    previous.world.erase("dragon")
    previous.world.erase("dragon_hoard")
    previous.erase("pending_attack")
    previous.erase("attack_notice")
    for site in definition.special_encounters: previous.lair_loot.erase(site.id)
    var before: Dictionary=previous.duplicate(true)
    var migrated: RefCounted=fresh()
    check(migrated.restore_checkpoint(previous),"old Journey save migrates")
    check(previous==before,"migration never changes caller-owned old save")
    check(migrated.character.snapshot()==old.character.snapshot() and migrated.inventory==old.inventory,"all legacy character/pack state preserved")
    for id in previous.lair_loot: check(migrated.lair_loot[id]==previous.lair_loot[id],"old chest remains exact: "+id)
    check(migrated.lair_loot.size()==29,"separate boss/roaming reward contexts added")
    var complete_old: Dictionary=previous.duplicate(true)
    for site in definition.lairs:
        if site.region=="Great Forest":
            complete_old.awarded_lairs[site.id]=true
            complete_old.world.cleared[site.id]=true
    var recovered: RefCounted=fresh()
    check(recovered.restore_checkpoint(complete_old) and recovered.owned_keys==0,"old completed region does not invent held key")
    var recovered_site: Dictionary=definition.lairs[5]
    check(recovered.has_treasure(recovered_site.id) and recovered.lair_loot[recovered_site.id].keys==8,"old cleared region gets one recoverable chest key")
    recovered.world.position=recovered_site.position-Vector2i(6,0)
    for step in range(8):
        recovered.travel(Vector2i.RIGHT)
        if recovered.confirm_location(recovered_site.id):break
    check(recovered.loot_open and recovered.take_loot("key_forest") and recovered.owned_keys==8,"migrated key is reachable without repeating combat or XP")
    # Protection is an explicit pre-combat choice, and survives save/continue.
    var ambushed: RefCounted=fresh()
    ambushed.inventory.items.scroll_of_protection=2
    var knight: Dictionary=ambushed.world.lair("roaming_black_knight")
    ambushed.world.position=knight.position-Vector2i(5,0)
    ambushed.begin_rival_encounter("roaming_black_knight",true)
    check(ambushed.attack_notice and ambushed.combat==null,"incoming knight warns before combat")
    var pending: Dictionary=ambushed.checkpoint()
    var continued: RefCounted=fresh()
    check(continued.restore_checkpoint(pending) and continued.attack_notice and continued.pending_attack=="roaming_black_knight","continue cannot bypass pending attack")
    check(continued.use_item("scroll_of_protection") and continued.inventory.items.scroll_of_protection==1 and continued.combat==null and continued.world.cleared.is_empty(),"explicit scroll use consumes one and avoids without rewards")
    continued=fresh()
    check(continued.restore_checkpoint(pending),"pending attack can be reopened")
    continued.dismiss_attack_notice()
    check(continued.resolve_pending_attack(false) and continued.combat.simulation.encounter==&"black_knight_fight" and continued.inventory.items.scroll_of_protection==2,"leaving pack starts battle and keeps scroll")
    var boss: RefCounted=fresh()
    boss.world.active_lair="valley_guardian"
    boss.start_site_combat()
    check(boss.combat==null and boss.world.active_lair=="","Valley refuses entry without four regional keys")
    for site in definition.lairs: boss.awarded_lairs[site.id]=true
    check(boss.key_mask()==0,"clearing sites alone never invents key possession")
    boss=fresh()
    for key_id in boss.REGIONAL_KEYS:
        var area: String=boss.REGIONAL_KEYS[key_id].region
        var sites: Array=[]
        for site in definition.lairs:
            if site.region==area: sites.append(site)
        for index in range(sites.size()):
            boss.world.active_lair=sites[index].id
            boss.start_site_combat()
            win(boss)
            boss.prepare_loot()
            var offered: int=int(boss.available_loot().keys)
            check(offered==(int(boss.REGIONAL_KEYS[key_id].bit) if index==5 else 0),"key only appears after area's final lair")
            if index==5:
                check((boss.key_mask() & offered)==0,"key must be looted before it is owned")
                var key_save: Dictionary=boss.checkpoint()
                var copy: RefCounted=fresh()
                check(copy.restore_checkpoint(key_save) and copy.available_loot().keys==offered and copy.key_mask()==boss.key_mask(),"uncollected key survives Continue")
                check(boss.take_loot(key_id) and not boss.take_loot(key_id),"key pickup transfers exactly once")
            boss.return_to_map()
    check(boss.key_mask()==15,"all four collected regional keys permit Valley access")
    var key_copy: RefCounted=fresh()
    check(key_copy.restore_checkpoint(boss.checkpoint()) and key_copy.key_mask()==15,"owned keys survive Continue")
    var invalid: Dictionary=boss.checkpoint()
    invalid.owned_keys=16
    check(not key_copy.restore_checkpoint(invalid) and key_copy.key_mask()==15,"malformed key save rejected before live mutation")
    invalid=boss.checkpoint()
    invalid.lair_loot[definition.lairs[0].id].keys=8
    check(not key_copy.restore_checkpoint(invalid),"duplicate key in pack and chest is rejected")
    for mask in [1,3,7]:
        key_copy.owned_keys=mask
        key_copy.world.active_lair="valley_guardian"
        key_copy.start_site_combat()
        check(key_copy.combat==null,"partial distinct key set cannot enter Valley")
    boss.world.active_lair="valley_guardian"
    boss.start_site_combat()
    boss.combat.simulation.actors[1].health=0
    boss.settle_battle()
    check(boss.character.lives==2,"Guardian defeat costs three lives once")
    if failures==0: print("PASS: exact retail 24-site placement/kind/count/region and actual routing, eight lair types, per-site loot/save/XP, lossless legacy migration, separate roaming/Valley contexts, protection choice/continuation and Guardian stakes")
    quit(1 if failures else 0)
