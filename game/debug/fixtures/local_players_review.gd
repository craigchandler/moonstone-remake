extends RefCounted
const Journey=preload("res://scripts/session/journey_session.gd")
const Party=preload("res://scripts/session/local_party.gd")
const Definition=preload("res://content/first_journey.tres")
const Rules=preload("res://content/foundation_rules.tres")
const Runtime=preload("res://scripts/session/runtime_mode.gd")
var checks: int=0
var failures: Array[String]=[]
var traces: Dictionary={}
var controls: Node
var sample_checkpoint: Dictionary={}

func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failures.append(label)

func fresh(roster: Array=[]) -> RefCounted:
    var j: RefCounted=Journey.new(Definition,Rules,12345)
    check(j.start_local_party(Party.defaults() if roster.is_empty() else roster,12345),"valid local game starts")
    return j

func roundtrip(j: RefCounted,label: String) -> void:
    var data: Dictionary=j.checkpoint()
    var copy: RefCounted=Journey.new(Definition,Rules,3)
    check(not j.validate_checkpoint(data).is_empty(),label+": checkpoint validates")
    var restored: bool=copy.restore_checkpoint(JSON.parse_string(JSON.stringify(data)))
    check(restored,label+": JSON Continue restores")
    if restored:check(copy.checkpoint()==data,label+": exact campaign and roster roundtrip")

func duel(j: RefCounted) -> int:
    j.begin_turn()
    var row: Dictionary=j.rivals.find(j.party.id_for(1))
    row.position=j.world.position+Vector2i(2,0)
    check(j.begin_rival_encounter(row.id,false),"human challenger enters duel")
    var opponent: int=0
    for id in j.combat.human_actors:
        if id!=1:opponent=id
    check(opponent!=0,"human defender receives an actor")
    roundtrip(j,"live duel entrance checkpoint")
    return opponent

func key(code: int,pressed: bool=true) -> void:
    var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=pressed
    Input.parse_input_event(event);Input.flush_buffered_events()

func press(code: int) -> void:key(code);key(code,false)

func button(device: int,code: int,pressed: bool=true) -> void:
    var event:=InputEventJoypadButton.new();event.device=device;event.button_index=code;event.pressed=pressed
    Input.parse_input_event(event);Input.flush_buffered_events()

func tap(device: int,code: int) -> void:button(device,code);button(device,code,false)

func click(parent: Node,point: Vector2) -> void:
    var event:=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true
    parent.get_tree().root.push_input(event,true)
    event=event.duplicate();event.pressed=false;parent.get_tree().root.push_input(event,true)

