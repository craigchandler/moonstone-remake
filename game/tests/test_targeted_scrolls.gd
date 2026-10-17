extends SceneTree
const Journey=preload("res://scripts/session/journey_session.gd")
const Scrolls=preload("res://scripts/domain/targeted_scrolls.gd")
const Store=preload("res://scripts/session/journey_store.gd")
var definition: Resource=preload("res://content/first_journey.tres")
var rules: Resource=preload("res://content/foundation_rules.tres")
var failures: int=0
var checks: int=0
func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failures+=1;push_error(label)
func fresh() -> RefCounted:return Journey.new(definition,rules,0x4d4f4f4e)
func _initialize() -> void:
    var j: RefCounted=fresh()
    var row: Dictionary=j.rivals.records[1]
    row.inventory.items={"ring_of_protection":1,"healing_potion":2,"sword_of_sharpness":1}
    row.character.health=40
    j.inventory.items.scroll_of_acquisition=4
    var before: Dictionary=j.checkpoint()
    for invalid in [null,"rival_knight_2",{}, {"rival":row.id,"item":"healing_potion","extra":0},{"rival":0,"item":"healing_potion"},{"rival":row.id,"item":0},{"rival":"missing","item":"healing_potion"},{"rival":row.id,"item":"claymore"}]:
        check(not j.use_item("scroll_of_acquisition",invalid) and j.checkpoint()==before,"invalid Acquisition is atomic: "+str(invalid))
    check(j.use_item("scroll_of_acquisition",{"rival":row.id,"item":"healing_potion"}),"select actual second rival's potion")
    check(j.inventory.items.healing_potion==1 and row.inventory.items.healing_potion==1 and j.rivals.records[0].inventory.items.is_empty(),"transfer one count from correct record")
    check(j.use_item("scroll_of_acquisition",{"rival":row.id,"item":"ring_of_protection"}) and j.character.health==40 and row.character.health==20,"ring immediately changes both maximum health values")
    check(j.use_item("scroll_of_acquisition",{"rival":row.id,"item":"sword_of_sharpness"}) and j.character.effective_weapon(j.inventory.items)=="sword_of_sharpness" and j.rivals.knight(row).effective_weapon(row.inventory.items)=="long_sword","passive sword follows ownership")
    check(j.day==before.day and j.character.experience==0 and j.lair_loot==before.lair_loot and j.rivals.random.state==before.rivals.seed,"scroll has no XP, round, chest or RNG side effect")
    j.inventory.items.healing_potion=255;before=j.checkpoint()
    check(not j.use_item("scroll_of_acquisition",{"rival":row.id,"item":"healing_potion"}) and j.checkpoint()==before,"full object count keeps both packs and scroll")
    row.character.lives=0;row.character.health=0;before=j.checkpoint()
    check(Scrolls.targets(j).size()==2 and not j.use_item("scroll_of_acquisition",{"rival":row.id,"item":"healing_potion"}) and j.checkpoint()==before,"fallen target cannot be acquired from")
    j=fresh();row=j.rivals.records[2];row.keys=5;j.inventory.items.scroll_of_acquisition=3
    check(j.use_item("scroll_of_acquisition",{"rival":row.id,"item":"key_moors"}) and j.owned_keys==1 and row.keys==4,"acquire one selected regional key")
    # A genuinely earned stone may be with another knight and must remain unique.
    j.quest.valley_stone=2;j.awarded_lairs.valley_guardian=true;j.world.cleared.valley_guardian=true
    row.stones=2;j.owned_keys=0;row.keys=0
    check(j.use_item("scroll_of_acquisition",{"rival":row.id,"item":j.quest_rules.stone_ids[1]}) and j.quest.stones==2 and row.stones==0,"acquire earned moonstone without new reward")
    check(not j.validate_checkpoint(j.checkpoint()).is_empty(),"unique acquired stone archive validates")
    row.inventory.items.scroll_of_acquisition=1
    check(j.use_item("scroll_of_acquisition",{"rival":row.id,"item":"scroll_of_acquisition"}) and j.inventory.items.scroll_of_acquisition==1 and row.inventory.items.is_empty(),"taking another Acquisition still spends exactly one scroll")
    # Wyrm cannot skip first-appearance gate or resurrect the Dragon.
    j=fresh();row=j.rivals.records[1];j.inventory.items.scroll_of_the_wyrm=2;before=j.checkpoint()
    check(not j.use_item("scroll_of_the_wyrm",row.id) and j.checkpoint()==before,"early Wyrm kept before round gate")
    j.day=9
    check(j.use_item("scroll_of_the_wyrm",row.id) and j.dragon_order==2 and j.inventory.items.scroll_of_the_wyrm==1,"Wyrm queues chosen living rival")
    before=j.checkpoint()
    check(not j.use_item("scroll_of_the_wyrm",row.id) and j.checkpoint()==before,"same target does not spend another Wyrm")
    var copy: RefCounted=fresh()
    check(copy.restore_checkpoint(JSON.parse_string(JSON.stringify(before))) and copy.checkpoint()==before,"queued pursuit survives JSON Continue")
    j.dragon_aim();j.world.dragon.advance(8,row.position,true)
    j.world.dragon.position=Vector2i(200,70);j.world.dragon.phase=5
    check(j.use_item("scroll_of_the_wyrm",j.rivals.records[0].id) and j.world.dragon.target==1 and j.world.dragon.position==Vector2i(200,70) and j.world.dragon.phase==5,"active retarget preserves flight pose and position")
    check(copy.restore_checkpoint(j.checkpoint()) and copy.checkpoint()==j.checkpoint(),"active retarget Continue exact")
    j.world.dragon.reset();check(j.dragon_aim()==j.rivals.records[0].position and j.world.dragon.target==1,"arena/turn reset retains Wyrm order")
    j.inventory.items.scroll_of_the_wyrm=1;j.world.cleared.roaming_dragon=true;before=j.checkpoint()
    check(not j.use_item("scroll_of_the_wyrm",row.id) and j.checkpoint()==before,"defeated Dragon cannot be summoned")
    # Natural target choice includes all living slots; no wrong-turn collision.
    var seen: Dictionary={}
    j=fresh();j.day=9
    for attempt in range(100):
        j.world.dragon.reset();j.dragon_aim();seen[j.world.dragon.target]=true
    check(seen.size()==4,"natural Dragon target includes human and all three rivals")
    j.rivals.records[0].character.lives=0;j.rivals.records[0].character.health=0
    for attempt in range(40):
        j.world.dragon.reset();j.dragon_aim();check(j.world.dragon.target!=1,"natural Dragon excludes fallen knight")
    j.world.dragon.active=true;j.world.dragon.target=2;j.world.dragon.position=j.rivals.records[1].position+Vector2i(10,0)
    check(not j.world.dragon.touches(j.rivals.records[1].position,0) and j.world.dragon.touches(j.rivals.records[1].position,2),"only target's turn can trigger Dragon contact")
    # Stage contact then use actual rival scheduler/settlement.
    j=fresh();j.day=9;j.lair_loot.roaming_dragon={"gold":0,"items":{},"kind":4,"keys":0,"stones":0};row=j.rivals.records[1];row.inventory.gold=41;row.inventory.items={"ring_of_protection":1,"healing_potion":1};row.character.health=40
    j.dragon_order=2;j.rest();j.rivals.active=2;j.rivals.target="player";j.rivals.goal=j.world.position;j.rivals.budget=96;j.rivals.walk.assign([100,10,-1,1,100,0])
    j.world.dragon.active=true;j.world.dragon.target=2;j.world.dragon.position=row.position+Vector2i(10,0)
    j.advance_rival_turn()
    check(row.character.lives==4 and row.inventory.gold==21 and row.character.health==20,"AI Dragon contact loses one life, half gold, clamps ring HP")
    check(j.lair_loot.roaming_dragon.gold==20 and j.lair_loot.roaming_dragon.items=={"ring_of_protection":1} and j.combat==null and j.dragon_order==-1,"Dragon hoard receives actual possession without human fight")
    check(j.rivals.active==3 and not j.world.dragon.active and not j.validate_checkpoint(j.checkpoint()).is_empty(),"contact finishes one rival slot and saves valid state")
    before=j.checkpoint();j.advance_rival_turn();check(row.character.lives==4 and j.lair_loot==before.lair_loot,"next tick does not settle caught rival twice")
    # Hoard can retain a stolen earned stone; actual victory recovers it once.
    j=fresh();j.day=9;row=j.rivals.records[0]
    j.quest.valley_stone=4;j.awarded_lairs.valley_guardian=true;j.world.cleared.valley_guardian=true;row.stones=4
    j.dragon_takes(row.inventory,row,false)
    check(row.stones==0 and j.lair_loot.roaming_dragon.stones==4 and not j.validate_checkpoint(j.checkpoint()).is_empty(),"stolen earned stone moves to valid Dragon hoard")
    j.world.active_lair="roaming_dragon";j.start_site_combat()
    for actor in j.combat.simulation.actors.values():
        if actor.team==2:actor.health=0;actor.down_remaining=0
    check(j.prepare_loot() and j.take_loot(j.quest_rules.stone_ids[2]) and j.quest.stones==4,"actual Dragon victory recovers stolen stone")
    check(not j.take_loot(j.quest_rules.stone_ids[2]) and not j.validate_checkpoint(j.checkpoint()).is_empty(),"no duplicate stone on repeated take/Continue")
    # Final defeat transfers every object, with caps preserving overflow.
    j=fresh();j.lair_loot.roaming_dragon={"gold":0,"items":{},"kind":4,"keys":0,"stones":0};row=j.rivals.records[0];row.inventory.gold=40;row.inventory.items={"healing_potion":2,"ring_of_protection":1};row.keys=3
    j.dragon_takes(row.inventory,row,true)
    check(j.lair_loot.roaming_dragon.items=={"healing_potion":2,"ring_of_protection":1} and row.inventory.items.is_empty() and row.keys==0 and j.lair_loot.roaming_dragon.keys==3,"final defeat transfers all objects and flags")
    j.lair_loot.roaming_dragon.gold=149;row.inventory.gold=40;j.dragon_takes(row.inventory,row,false)
    check(j.lair_loot.roaming_dragon.gold==150 and row.inventory.gold==39,"gold cap retains overflow without loss/wrap")
    j=fresh();before=j.checkpoint()
    var old: Dictionary=before.duplicate(true);old.schema=12;old.content="journey.campaign.v10";old.erase("dragon_order");old.lair_loot.roaming_dragon.erase("stones")
    check(copy.restore_checkpoint(old) and copy.checkpoint()==before,"campaign12 migrates without changing prior kit, chests, RNG or turn")
    for corrupt in [0,4,1.5,"2",null]:
        var bad: Dictionary=before.duplicate(true);bad.dragon_order=corrupt
        var stable: Dictionary=copy.checkpoint()
        check(not copy.restore_checkpoint(bad) and copy.checkpoint()==stable,"malformed target rejects atomically: "+str(corrupt))
    var bad: Dictionary=before.duplicate(true);bad.dragon_order=2
    check(not copy.restore_checkpoint(bad),"save cannot queue Wyrm before gate")
    bad=before.duplicate(true);bad.world.cleared="bad"
    check(not copy.restore_checkpoint(bad),"malformed clear state rejected safely")
    bad=before.duplicate(true);bad.day=9;bad.dragon_order=2;bad.rivals.records[1].character.lives=0;bad.rivals.records[1].character.health=0
    check(not copy.restore_checkpoint(bad),"save cannot target fallen rival")
    j=fresh();j.day=9;j.inventory.items.scroll_of_the_wyrm=1;j.use_item("scroll_of_the_wyrm",j.rivals.records[2].id)
    var store: RefCounted=Store.new("user://targeted-scrolls-test.json",j.validate_checkpoint)
    check(store.save_checkpoint(j.checkpoint()) and copy.restore_checkpoint(store.load_checkpoint()) and copy.checkpoint()==j.checkpoint(),"checksummed disk Continue retains chosen rival and spent scroll")
    # Active target mismatch and cleared/dead orders cannot enter live state.
    j=fresh();j.day=9;j.inventory.items.scroll_of_the_wyrm=1;j.use_item("scroll_of_the_wyrm",j.rivals.records[1].id)
    j.dragon_aim();j.world.dragon.advance(8,j.rivals.records[1].position,true)
    bad=j.checkpoint();bad.world.dragon.target=1
    check(not copy.restore_checkpoint(bad),"forced active flight cannot disagree with saved target")
    bad=j.checkpoint();bad.world.cleared.roaming_dragon=true
    check(not copy.restore_checkpoint(bad),"cleared Dragon cannot retain Wyrm order")
    row=j.rivals.records[1];row.character.lives=0;row.character.health=0
    j.discard_dead_dragon_target()
    check(j.dragon_order==-1 and not j.world.dragon.active,"fallen selected rival clears pending order and flight")
    # A controlled Dragon loss transfers from the actual human once.
    j=fresh();j.day=9;j.inventory.gold=41;j.inventory.items={"ring_of_protection":1,"healing_potion":2};j.character.health=40
    j.lair_loot.roaming_dragon={"gold":0,"items":{},"kind":4,"keys":0,"stones":0}
    j.world.active_lair="roaming_dragon";j.start_site_combat();j.combat.simulation.actors[1].health=0
    j.settle_battle()
    check(j.character.lives==4 and j.character.health==20 and j.inventory.gold==21 and j.inventory.items=={"healing_potion":2},"controlled Dragon loss costs life, half gold, one priority object")
    before=j.snapshot();j.settle_battle()
    check(j.snapshot()==before and j.lair_loot.roaming_dragon.items=={"ring_of_protection":1},"controlled Dragon loss settles only once")
    j=fresh();j.day=9;row=j.rivals.records[1];row.character.lives=1;row.inventory.items.healing_potion=2
    j.lair_loot.roaming_dragon={"gold":0,"items":{},"kind":4,"keys":0,"stones":0}
    j.rest();j.rivals.active=2;j.rivals.target="player";j.rivals.goal=j.world.position;j.rivals.budget=96;j.rivals.walk.assign([100,10,-1,1,100,0])
    j.world.dragon.active=true;j.world.dragon.target=2;j.world.dragon.position=row.position+Vector2i(10,0)
    j.advance_rival_turn()
    check(row.character.lives==0 and row.character.health==0 and j.world.cleared.has(row.id) and row.inventory.items.is_empty(),"final AI Dragon contact leaves fallen icon and transfers all objects")
    check(not j.validate_checkpoint(j.checkpoint()).is_empty(),"final Dragon casualty saves valid dead rival/hoard")
    if failures==0:print("PASS: ",checks," targeted scroll/Dragon ownership, gate, persistence and archive checks")
    quit(1 if failures else 0)
