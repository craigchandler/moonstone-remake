extends SceneTree
const Journey=preload("res://scripts/session/journey_session.gd")
const Places=preload("res://scripts/domain/town_locations.gd")
const Store=preload("res://scripts/session/journey_store.gd")
const Art=preload("res://assets/classic/town_locations/art.tres")
var definition: Resource=preload("res://content/first_journey.tres")
var rules: Resource=preload("res://content/foundation_rules.tres")
var failures: int=0
var checks: int=0
func fresh() -> RefCounted:return Journey.new(definition,rules,0x4d4f4f4e)
func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failures+=1;push_error(label)
func enter(j: RefCounted,town: String,service: String="") -> void:
    j.world.position=j.town(town).position
    check(j.enter_town(town),"enter "+town)
    if not service.is_empty():check(j.open_service(service),"open "+service)
func outcome_seed(kind: String,recency: int=0) -> int:
    for seed in range(2,10000):
        var j: RefCounted=fresh();j.places.seed=(seed*0x9e3779b9)&0xffffffff;j.places.recency=recency;j.places.visit=Places.visit("wizard")
        Places.wizard_roll(j)
        if j.places.visit.result==kind:return (seed*0x9e3779b9)&0xffffffff
    return -1
func _initialize() -> void:
    var j: RefCounted=fresh();var copy: RefCounted=fresh()
    check(not j.validate_checkpoint(j.checkpoint()).is_empty(),"new town state validates")
    check(j.places.market.items.values().reduce(func(a: int,b: int) -> int:return a+b,0)==8 and j.places.market.items.get("talisman_of_the_wyrm",0)>=2,"six initial magical stock rolls plus two talismans")
    check(Art.data.dice_rows==Places.DICE and Art.data.prices.slice(0,10)==Places.PRICES,"native payout/price data match imported source rows")
    check(Art.streams.size()==17 and Art.data.tower.size()==3 and Art.data.gift_a.size()==22 and Art.data.dice_roll_ticks==69,"all wizard/dice poses and sound cues recovered")
    # Source version13 migrates without altering any earlier progress/chest/clock/RNG.
    var cp: Dictionary=j.checkpoint();var old: Dictionary=cp.duplicate(true);old.schema=13;old.content="journey.campaign.v11";old.erase("places")
    check(copy.restore_checkpoint(old) and copy.checkpoint()==cp,"previous campaign migration adds independent town state only")
    for kind in ["item","stat","gold","frog"]:
        j=fresh();enter(j,"wizard");j.places.seed=outcome_seed(kind)
        var before: Dictionary=j.checkpoint()
        check(j.places.visit.phase=="greeting" and j.character.snapshot()==before.character,"tower greeting does not roll gift")
        check(Places.advance_wizard(j) and j.places.visit.result==kind and j.places.visit.phase=="gift","original wizard outcome: "+kind)
        var gift: Dictionary=j.checkpoint()
        check(copy.restore_checkpoint(JSON.parse_string(JSON.stringify(gift))) and copy.checkpoint()==gift,"Continue resumes applied gift: "+kind)
        check(Places.advance_wizard(copy) and copy.character.snapshot()==j.character.snapshot() and copy.inventory==j.inventory,"gift acknowledgement cannot award twice: "+kind)
        check(Places.advance_wizard(copy) and copy.places.recency==70 and copy.places.visit.phase=="sheet","omen leads to character sheet and recency70")
        if kind=="frog":check(copy.places.frog_days==3,"wizard toad lasts three source days")
        if kind=="stat":check(j.character.stats.values().reduce(func(a: int,b: int) -> int:return a+b,0)==4 and j.character.experience==0,"stat gift does not invent or spend XP")
        check(copy.leave_town() and copy.rivals.active==1 and copy.places.visit.is_empty(),"tower exit spends one turn only: "+kind)
        check(not copy.leave_town(),"cannot leave tower twice")
    # Healer charges the full accepted donation; cancellation is a preview.
    j=fresh();j.inventory.gold=100;j.character.health=3;j.character.lives=3;j.character.life_loss=7
    enter(j,"highwood","healer");j.places.visit.phase="donation"
    var before: Dictionary=j.checkpoint()
    check(not Places.donate(j,101) and not Places.donate(j,-1) and j.checkpoint()==before,"unaffordable/negative donation is atomic")
    check(Places.donate(j,25) and j.inventory.gold==75 and j.character.health==20 and j.character.lives==4 and j.character.life_loss==0,"25gp donation heals wounds and one life and curse")
    before=j.checkpoint();check(not Places.donate(j,25) and j.checkpoint()==before,"reply cannot charge donation again")
    j=fresh();j.inventory.gold=30;j.character.lives=4;enter(j,"waterdeep","healer");j.places.visit.phase="donation"
    check(Places.donate(j,14) and j.character.lives==4 and j.inventory.gold==16,"10..14gp offer cannot underflow life cost")
    j=fresh();enter(j,"highwood","healer");j.places.visit.phase="donation"
    check(Places.donate(j,0) and j.inventory.gold==10 and j.places.visit.result=="none","zero donation has no benefit or charge")
    # Mythral's original donation bands can raise or lower a selected stat.
    var found: Dictionary={}
    for seed in range(2,300):
        j=fresh();j.inventory.gold=60;j.character.stats={"strength":3,"constitution":3,"endurance":3};j.character.health=40
        enter_quiet(j,"waterdeep","mystic");j.places.seed=(seed*0x9e3779b9)&0xffffffff;j.places.visit.phase="donation"
        Places.donate(j,10);found[j.places.visit.result]=true
        check(j.inventory.gold==50 and not j.validate_checkpoint(j.checkpoint()).is_empty(),"paid reading has valid bounded kit/health")
        if found.has("raise") and found.has("lower"):break
    check(found.has("raise") and found.has("lower"),"both raised and lowered Mythral outcomes occur")
    j=fresh();j.inventory.gold=60;j.character.stats={"strength":5,"constitution":5,"endurance":5};j.character.health=60
    enter(j,"waterdeep","mystic");j.places.visit.phase="donation"
    check(Places.donate(j,50) and j.character.stats=={"strength":5,"constitution":5,"endurance":5},"all stats max avoids original stale-byte corruption")
    # All216 ordered throws match the exact sorted winning rows; bet commits once.
    var paid: Dictionary={}
    for seed in range(2,500):
        j=fresh();j.inventory.gold=20;enter_quiet(j,"highwood","tavern");j.places.seed=(seed*0x9e3779b9)&0xffffffff
        check(Places.wager(j,3),"valid wager accepted")
        var v: Dictionary=j.places.visit;var sorted: Array=v.dice.duplicate();sorted.sort();var mult: int=0
        for row in Places.DICE:
            if sorted==row.slice(0,3):mult=row[3];break
        check(j.inventory.gold==17+3*mult and v.payout==3*mult and v.phase=="rolling","bet is settled to original payout before reveal")
        before=j.checkpoint();check(not Places.wager(j,3) and j.checkpoint()==before,"rolling cannot debit or reroll again")
        check(copy.restore_checkpoint(before) and copy.checkpoint()==before,"mid-roll Continue keeps paid result and seed")
        paid[v.payout>0]=true
        if paid.size()==2:break
    check(paid.size()==2,"winning and losing wagers covered")
    j=fresh();enter(j,"highwood","tavern");before=j.checkpoint()
    for stake in [-1,0,6,100]:check(not Places.wager(j,stake) and j.checkpoint()==before,"invalid stake kept: "+str(stake))
    # Real market ownership, passives, sell-back and quest recovery.
    j=fresh();j.inventory.gold=100;j.places.market.items={"ring_of_protection":1,"sword_of_sharpness":1}
    enter(j,"highwood","temple")
    check(Places.trade(j,"ring_of_protection",true) and j.inventory.gold==60 and j.character.health==40 and j.places.market.items.get("ring_of_protection",0)==0,"buy ring changes actual stock, purse and passive HP")
    check(Places.trade(j,"ring_of_protection",false) and j.inventory.gold==80 and j.character.health==20 and j.places.market.items.ring_of_protection==1,"sell ring pays half and removes its benefit")
    before=j.checkpoint();check(not Places.trade(j,"unknown",true) and not Places.trade(j,"healing_potion",true) and j.checkpoint()==before,"unknown or sold-out stock is atomic")
    j.owned_keys=1;check(Places.trade(j,"key_moors",false) and j.owned_keys==0 and j.places.market.keys==1,"regional key can be sold without copied ownership")
    check(Places.trade(j,"key_moors",true) and j.owned_keys==1 and j.places.market.keys==0,"same regional key can be recovered")
    j.owned_keys=0;j.quest.valley_stone=2;j.quest.stones=2;j.awarded_lairs.valley_guardian=true;j.world.cleared.valley_guardian=true
    check(Places.trade(j,j.quest_rules.stone_ids[1],false) and j.quest.stones==0 and j.places.market.stones==2,"earned moonstone can enter actual stock")
    check(not j.validate_checkpoint(j.checkpoint()).is_empty() and copy.restore_checkpoint(j.checkpoint()),"quest remains valid with earned stone at market")
    check(Places.trade(copy,copy.quest_rules.stone_ids[1],true) and copy.quest.stones==2 and copy.places.market.stones==0,"Continue recovers the same unique moonstone")
    cp=copy.checkpoint()
    for field in ["seed","frog_days","recency","market","visit"]:
        var bad: Dictionary=cp.duplicate(true);bad.places[field]="invalid"
        check(not copy.restore_checkpoint(bad) and copy.checkpoint()==cp,"malformed place state rejects atomically: "+field)
    var bad: Dictionary=cp.duplicate(true);bad.places.market.stones=2
    check(not copy.restore_checkpoint(bad),"duplicate market/held moonstone rejected")
    var store: RefCounted=Store.new("user://town-locations-test.json",copy.validate_checkpoint)
    check(store.save_checkpoint(cp) and j.restore_checkpoint(store.load_checkpoint()) and j.checkpoint()==cp,"checksummed disk save retains traded stock/quest and visit state")
    # Daily frog decrement and skipped human turns do not skip the other knights.
    j=fresh();j.places.frog_days=3;j.end_turn("rest")
    drain(j);check(j.day==2 and j.places.frog_days==2 and j.turn_pending,"first frog day expires on normal full-round upkeep")
    check(j.begin_turn() and j.rivals.active==1 and not j.turn_pending,"frogged human turn passes to the rivals")
    drain(j);j.begin_turn();drain(j)
    check(j.day==4 and j.places.frog_days==0 and j.begin_turn() and j.rivals.active==0,"normal human turn resumes after three days")
    # Frogged knights cannot be put into a player-controlled duel by pursuing AI.
    for mode in [&"competitive",&"cooperative"]:
        j=fresh();j.mode=mode;j.places.frog_days=2;var rival: Dictionary=j.rivals.records[0]
        rival.position=j.world.position;j.rivals.active=1;j.turn_reason="rest"
        check(j.begin_rival_encounter(rival.id,true) and j.combat==null and j.character.lives==4 and rival.character.experience==1,"cursed token loses incoming duel without an arena: "+str(mode))
        check(not j.validate_checkpoint(j.checkpoint()).is_empty(),"frog encounter saves valid turn state: "+str(mode))
    j=fresh();enter_quiet(j,"wizard","temple");j.places.visit.phase="sheet";j.service=""
    check(copy.restore_checkpoint(j.checkpoint()) and copy.places.visit.phase=="sheet","Math personal pack saves with no active stat service")
    j.inventory.items.scroll_of_the_hawk=1
    check(j.use_item("scroll_of_the_hawk",Vector2i(100,100)) and j.town_id=="" and j.places.visit.is_empty() and j.rivals.active==1 and not j.inventory.items.has("scroll_of_the_hawk"),"Hawk leaving a town/tower clears visit and spends its one turn")
    check(not j.validate_checkpoint(j.checkpoint()).is_empty(),"departed Hawk visit saves a valid rival turn")
    if failures==0:print("PASS: ",checks," Math outcomes, recency/frog turns, donations/readings, dice payout/Continue, trading/passives/quest ownership and archive checks")
    quit(1 if failures else 0)
func enter_quiet(j: RefCounted,town: String,service: String) -> void:
    j.world.position=j.town(town).position;j.enter_town(town);j.open_service(service)
func drain(j: RefCounted) -> void:
    for tick in range(15000):
        if not j.pending_attack.is_empty():j.resolve_pending_attack(false)
        if j.combat!=null:j.combat.simulation.actors[1].health=0;j.return_to_map(false)
        if j.rivals.active==0:return
        j.advance_rival_turn()
    check(false,"rival round finishes")