func ui_checks(parent: Node) -> void:
    controls=parent.get_node("/root/MoonstoneInput")
    var old_profile: Dictionary=controls.profile.duplicate(true)
    var old_write: bool=controls.allow_write
    controls.profile=controls.Profile.defaults();controls.allow_write=false;controls.seats.test_devices=[42,7,9,12];controls.seats.port_devices=[-1,-1,-1,-1]
    controls.clear_input();controls.blocked.clear();controls.active_device=-1;controls.focused=true
    var world: Node=load("res://scenes/main.tscn").instantiate()
    world.saving_enabled=false;world.parse_launch_arguments=false;world.debug_mode=false
    parent.add_child(world);world.set_physics_process(false)
    await parent.get_tree().process_frame
    world.show_menu({})
    var initial: Dictionary=world.journey.checkpoint()
    press(KEY_N);press(KEY_I)
    check(world.local_setup!=null and world.selection_view!=null,"New journey exposes Local players setup")
    if world.local_setup==null:world.queue_free();return
    tap(42,JOY_BUTTON_A)
    check(world.local_setup.editing,"controller confirm edits the selected name")
    tap(42,JOY_BUTTON_A)
    check(not world.local_setup.editing,"controller confirm accepts the name and returns to setup")
    press(KEY_ESCAPE)
    check(world.local_setup==null and world.selection_view.visible and world.journey.checkpoint()==initial,"cancelling setup leaves the current campaign unchanged")
    press(KEY_I)
    var setup: Node=world.local_setup
    click(parent,setup.field_rect(0,2).get_center());click(parent,setup.field_rect(1,2).get_center())
    click(parent,setup.row_rect(4).get_center())
    check(world.local_setup!=null and not setup.notice.is_empty() and world.journey.checkpoint()==initial,"setup rejects assigning the same controller to both humans without committing")
    click(parent,setup.field_rect(1,2).get_center())
    click(parent,setup.row_rect(4).get_center())
    check(world.local_setup==null and world.menu_view==null and world.selection_view==null and world.journey.party!=null,"Start commits one local campaign and closes setup")
    if world.journey.party==null:world.queue_free();return
    check(world.journey.party.players[0].input==1 and world.journey.party.players[1].input==2,"chosen logical controller ports belong to distinct knights")
    controls.refresh_context()
    tap(7,JOY_BUTTON_A)
    check(world.journey.party.awaiting,"the other player's controller cannot accept the current turn")
    tap(42,JOY_BUTTON_A)
    check(not world.journey.party.awaiting,"the assigned controller accepts its own handoff")
    world.journey.rest();controls.refresh_context()
    check(world.journey.party.active==1 and world.journey.party.awaiting,"map rest opens the next human handoff")
    tap(42,JOY_BUTTON_A)
    check(world.journey.party.awaiting,"previous controller cannot operate the next knight's turn")
    tap(7,JOY_BUTTON_A)
    check(not world.journey.party.awaiting,"second controller accepts the second human turn")
    var rival: Dictionary=world.journey.rivals.find(world.journey.party.id_for(0))
    rival.position=world.journey.world.position+Vector2i(1,0)
    world.journey.begin_rival_encounter(rival.id,false);world.show_lair();world.arena.set_physics_process(false)
    await parent.get_tree().process_frame
    controls.refresh_context()
    check(world.arena.duel_ready and world.arena.local_players.size()==2,"human duel displays a readiness screen before simulation begins")
    var tick: int=world.arena.session.simulation.tick
    world.arena._physics_process(0.02)
    check(world.arena.session.simulation.tick==tick,"ready screen does not advance combat")
    press(KEY_ENTER)
    check(not world.arena.duel_ready,"keyboard confirm starts the human duel")
    button(7,JOY_BUTTON_X);button(42,JOY_BUTTON_Y)
    check(controls.action_for(1)=="swing" and controls.action_for(0,true)=="heavy","two assigned controllers produce different simultaneous attacks")
    button(9,JOY_BUTTON_B)
    check(controls.action_for(1)=="swing" and controls.action_for(0,true)=="heavy","unassigned controller cannot hijack either fighter")
    world.arena._physics_process(0.02)
    var opponent: int=0
    for id in world.arena.local_players:
        if id!=1:opponent=id
    check(world.arena.session.simulation.actors[1].action=="swing" and world.arena.session.simulation.actors[opponent].action=="heavy","actual arena routes both players in the same simulation tick")
    button(7,JOY_BUTTON_X,false);button(42,JOY_BUTTON_Y,false);button(9,JOY_BUTTON_B,false)
    key(KEY_Z);key(KEY_KP_9)
    check(controls.action_for(1)=="swing" and controls.action_for(0,true)=="heavy","shared keyboard separates normal and defender number-pad attacks")
    key(KEY_Z,false);key(KEY_KP_9,false)
    controls._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
    check(parent.get_tree().paused and controls.direction_for(1)==Vector2i.ZERO and controls.action_for(0,true)=="idle","local duel focus loss pauses both humans even after keyboard use")
    controls._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN);controls.close_pause()
    button(42,JOY_BUTTON_START)
    check(parent.get_tree().paused and controls.pause_view!=null,"defender can pause the duel with their controller")
    button(42,JOY_BUTTON_START,false)
    var paused: Dictionary=world.arena.session.simulation.snapshot()
    world.arena.set_physics_process(true)
    for frame in range(3):await parent.get_tree().process_frame
    check(world.arena.session.simulation.snapshot()==paused,"both fighters stop while paused")
    world.arena.set_physics_process(false)
    tap(42,JOY_BUTTON_START)
    check(not parent.get_tree().paused,"the player who paused can resume with the same controller")
    controls.seats.test_devices=[7,9,12]
    controls.connection_changed(42,false)
    check(parent.get_tree().paused,"disconnecting the defender pauses both fighters")
    check(controls.seats.device_for(2)==7 and controls.seats.device_for(1)==-1,"disconnect does not reassign the other controller's player")
    controls.close_pause()
    world.journey.return_to_map(false)
    world.remove_child(world.arena);world.arena.queue_free();world.arena=null
    var recover: RefCounted=fresh()
    recover.begin_turn();recover.character.lives=0;recover.character.health=0
    world.show_menu(recover.checkpoint());world.menu_choice("continue")
    world._physics_process(0.02)
    check(world.journey.party.active==1 and world.journey.party.awaiting,"Continue after a final-life defeat advances to another living human")
    world.queue_free()
    await parent.get_tree().process_frame
    controls.profile=old_profile;controls.allow_write=old_write;controls.seats.test_devices=[];controls.seats.port_devices=[-1,-1,-1,-1];controls.clear_input();controls.blocked.clear();controls.active_device=-1;controls.using_controller=false

