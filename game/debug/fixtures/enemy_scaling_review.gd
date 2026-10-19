extends RefCounted

# Explicit diagnostic only. Ordinary play never reads the external numeric
# reference fixture. Actual rules, journey entry and spawn services are used.
const Journey=preload("res://scripts/session/journey_session.gd")
const Host=preload("res://scripts/domain/encounter_scaling_host.gd")
var rules: Resource=preload("res://content/foundation_rules.tres")
var definition: Resource=preload("res://content/first_journey.tres")
var checks: int=0
var failures: Array[String]=[]

func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failures.append(label)

func configure(j: RefCounted,p: Dictionary) -> void:
    j.character.stats={"strength":int(p.strength),"constitution":int(p.constitution),"endurance":int(p.endurance)}
    j.character.weapon=p.weapon;j.character.armour=p.armour;j.character.experience=int(p.experience)
    j.inventory.items=p.items.duplicate(true)
    for key in j.inventory.items:j.inventory.items[key]=int(j.inventory.items[key])
    j.character.health=int(p.health)
    j.quest.stones=int(p.stones)
    j.day=int(p.phase)*int(j.world.definition.dragon_rules.rounds_per_counter)+1

func run_checks(path: String) -> Dictionary:
    var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
    if not data is Dictionary or not data.has_all(["cases","profiles","rows"]):
        return {"checks":0,"failures":["Missing numeric reference fixture"],"profiles":[]}
    for row in data.cases:
        var before: Dictionary=row.facts.duplicate(true)
        var actual: Dictionary=Host.options(rules,row.facts)
        check(actual=={"count":int(row.expected.count),"concurrent":int(row.expected.concurrent)},"retail table/threshold: "+str(row.facts))
        check(row.facts==before,"scaling leaves caller facts unchanged")
    var profiles: Array=[]
    for p in data.profiles:
        var j: RefCounted=Journey.new(definition,rules,0x4d4f4f4e)
        configure(j,p)
        check(j.character.maximum(j.inventory.items)==int(p.maximum_hp),"profile maximum "+p.id)
        var original_loot: Dictionary=j.lair_loot.duplicate(true)
        var original_seed: int=j.reward_seed
        var original_character: Dictionary=j.character.snapshot()
        var sites: Array=[]
        for row in p.sites:
            var site: Dictionary=j.world.lair(row.id)
            var before: Dictionary=j.snapshot()
            var options: Dictionary=j.encounter_options(site)
            check(j.snapshot()==before,"query cannot change inventory, XP, world, reward or rival RNG")
            check(options.count==int(row.expected.count) and options.concurrent==int(row.expected.concurrent),"independent original lair "+p.id+":"+row.id)
            j.world.active_lair=site.id;j.start_site_combat()
            var m: RefCounted=j.combat.simulation
            var living: Array=m.actors.values().filter(func(a: Dictionary) -> bool:return a.team==2 and a.health>0)
            check(m.encounter_settings.count==options.count and m.encounter_settings.concurrent==options.concurrent,"real journey entry uses scaled values")
            check(living.size()==mini(options.count,options.concurrent) and m.spawn_remaining==options.count-living.size(),"initial slots and queued remainder")
            var hp: Array=[]
            var expected_hp: int=rules.actor_definitions[row.kind].maximum_health
            if row.kind=="ratman":expected_hp=7 if int(p.phase)==0 else (12 if int(p.phase)==4 else 5)
            for a in living:
                hp.append(a.health)
                check(a.health==expected_hp,"scaling does not inflate individual HP")
            sites.append({"id":site.id,"kind":row.kind,"base_count":int(site.count),"count":m.encounter_settings.count,"concurrent":m.encounter_settings.concurrent,"initial":living.size(),"remaining":m.spawn_remaining,"hp":hp})
            var total: int=0
            while not living.is_empty():
                living[0].health=0;total+=1;m.fill_wave_slots()
                living=m.actors.values().filter(func(a: Dictionary) -> bool:return a.team==2 and a.health>0)
                check(living.size()<=options.concurrent,"refills respect concurrent cap")
                if total>60:break
            check(total==options.count and m.spawn_remaining==0,"entire wave spawns exactly once")
            check(j.lair_loot==original_loot and j.reward_seed==original_seed and j.character.snapshot()==original_character,"setup/refill cannot award XP, spend health or reroll loot")
        profiles.append({"id":p.id,"maximum_hp":int(p.maximum_hp),"matching_moonstone":p.matching,"sites":sites})
    # A saved battle checkpoint returns to its entrance; all kit and rolls stay.
    var j: RefCounted=Journey.new(definition,rules,0x4d4f4f4e)
    j.character.stats.strength=4;j.character.stats.constitution=5;j.character.health=60
    j.character.weapon="claymore";j.character.experience=11;j.inventory.gold=71
    j.world.active_lair="grassland_east";j.start_site_combat()
    var saved: Dictionary=j.checkpoint()
    var resumed: RefCounted=Journey.new(definition,rules,1)
    check(resumed.restore_checkpoint(saved),"current selected campaign remains compatible")
    check(resumed.character.snapshot()==j.character.snapshot() and resumed.inventory==j.inventory and resumed.lair_loot==j.lair_loot,"Continue keeps kit, XP, gold and every chest")
    var site: Dictionary=resumed.world.lair("grassland_east")
    check(resumed.encounter_options(site).concurrent==3,"Continue applies corrected beast cap at next entry")
    # Only settlement earns XP; obtaining options/spawning cannot do so.
    j.combat.simulation.spawn_remaining=0
    for a in j.combat.simulation.actors.values():
        if a.team==2:a.health=0
    check(j.prepare_loot(),"staged won encounter enters real loot settlement")
    var earned: int=j.character.experience
    j.prepare_loot();var loot_save: Dictionary=j.checkpoint()
    check(earned==12 and j.character.experience==earned,"new counts preserve one XP per victory")
    check(resumed.restore_checkpoint(loot_save) and resumed.available_loot()==j.available_loot() and resumed.character.experience==earned,"looting Continue preserves remaining rewards without another XP")
    check(j.checkpoint().schema==16 and j.checkpoint().content=="journey.campaign.v14","campaign format is unchanged")
    check(j.combat.simulation.snapshot().encounter_scaling_versions=={"classic:lair_scaling":{"api":1,"version":1}},"combat records scaling policy version")
    return {"checks":checks,"failures":failures,"profiles":profiles,"table_cases":data.cases.size(),"lair_cases":data.profiles.size()*24,
        "combat_schema":24,"combat_content":String(rules.content_id),"campaign_schema":16,"campaign_content":"journey.campaign.v14"}

func report(host: Node,path: String) -> void:
    var result: Dictionary=run_checks(path)
    print("ENEMY_SCALING_STATE=",JSON.stringify(result))
    if result.failures.is_empty():print("PASS:",result.checks," independent scaling, actual journey/spawn/refill and Continue/loot checks")
    else:print("FAIL:",JSON.stringify(result.failures.slice(0,8)))
    host.get_tree().quit(0 if result.failures.is_empty() else 1)
