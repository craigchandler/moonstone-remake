extends SceneTree
const Session=preload("res://scripts/session/campaign_session.gd")
const ReadModel=preload("res://scripts/session/campaign_projection.gd")
const Protocol=preload("res://scripts/session/campaign_protocol.gd")
const Replica=preload("res://scripts/session/campaign_journey_replica.gd")
var checks: int=0
var failures: Array[String]=[]
func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failures.append(label);push_error(label)
func command(s: RefCounted,seat: int,action: String,args: Dictionary={}) -> Dictionary:
    return s.command(seat,int(s.command_sequences.get(seat,0))+1,s.epoch,action,args)
func _initialize() -> void:
    for humans in range(1,5):
        var s: RefCounted=Session.new(12345,range(humans))
        check(s.journey.human_players==humans,"correct human count")
        var view: Dictionary=ReadModel.view(s,0)
        check(Protocol.valid_view(view),"bounded complete campaign view validates")
        check(not view.campaign.has("reward_seed") and not view.campaign.places.has("seed") and not view.campaign.rivals.has("seed"),"campaign RNG stays host-owned")
        check(view.campaign.lair_loot.values().all(func(row):return row.gold==0 and row.items.is_empty() and row.keys==0 and row.stones==0),"unseen pre-rolled treasure is not disclosed")
        var decoded: Dictionary=Protocol.decode(Protocol.encode({"type":"view","body":view}))
        check(Protocol.packet(decoded) and decoded.body==view,"live projection crosses primitive-only wire")
        var replica: RefCounted=Replica.new()
        check(replica.apply(view) and replica.party.players.size()==4,"classic client reads detached four-seat view")
        var own: RefCounted=Replica.new()
        check(own.apply(view,true) and own.inventory==s.journey.party.record(s.journey,0).inventory,"own inventory is independent of current-turn presentation")
        var before: Dictionary=s.safe_checkpoint()
        if humans>1:
            check(not command(s,1,"rest").ok and s.safe_checkpoint()==before,"inactive human cannot change the turn")
        check(command(s,0,"begin_turn").ok,"turn owner begins")
        var old_epoch: int=s.epoch
        var seq: int=int(s.command_sequences[0])+1
        check(s.command(0,seq,old_epoch,"rest").ok,"turn owner can rest")
        var settled: Dictionary=s.safe_checkpoint()
        check(not s.command(0,seq,old_epoch,"rest").ok and s.safe_checkpoint()==settled,"duplicate command never advances another turn")
        check(not s.command(0,seq+1,old_epoch,"begin_turn").ok and s.safe_checkpoint()==settled,"previous-phase command cannot cross turn boundary")
        check(not s.journey.validate_checkpoint(settled).is_empty(),"separate network safe checkpoint preserves existing schema")
    var s: RefCounted=Session.new(99,[0,1,2,3])
    for seat in range(4):
        check(command(s,seat,"begin_turn").ok and command(s,seat,"rest").ok,"all four human seats take their own turn")
    check(s.journey.day==2 and s.journey.party.active==0,"one full classic round keeps existing upkeep")
    command(s,0,"begin_turn")
    var start: Vector2i=s.journey.world.position
    check(s.input(0,1,s.epoch,Vector2i.RIGHT,"idle"),"owner held movement accepted")
    check(not s.input(1,1,s.epoch,Vector2i.RIGHT,"idle"),"spectator movement rejected")
    for tick in range(18):s.advance()
    check(s.journey.world.position.x>start.x,"host advances map travel")
    var stopped: Vector2i=s.journey.world.position
    for tick in range(20):s.advance()
    check(s.journey.world.position==stopped,"lost held input expires")
    var checkpoint: Dictionary=s.safe_checkpoint();var frozen_tick: int=s.tick
    s.set_paused(true)
    for tick in range(30):s.advance()
    check(s.tick==frozen_tick and s.safe_checkpoint()==checkpoint,"pause freezes clocks, AI, RNG and progress")
    check(not s.input(0,2,s.epoch,Vector2i.RIGHT,"swing"),"paused input rejected")
    s.set_paused(false)
    for tick in range(4):s.advance()
    check(s.journey.world.position==stopped,"resume does not replay held movement")
    s.journey.world.active_lair="grassland_east";s.journey.start_site_combat();s.sync_phase()
    var view: Dictionary=ReadModel.view(s,0)
    check(Protocol.valid_view(view) and Protocol.valid_combat(view.combat),"native monster battle is a validated detached combat view")
    var replica: RefCounted=Replica.new()
    check(replica.apply(view) and replica.combat.simulation.snapshot()==s.journey.combat.simulation.snapshot(),"client receives exact monster combat without stepping it")
    var live_before: Dictionary=s.journey.snapshot();var combat_before: Dictionary=s.journey.combat.simulation.snapshot()
    check(not s.journey.validate_checkpoint(s.safe_checkpoint()).is_empty(),"in-progress battle has compatible safe entrance checkpoint")
    check(s.journey.snapshot()==live_before and s.journey.combat.simulation.snapshot()==combat_before,"saving does not mutate live battle or loot phase")
    var bad: Dictionary=view.duplicate(true);bad.campaign.reward_seed=123
    check(not Protocol.valid_view(bad),"RNG-bearing checkpoint cannot masquerade as a public view")
    bad=view.duplicate(true);bad.combat.state.actors[1].erase("health")
    check(not Protocol.valid_view(bad),"malformed actor cannot reach classic renderer")
    check(not ReadModel.map_frame(s).quest.has("seed") and not view.campaign.quest.has("seed"),"quest RNG stays private in full and map updates")
    bad=ReadModel.map_frame(s);bad.world.dragon.erase("timer")
    check(not Protocol.valid_map(bad),"malformed live dragon frame is rejected")
    bad=view.duplicate(true);bad.campaign.character.stats.strength="wrong"
    check(not Protocol.valid_view(bad),"malformed character cannot reach classic panels")
    var count: int=s.feedback.size()
    for index in range(10):s.phase();ReadModel.view(s,0)
    check(s.feedback.size()==count,"phase/view reads never collect or duplicate hit feedback")
    for encounter in ["spear_lair","axe_lair","hammer_lair","balok_lair","rat_lair","mud_lair","beast_lair","troll_lair","dragon_fight","guardian_fight","black_knight_fight"]:
        s=Session.new(123,[0,1]);command(s,0,"begin_turn")
        s.journey.combat=preload("res://scripts/session/local_session.gd").new(s.journey.rules)
        s.journey.combat.start(&"competitive",StringName(encounter));s.sync_phase()
        for frame in range(60):s.advance()
        check(Protocol.valid_combat(ReadModel.combat(s)),"live creature state validates: "+encounter)
    s=Session.new(123,[0,1]);command(s,0,"begin_turn")
    s.journey.world.active_lair=s.journey.party.id_for(1);s.journey.start_site_combat();s.sync_phase()
    check(s.phase()=="battle_ready" and s.journey.combat.human_actors.values().size()==2,"human knight encounter requires both participants ready")
    var fight_tick: int=s.journey.combat.simulation.tick
    for index in range(10):s.advance()
    check(s.journey.combat.simulation.tick==fight_tick,"duel does not start before both humans agree")
    check(command(s,0,"battle_ready").ok and s.phase()=="battle_ready","one human cannot start a PvP fight")
    check(command(s,1,"battle_ready").ok and s.phase()=="battle","defending human can ready outside the map turn")
    var first_x: int=s.journey.combat.simulation.actors[1].x
    var second_id: int=s.journey.combat.human_actors.keys()[1]
    var second_x: int=s.journey.combat.simulation.actors[second_id].x
    check(s.input(0,1,s.epoch,Vector2i.LEFT,"idle") and s.input(1,1,s.epoch,Vector2i.RIGHT,"idle"),"both PvP humans submit only their own actor inputs")
    for index in range(5):s.advance()
    check(s.journey.combat.simulation.actors[1].x<first_x and s.journey.combat.simulation.actors[second_id].x>second_x,"host advances both human knights without AI control")
    s=Session.new(123,[0,1]);command(s,0,"begin_turn")
    s.journey.world.active_lair="grassland_east";s.journey.start_site_combat();s.sync_phase()
    var sim: RefCounted=s.journey.combat.simulation
    sim.spawn_remaining=0
    for actor in sim.actors.values():
        if actor.team==2:actor.health=0;actor.down_remaining=3
    s.advance()
    check(s.phase()=="result" and not command(s,0,"retreat").ok,"terminal death drawing cannot be skipped by a retreat command")
    for index in range(6):s.advance()
    check(s.phase()=="loot" and s.journey.battle_settled,"server settles monster victory before opening loot")
    var xp: int=s.journey.character.experience
    s.journey.lair_loot[s.journey.world.active_lair]={"gold":7,"items":{},"kind":1,"keys":0,"stones":0}
    var gold: int=s.journey.inventory.gold
    var pile_gold: int=s.journey.available_loot().gold
    var sequence: int=int(s.command_sequences[0])+1
    check(s.command(0,sequence,s.epoch,"take_loot",{"id":"gold"}).ok,"active human collects server-owned treasure")
    var collected: int=s.journey.inventory.gold
    check(collected==mini(150,gold+pile_gold) and not s.command(0,sequence,s.epoch,"take_loot",{"id":"gold"}).ok and s.journey.inventory.gold==collected,"duplicate loot command never duplicates gold")
    for index in range(5):s.advance()
    check(s.journey.character.experience==xp,"loot/result clock cannot award victory XP twice")
    check(not s.journey.validate_checkpoint(s.safe_checkpoint()).is_empty(),"settled loot saves retain existing campaign compatibility")
    var connection: RefCounted=preload("res://scripts/session/campaign_connection.gd").new();connection.profile_path="";connection.seat=0;connection.state="playing"
    s=Session.new(123,[0,1]);command(s,0,"begin_turn");s.tick=100
    connection.receive("view",ReadModel.view(s,0))
    var fast: Dictionary=ReadModel.map_frame(s);fast.tick=104;fast.world.position.x=60
    connection.receive("map",fast)
    s.tick=102;s.revision+=1;s.journey.character.weapon="broad_sword";s.journey.inventory.gold=0
    connection.receive("view",ReadModel.view(s,0))
    check(connection.replica.character.weapon=="broad_sword" and connection.own_inventory.inventory.gold==0,"reliable purchase is not lost behind a newer packet on another channel")
    check(connection.latest_tick==104 and connection.replica.world.position.x==60,"late transaction view retains freshest map movement")
    connection.close();connection=null
    print("CAMPAIGN_SESSION=",JSON.stringify({"checks":checks,"failures":failures}))
    if failures.is_empty():print("PASS: ",checks," campaign authority, privacy, seats, sequencing, pause, input and save checks")
    quit(0 if failures.is_empty() else 1)
