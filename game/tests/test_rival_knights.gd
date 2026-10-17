extends SceneTree
const Journey=preload("res://scripts/session/journey_session.gd")
const Rivals=preload("res://scripts/domain/rival_knights.gd")
const Store=preload("res://scripts/session/journey_store.gd")
var definition: Resource=preload("res://content/first_journey.tres")
var rules: Resource=preload("res://content/foundation_rules.tres")
var failures: int=0
var checks: int=0
func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failures+=1;push_error(label)
func fresh(seed: int=0x4d4f4f4e) -> RefCounted:return Journey.new(definition,rules,seed)
func drain(j: RefCounted) -> void:
    for tick in range(12000):
        if not j.pending_attack.is_empty():j.resolve_pending_attack(false)
        if j.combat!=null:j.return_to_map(false)
        if j.rivals.active==0:return
        j.rivals.advance(j)
    check(false,"rival slots terminate")
func dead_foe(j: RefCounted) -> void:
    j.combat.simulation.spawn_remaining=0
    for actor in j.combat.simulation.actors.values():
        if actor.team==2:actor.health=0
func _initialize() -> void:
    var j: RefCounted=fresh()
    var copy: RefCounted=fresh(32)
    check(j.rivals.records.size()==3 and j.world.sites().size()==29,"three separate rivals replace moving ghost")
    var untouched: Dictionary=j.checkpoint()
    check(not j.validate_checkpoint(untouched).is_empty(),"fresh production archive validates")
    var positions: Array=j.rivals.records.map(func(row: Dictionary) -> Vector2i:return row.position)
    for tick in range(200):j.travel(Vector2i.ZERO)
    check(j.rivals.records.map(func(row: Dictionary) -> Vector2i:return row.position)==positions,"rivals stationary throughout human turn")
    j.character.health=12
    check(j.rest() and j.day==1 and j.rivals.active==1 and not j.turn_pending,"human end hands over before calendar/recovery")
    check(not j.rest() and not j.begin_turn(),"no double turn/early acknowledge")
    var human: Vector2i=j.world.position
    for tick in range(47):j.rivals.advance(j)
    check(j.world.position==human and j.character.health==12 and j.rivals.records[0].position!=positions[0],"rival moves independently and spends its own budget")
    var half: Dictionary=j.checkpoint()
    check(copy.restore_checkpoint(JSON.parse_string(JSON.stringify(half))) and copy.checkpoint()==half,"mid-rival JSON Continue exact")
    drain(j);drain(copy)
    check(j.checkpoint()==copy.checkpoint(),"mid-slot continuation yields identical full round")
    check(j.day==2 and j.turn_pending and j.rivals.active==0 and j.character.health==15,"one completed round heals once and waits")
    check(j.lair_loot==untouched.lair_loot and j.awarded_lairs.is_empty(),"roaming AI cannot clear/reroll/loot creature lairs")
    for index in range(3):check(j.rivals.records[index].position!=positions[index],"each rival gets its own movement slot")
    var complete: Dictionary=j.checkpoint()
    check(copy.restore_checkpoint(complete) and copy.checkpoint()==complete,"new-round pause Continue exact")
    check(j.begin_turn() and not j.begin_turn() and j.day==2,"acknowledge does not repeat round/recovery")
    var cp: Dictionary=j.checkpoint()
    var old: Dictionary=cp.duplicate(true);old.schema=11;old.content="journey.campaign.v9";old.erase("rivals")
    old.lair_loot.erase("rival_knight_2");old.lair_loot.erase("rival_knight_3")
    var original_old: Dictionary=old.duplicate(true)
    check(copy.restore_checkpoint(old) and old==original_old and copy.day==old.day and copy.character.snapshot()==old.character,"previous save migration retains exact human kit/day without mutation")
    for id in old.lair_loot:check(copy.lair_loot[id]==old.lair_loot[id],"migration preserves existing chest: "+id)
    check(copy.rivals.records.size()==3 and copy.rivals.active==0,"migration adds separate rivals without spending turns")
    var stable: Dictionary=j.checkpoint()
    for value in [-1,4,1.5]:
        var bad: Dictionary=stable.duplicate(true);bad.rivals.active=value
        check(not copy.restore_checkpoint(bad),"invalid active slot rejected")
    for field in ["position","character","inventory"]:
        var bad: Dictionary=stable.duplicate(true);bad.rivals.records[1][field]="res://bad"
        var before: Dictionary=copy.checkpoint()
        check(not copy.restore_checkpoint(bad) and copy.checkpoint()==before,"malformed rival rejects atomically: "+field)
    var bad: Dictionary=stable.duplicate(true);bad.rivals.records[2].id=Rivals.IDS[0]
    check(not copy.restore_checkpoint(bad),"duplicate/reordered rival identity rejected")
    bad=stable.duplicate(true);bad.rivals.records[2].inventory.items={"untrusted":1}
    check(not copy.restore_checkpoint(bad),"unknown rival inventory rejected")
    # Profiles must use the specific rival, not a freshly generated 20HP actor.
    j=fresh();var row: Dictionary=j.rivals.records[1]
    row.character.stats.strength=3;row.character.armour="chainmail";row.character.health=47
    row.character.daggers=4;row.inventory.items={"ring_of_protection":1};row.character.weapon="claymore"
    j.world.position=row.position
    check(j.confirm_location(row.id),"player confirms overlapping rival icon")
    var foe: Dictionary=j.combat.simulation.actors[10]
    check(foe.health==47 and foe.maximum==50 and foe.daggers==4 and foe.damage_bonus==5,"duel uses distinct saved health, armour, ring, daggers, strength and sword")
    dead_foe(j);check(j.prepare_loot(),"rival victory opens loot")
    check(row.character.lives==4 and row.character.health==30 and row.inventory.items.is_empty(),"surviving loser loses one life and one ranked possession")
    check(j.available_loot().items=={"ring_of_protection":1} and j.character.experience==0,"duel reward comes from actual inventory, without lair XP")
    var won: Dictionary=j.checkpoint()
    check(copy.restore_checkpoint(won) and copy.checkpoint()==won,"partially settled rival loot Continue does not settle twice")
    check(copy.take_loot("ring_of_protection") and not copy.take_loot("ring_of_protection"),"rival item collected once")
    check(copy.character.health==40 and copy.character.maximum(copy.inventory.items)==40,"taken passive ring applies to human")
    j.return_to_map(false);drain(j);j.begin_turn();j.world.position=row.position
    check(j.confirm_location(row.id) and j.loot_open and row.character.lives==4,"unclaimed duel loot reopens without another lost life")
    j.collect_all_loot();j.return_to_map(false);drain(j);j.begin_turn()
    # Incoming attacks keep the existing explicit Protection decision for each identity.
    for index in range(3):
        j=fresh();row=j.rivals.records[index];j.world.position=row.position
        j.inventory.items.scroll_of_protection=1
        check(j.begin_rival_encounter(row.id,true) and j.pending_attack==row.id and j.attack_notice and j.combat==null,"incoming protection warning: "+row.id)
        var pending: Dictionary=j.checkpoint()
        check(copy.restore_checkpoint(pending) and copy.checkpoint()==pending,"pending rival choice Continue: "+row.id)
        check(j.resolve_pending_attack(true) and j.combat==null and not j.inventory.items.has("scroll_of_protection") and row.character.lives==5,"protection spends once without HP/loot/XP: "+row.id)
        j=fresh();row=j.rivals.records[index];j.world.position=row.position;j.inventory.items.scroll_of_protection=1
        j.begin_rival_encounter(row.id,true)
        check(j.resolve_pending_attack(false) and j.combat!=null and j.inventory.items.scroll_of_protection==1,"closing pack starts correct duel without consuming scroll")
    # Human loss transfers only the first owned slot and grants rival XP once.
    j=fresh();row=j.rivals.records[0];j.world.position=row.position
    j.inventory.items={"ring_of_protection":2,"healing_potion":1};j.character.health=60
    j.begin_rival_encounter(row.id,true);j.combat.simulation.actors[1].health=0
    j.settle_battle();j.settle_battle()
    check(j.character.lives==4 and j.inventory.items.ring_of_protection==1 and row.inventory.items.ring_of_protection==1 and row.character.experience==1,"one human life/possession and one rival XP settle once")
    check(not j.validate_checkpoint(j.checkpoint()).is_empty(),"settled defeat checkpoint validates")
    # Final defeat offers all objects; capped purse pickup preserves remainder.
    j=fresh();row=j.rivals.records[2];row.character.lives=1;row.inventory.gold=149
    row.inventory.items={"healing_potion":2,"gem_of_seeing":1};row.keys=4
    j.world.position=row.position;j.confirm_location(row.id);dead_foe(j);j.prepare_loot()
    check(row.character.lives==0 and j.world.cleared.has(row.id) and row.inventory.items.is_empty() and row.keys==0,"final defeat marks correct fallen record and removes its possessions")
    check(j.available_loot().gold==149 and j.available_loot().keys==4 and j.available_loot().items=={"healing_potion":2,"gem_of_seeing":1},"final rival chest holds actual gold, flag and all objects")
    j.inventory.gold=149;j.take_loot("gold")
    check(j.inventory.gold==150 and j.available_loot().gold==148,"full purse retains unclaimed duel gold")
    check(copy.restore_checkpoint(j.checkpoint()),"final duel loot with large gold/key count validates")
    j.take_loot("key_wastes");check(j.owned_keys==4 and j.available_loot().keys==0,"rival key pickup transfers ownership once")
    # Calendar advances once after all slots; gifts are on four-round cadence.
    j=fresh()
    for round_index in range(8):
        check(j.rest(),"start next full round");drain(j)
        check(j.day==round_index+2 and j.calendar().lunar_counter==(round_index+1)/4,"one lunar tick per completed round")
        check(j.begin_turn(),"acknowledge round")
    check(j.rivals.records.any(func(r: Dictionary) -> bool:return r.character.stats!={"strength":1,"constitution":1,"endurance":1} or r.inventory.gold!=10 or not r.inventory.items.is_empty()),"living rivals gain independent periodic gifts/shopping")
    # A held quest object may move to a rival and be recovered without duplicating.
    j=fresh();j.awarded_lairs.valley_guardian=true;j.world.cleared.valley_guardian=true
    j.quest.valley_stone=1;j.quest.stones=1;row=j.rivals.records[0];j.world.position=row.position
    j.begin_rival_encounter(row.id,true);j.combat.simulation.actors[1].health=0;j.return_to_map(false)
    check(j.quest.stones==0 and row.stones==1 and copy.restore_checkpoint(j.checkpoint()),"stolen earned moonstone remains valid and recoverable")
    j.world.position=row.position;j.confirm_location(row.id);dead_foe(j);j.prepare_loot()
    check(j.available_loot().stones==1 and j.take_loot(j.quest_rules.stone_ids[0]) and j.quest.stones==1 and row.stones==0,"moonstone returns through original loot icons")
    # Real disk continuation in the middle of a rival movement slot.
    j=fresh();j.rest()
    for tick in range(39):j.rivals.advance(j)
    var store: RefCounted=Store.new("user://unit-rivals.json",j.validate_checkpoint)
    check(store.save_checkpoint(j.checkpoint()) and copy.restore_checkpoint(store.load_checkpoint()) and copy.checkpoint()==j.checkpoint(),"mid-rival atomic disk roundtrip")
    if failures==0:print("PASS: ",checks," rival checks; three independent records/turns, saved movement/calendar, source AI roaming/shopping/gifts, distinct duel profiles, life and possession settlement, protection, quest recovery and migration")
    quit(1 if failures else 0)