func store_checks() -> void:
    var j: RefCounted=fresh()
    var path: String="user://local-player-review-"+str(OS.get_process_id())+".json"
    var store: RefCounted=load("res://scripts/session/journey_store.gd").new(path,j.validate_checkpoint)
    j.store=store
    check(j.persist(),"whole local party saves through the existing store")
    j.begin_turn();j.inventory.gold=77;j.persist()
    var copy: RefCounted=Journey.new(Definition,Rules,3)
    check(copy.restore_checkpoint(store.load_checkpoint()) and copy.checkpoint()==j.checkpoint(),"saved roster, player kit and turn Continue together")
    if Runtime.debug_enabled():
        check(not FileAccess.file_exists(path) and not FileAccess.file_exists(path+".tmp") and not FileAccess.file_exists(path+".bak"),"debug local play creates no primary backup or temporary save")
    else:
        check(FileAccess.file_exists(path) and FileAccess.file_exists(path+".bak") and not FileAccess.file_exists(path+".tmp"),"normal local campaign commits and retains a backup")
    for suffix in ["",".tmp",".bak"]:
        if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)

func core_checks() -> void:
    var roster: Array=Party.defaults()
    for row in roster:row.human=true
    var j: RefCounted=fresh(roster)
    check(j.party.active==0 and j.human_players==4 and j.party.awaiting,"four independent seats start at a handoff")
    var position: Vector2i=j.world.position
    check(not j.travel(Vector2i.RIGHT) and j.world.position==position and not j.rest(),"handoff cannot spend travel or skip a turn")
    roundtrip(j,"initial handoff")
    j.begin_turn()
    j.inventory.gold=88;j.inventory.items={"healing_potion":2}
    j.character.experience=12;j.character.stats.strength=3;j.character.health=7
    j.world.position=Vector2i(75,95);j.places.recency=50;j.places.frog_days=0
    j.revealed_lairs[Definition.lairs[0].id]=true
    var primary: Dictionary=j.character.snapshot()
    check(j.rest() and j.party.active==1 and j.party.awaiting and j.day==1,"ending seat zero opens seat one within the same round")
    check(j.inventory.gold==j.character_rules.starting_gold,"next human has their own purse")
    check(j.character.experience==0 and j.character.stats.strength==1 and j.inventory.items.is_empty(),"XP stats and potions do not leak to another knight")
    roundtrip(j,"second human")
    for seat in [1,2,3]:
        check(j.party.active==seat,"stable human seat order "+str(seat))
        j.begin_turn();j.inventory.gold=20+seat
        check(j.rest(),"each human can finish their own turn")
    check(j.party.active==0 and j.day==2 and j.party.awaiting,"one complete round requires all four slots")
    check(j.inventory.gold==88 and j.inventory.items.healing_potion==2 and j.character.experience==12 and j.character.stats==primary.stats,"primary keeps their own kit after a full round")
    check(j.world.position==Vector2i(75,95) and j.places.recency==40 and j.revealed_lairs.has(Definition.lairs[0].id),"personal position wizard recency and revealed lairs survive other turns")
    check(j.character.health>7,"round upkeep heals once")
    roundtrip(j,"full round")
    # End-of-turn item operations commit against the outgoing owner first.
    var teleport: RefCounted=fresh(roster)
    teleport.begin_turn();teleport.world.position=teleport.town("home").position
    teleport.enter_town("home");teleport.inventory.items.scroll_of_the_hawk=1
    check(teleport.use_item("scroll_of_the_hawk",Vector2i(60,70)),"Hawk works while leaving a personal home")
    var traveller: Dictionary=teleport.party.record(teleport,0)
    check(teleport.party.active==1 and traveller.position==Vector2i(60,70) and not traveller.inventory.items.has("scroll_of_the_hawk"),"teleport and scroll consumption belong to the outgoing knight")
    check(teleport.world.position!=Vector2i(60,70) and teleport.inventory.items.is_empty(),"next human is not teleported or charged for another player's scroll")
    roundtrip(teleport,"home teleport handoff")
    teleport=fresh(roster);teleport.begin_turn()
    var site: String=Definition.lairs[0].id
    teleport.world.position=teleport.world.lair(site).position;teleport.world.active_lair=site
    teleport.start_site_combat();teleport.combat.simulation.spawn_remaining=0
    for actor in teleport.combat.simulation.actors.values():
        if actor.team==2:actor.health=0;actor.down_remaining=0
    teleport.prepare_loot();teleport.inventory.items.scroll_of_the_hawk=1
    teleport.travel_spent=teleport.travel_allowance()
    check(teleport.use_item("scroll_of_the_hawk",Vector2i(62,72)),"Hawk works from loot on the last travel point")
    traveller=teleport.party.record(teleport,0)
    check(teleport.party.active==1 and traveller.position==Vector2i(62,72) and traveller.character.experience==1 and not traveller.inventory.items.has("scroll_of_the_hawk"),"loot exit settles once before teleport and player handoff")
    roundtrip(teleport,"loot teleport handoff")
    traces["four_human_round"]=j.checkpoint().hash()
    sample_checkpoint=j.checkpoint().duplicate(true)
    var before: Dictionary=j.checkpoint()
    for kind in ["zero_humans","port_conflict","identity","wrong_turn","bad_item","duplicate_keys","unexpected","fractional"]:
        var bad: Dictionary=before.duplicate(true)
        match kind:
            "zero_humans":
                for row in bad.party.players:row.human=false
            "port_conflict":bad.party.players[0].input=1;bad.party.players[1].input=1
            "identity":bad.party.players[1].identity.kind=0
            "wrong_turn":bad.party.turn=2
            "bad_item":bad.party.personal[0].duel.items["not-an-item"]=1
            "duplicate_keys":bad.party.personal[0].duel.keys=1;bad.campaign.owned_keys=1
            "unexpected":bad.party.players[1].extra=true
            "fractional":bad.party.active=0.5
        check(not j.restore_checkpoint(bad) and j.checkpoint()==before,"malformed local save rejected atomically: "+kind)
    var solo: RefCounted=Journey.new(Definition,Rules,234)
    var legacy: Dictionary=solo.checkpoint()
    check(j.restore_checkpoint(legacy) and j.party==null and j.checkpoint()==legacy,"existing solo saves retain their exact shape and gameplay")
    # Real duel commands and per-knight settlement, with explicit result fixtures.
    j=fresh()
    var opponent: int=duel(j)
    if opponent!=0:
        check(j.combat.simulation.actors[1].owner==1 and j.combat.simulation.actors[opponent].owner==2 and j.combat.simulation.actors[opponent].kind=="knight","both humans use player rules and distinct command ownership")
        check(not j.combat.command(opponent,1,Vector2i.LEFT,"heavy"),"one human cannot issue the other human's commands")
        j.combat.advance(Vector2i.LEFT,"swing",{opponent:{"direction":Vector2i.RIGHT,"action":"heavy"}})
        check(j.combat.simulation.actors[1].action=="swing" and j.combat.simulation.actors[opponent].action=="heavy","both human attacks reach one deterministic combat tick")
        j.combat.simulation.actors[opponent].daggers=1
        j.combat.simulation.actors[opponent].health=0;j.combat.simulation.actors[opponent].down_remaining=0
        var lives: int=j.rivals.records[0].character.lives
        check(j.prepare_loot(),"human duel winner receives normal loot phase")
        check(j.character.experience==1 and j.rivals.records[0].character.lives==lives-1 and j.rivals.records[0].character.daggers==1,"human victory settles XP life loss and defender daggers once")
        var settled: Dictionary=j.checkpoint()
        j.settle_battle();check(j.checkpoint()==settled,"repeated duel settlement does not duplicate rewards")
        roundtrip(j,"human duel loot")
        j.return_to_map(false)
        check(j.party.active==1 and j.party.awaiting,"outgoing human duel spends the attacker's turn")
        check(j.character.lives==lives-1 and j.character.daggers==1,"defender's next turn retains their duel result")
        roundtrip(j,"defender handoff")
    j=fresh();opponent=duel(j)
    if opponent!=0:
        j.inventory.gold=40;j.combat.simulation.actors[1].health=0;j.combat.simulation.actors[1].down_remaining=0
        j.combat.simulation.actors[opponent].health=9
        j.return_to_map(false)
        check(j.party.active==1 and j.character.experience==1 and j.character.health==9 and j.inventory.gold>j.character_rules.starting_gold,"human defender victory retains their XP wounds and spoils")
        roundtrip(j,"defender victory")
    # Real AI scheduler between humans, preserving a pending incoming duel.
    j=fresh();j.begin_turn();j.rest();j.begin_turn();j.rest()
    check(j.party.turn==2 and j.rivals.active!=0,"computer seats retain independent turns")
    var frames: int=0
    while j.day==1 and frames<5000:
        if j.combat!=null:
            for actor in j.combat.simulation.actors.values():
                if actor.team==2:actor.health=0;actor.down_remaining=0
            j.return_to_map(false)
        else:j.advance_rival_turn()
        frames+=1
    check(j.day==2 and j.party.active==0 and j.party.awaiting,"AI slots return to the next human without advancing the day twice")
    roundtrip(j,"AI round complete")
    j=fresh(roster)
    for row in j.rivals.records:row.character.lives=0;row.character.health=0
    j.begin_turn();j.rest()
    check(j.party.active==0 and j.day==2,"eliminated seats are skipped")
    j.begin_turn();j.character.lives=0;j.character.health=0;j.party.end_turn(j)
    check(j.party.game_over and not j.party.awaiting and j.rivals.active==0,"all human eliminations stop the campaign cleanly")
    roundtrip(j,"game over")
    j=fresh();j.begin_turn();j.character.lives=0;j.character.health=0
    j.rivals.records[0].character.lives=0;j.rivals.records[0].character.health=0
    j.party.turn=2;j.rivals.active=2;j.turn_reason="rest";j.party.next_turn(j)
    check(j.party.game_over and j.party.turn==j.party.active,"last human loss during a computer turn closes the acting slot")
    roundtrip(j,"computer-turn game over")
    j=fresh();j.begin_turn();j.character.lives=0;j.character.health=0
    j.party.turn=1;j.party.next_turn(j)
    check(j.party.active==1 and not j.party.awaiting and j.rivals.active!=0,"AI defends against a living human after the previous human is eliminated")
    roundtrip(j,"living defender during AI turn")
    j=fresh(roster);j.begin_turn();j.day=9;j.dragon_order=1;j.rest()
    check(j.party.active==1 and j.party.wyrm_target==1 and j.dragon_order==-1,"Wyrm target follows its stable seat when that human becomes current")
    check(j.dragon_aim()==j.world.position and j.world.dragon.target==0,"a previously targeted human remains the Dragon's target on their own turn")
    roundtrip(j,"targeted human handoff")

func run_checks(parent: Node) -> Dictionary:
    core_checks()
    store_checks()
    await ui_checks(parent)
    return {"checks":checks,"failures":failures,"traces":traces,"sample_checkpoint":sample_checkpoint,"debug":Runtime.debug_enabled(),"hardware":"NOT_RUN"}

func report(host: Node) -> void:
    var result: Dictionary=await run_checks(host)
    print("LOCAL_PLAYERS_STATE=",JSON.stringify(result))
    print("PASS:" if failures.is_empty() else "FAIL:",checks," local player ownership, rounds, duels, save compatibility checks ",JSON.stringify(failures))
    host.get_tree().quit(0 if failures.is_empty() else 1)
