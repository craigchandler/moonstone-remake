extends SceneTree

const Model=preload("res://scripts/domain/combat_simulation.gd")
const Session=preload("res://scripts/session/local_session.gd")
const Animator=preload("res://scripts/presentation/actor_animator.gd")
const Host=preload("res://scripts/domain/hold_behavior_host.gd")
var rules: Resource=preload("res://content/foundation_rules.tres")
var art: Resource=preload("res://content/classic_art.tres")
var failures: int=0
var checked: int=0

class ReplacementRide extends "res://scripts/gameplay/hold_behavior.gd":
    func decide(context: Dictionary) -> Dictionary:
        context.holder.health=0
        return {"operation":"release","clip":"rat_escape","ticks":30}

class InvalidRide extends "res://scripts/gameplay/hold_behavior.gd":
    func decide(_context: Dictionary) -> Dictionary:
        return {"operation":"throw","damage":-1,"flight_ticks":102,"ticks":96,"clip":"rat_throw_finish"}

func check(ok: bool,label: String) -> void:
    checked+=1
    if not ok:failures+=1;push_error(label)

func fresh(encounter: StringName=&"rat_lair") -> RefCounted:
    var m: RefCounted=Model.new(rules);m.start(&"competitive",0,encounter,{"count":1,"concurrent":1})
    m.actors[10].interaction={};m.actors[10].entering=false
    m.actors[10].visual_kind="";m.actors[10].x=80;m.actors[10].y=166
    m.actors[1].x=155;m.actors[1].y=166
    return m

func input(m: RefCounted,pressed: bool) -> void:
    if pressed:m.submit(1,{"actor":1,"sequence":m.tick+1,"tick":m.tick,"dx":0,"dy":1,"action":"block"})
    m.advance()

func _initialize() -> void:
    var anim: RefCounted=Animator.new()
    for mirror in [false,true]:
        var m: RefCounted=fresh()
        if mirror:
            for a in m.actors.values():a.x=320-a.x;a.facing=-a.facing
        m.actors[10].health=13;m.actors[10].maximum=13
        m.actors[1].damage_bonus=30;m.actors[1].moon_damage_shift=2
        m.start_rat_hold(m.actors[10],m.actors[1],"ride",42)
        for t in range(41):input(m,false)
        input(m,true)
        check(m.actors[10].health==13 and m.actors[1].health==20,"back-ride escape never applies invented sword damage")
        check(m.actors[10].special_clip=="rat_escape" and m.actors[10].special_duration==30 and m.actors[10].special_remaining==29,"085D shake-off replaces unrelated tree release")
        check(m.actors[1].hidden_by==10 and m.actors[1].grabbed_by==0,"composite prevents a duplicate independent knight")
        var poses: Dictionary={}
        for t in range(30):
            anim.update(m.actors,rules,art)
            if anim.poses[10].clip=="rat_escape":poses[anim.poses[10].index]=true
            m.advance()
        check(poses.size()==4,"all four original shake-off drawings appear")
        check(m.actors[1].hidden_by==0 and m.actors[1].grab_remaining==0 and m.actors[10].held_target==0,"shake-off releases exactly once")
        for hp in [20,5]:
            m=fresh();m.actors[1].health=hp;m.start_rat_hold(m.actors[10],m.actors[1],"ride",42)
            for t in range(42):input(m,false)
            check(m.actors[1].health==hp-5,"ride expiry retains source five damage")
            check(m.actors[10].special_clip==("rat_air" if hp>5 else "rat_throw_finish"),"living throw and lethal composite remain separate")
            for t in range(103):m.advance()
            check(m.actors[1].hidden_by==0,"throw settles independent living knight/remains")
        m=fresh();m.start_rat_hold(m.actors[10],m.actors[1],"ride",42)
        m.actors[10].health=0;m.knock_down(m.actors[10],"defeat");m.advance()
        check(m.actors[1].hidden_by==0 and m.actors[1].grab_remaining==0 and m.actors[1].health==20,"ally rescue clears ride without counter damage")
    for delay in [0,238,239]:
        var m: RefCounted=fresh(&"mud_lair")
        m.Finishers.begin(m,m.actors[10],m.actors[1],"mud")
        for t in range(delay):input(m,false)
        input(m,true)
        if delay<239:
            check(m.actors[1].health==20 and m.actors[10].interaction.stage=="release","Mudman escape before expiry")
            for t in range(18):m.advance()
            check(m.actors[10].health==m.actors[10].maximum-1 and m.actors[1].hidden_by==0,"Mudman release removes one holder HP once")
        else:
            check(m.actors[1].health==0 and m.actors[10].interaction.stage=="swallow","Mudman final-tick timeout wins over escape")
            check(not m.events.any(func(e: Dictionary)->bool:return e.type=="escape"),"expired hold emits no escape")
    for choice in [&"axe_lair",&"black_knight_fight"]:
        for mirror in [false,true]:
            var session: RefCounted=Session.new(rules);session.start(&"competitive",choice,{"count":1,"concurrent":1})
            var m: RefCounted=session.simulation
            m.actors[10].entering=false;m.actors[10].x=80;m.actors[10].y=166;m.actors[10].cooldown_remaining=0
            m.actors[1].x=155;m.actors[1].y=166;m.actors[1].facing=-1;m.actors[1].health=3 if choice==&"axe_lair" else 4
            m.actors[10].last_attack="heavy"
            if mirror:
                for a in m.actors.values():a.x=320-a.x;a.facing=-a.facing
            var downs: int=0;var executions: int=0;var poses: Dictionary={};var damage: int=0
            for t in range(360):
                session.advance(Vector2i.ZERO,"idle")
                anim.update(m.actors,rules,art)
                for e in m.events:
                    if e.type=="down" and e.actor==1:downs+=1
                    if e.type=="execution":executions+=1
                    if e.type=="damage" and e.actor==1:damage+=e.amount
                if m.actors[1].defeat_clip=="defeat_gory":poses[anim.poses[1].index]=true
            check(m.actors[1].health==0 and downs==1,"ordinary AI lethal contact produces one defeat: "+String(choice))
            check(executions==1,"AI finds and lands one separate kneeling strike: "+String(choice))
            check(poses.size()==14 and m.actors[1].down_remaining==0,"complete fourteen-pose second death and final remains: "+String(choice))
            check(damage==(3 if choice==&"axe_lair" else 4),"execution adds no health damage: "+String(choice))
    # A human can finish a rival too; an existing sword cannot hit twice.
    var m: RefCounted=Model.new(rules);m.start(&"competitive")
    m.actors[1].x=80;m.actors[2].x=120;m.actors[2].health=5
    m.submit(1,{"actor":1,"sequence":1,"tick":0,"dx":0,"dy":0,"action":"swing"})
    for t in range(1+rules.moves.swing.windup+rules.moves.swing.active+rules.moves.swing.recovery):m.advance()
    check(m.actors[2].health==0 and m.actors[2].defeat_clip=="defeat","one swing cannot also execute its own victim")
    m.submit(1,{"actor":1,"sequence":2,"tick":m.tick,"dx":0,"dy":0,"action":"swing"})
    var count: int=0
    for t in range(150):
        m.advance()
        count+=m.events.filter(func(e:Dictionary)->bool:return e.type=="execution").size()
    check(count==1 and m.actors[2].defeat_clip=="defeat_gory","separate human swing finishes a kneeling rival")
    m=Model.new(rules);m.start(&"competitive")
    m.actors[1].x=80;m.actors[1].health=5;m.actors[2].x=120;m.actors[2].health=0
    m.knock_down(m.actors[2],"defeat");m.actors[2].down_remaining=130
    m.actors[3]=m.make_actor(3,1,2,"knight",Vector2i(120,166),-1)
    for id in [1,3]:m.submit(1,{"actor":id,"sequence":1,"tick":0,"dx":0,"dy":0,"action":"swing"})
    var mutual_execution: bool=false
    for t in range(12):
        m.advance()
        if m.events.any(func(e:Dictionary)->bool:return e.type=="execution"):mutual_execution=true
    check(m.actors[1].health==0 and not mutual_execution and m.actors[2].defeat_clip=="defeat","same-tick lethal counter prevents a dead attacker executing")
    for encounter in [&"axe_lair",&"black_knight_fight",&"duel"]:
        for mirror in [false,true]:
            for separation in [0,10]:
                var session: RefCounted=Session.new(rules);session.start(&"competitive",encounter,{"count":1,"concurrent":1})
                m=session.simulation
                var foe: Dictionary=m.actors[2 if encounter==&"duel" else 10]
                var victim: Dictionary=m.actors[1]
                foe.x=155+separation;foe.y=166;foe.cooldown_remaining=0;foe.entering=false
                victim.x=155;victim.y=166;victim.health=0;m.knock_down(victim,"defeat");victim.down_remaining=138
                if mirror:
                    for a in m.actors.values():a.x=320-a.x;a.facing=-a.facing
                var count_execution: int=0
                for t in range(160):
                    session.advance(Vector2i.ZERO,"idle")
                    count_execution+=m.events.filter(func(e:Dictionary)->bool:return e.type=="execution").size()
                check(count_execution==1,"AI backs away from an overlapping/too-close kneeling target: "+String(encounter))
    # Eligibility is finite; hidden, consumed, already executed and settled
    # corpses never become repeatable targets.
    for clip in ["defeat","defeat_b","hop","flung","defeat_gory"]:
        m=Model.new(rules);m.start(&"competitive");m.actors[2].health=0;m.knock_down(m.actors[2],clip)
        var v: Dictionary=m.actors[2]
        check(not m.Executions.can_hit(m,m.actors[1],v),"unstarted/unsupported death cannot be hit")
        if clip in ["defeat","defeat_b","hop"]:
            var interval: Vector2i=rules.finishes.kneeling_windows[clip]
            m.actors[1].action="swing";v.down_remaining=v.down_duration-interval.x
            check(m.Executions.can_hit(m,m.actors[1],v),"exact first kneeling tick accepts contact")
            v.hidden_by=99;check(not m.Executions.can_hit(m,m.actors[1],v),"hidden composite cannot execute");v.hidden_by=0
            v.down_remaining=v.down_duration-interval.y
            check(not m.Executions.can_hit(m,m.actors[1],v),"exact end of kneeling rejects contact")
            for facing in [-1,1]:
                v.facing=facing;v.defeat_clip=clip
                v.down_duration=rules.death_frames.duration("death_knight",clip)
                v.down_remaining=v.down_duration-interval.x
                var before: int=-facing
                check(m.Executions.apply(m,m.actors[1],v) and v.facing==before,"execution inherits the kneeling drawing's facing in both directions: "+clip)
    check(not Host.valid({"operation":"throw","damage":-1,"flight_ticks":1,"ticks":1,"clip":"x"}),"invalid script damage rejected before mutation")
    check(not Host.valid({"operation":"release","ticks":0,"clip":"x"}),"zero script clock rejected")
    check(not Host.valid({"operation":"revive"}),"unsupported script command rejected")
    # Registry replacement uses the supported interface, without changing the
    # host/dispatch. Deliberately mutating context cannot touch real actors.
    var custom: Resource=rules.duplicate()
    custom.hold_behaviors=rules.hold_behaviors.duplicate()
    var replacement: Resource=ReplacementRide.new();replacement.behavior_id=&"classic:ratman.back_ride";replacement.content_version=2
    custom.hold_behaviors["classic:ratman.back_ride"]=replacement
    m=Model.new(custom);m.start(&"competitive",0,&"rat_lair",{"count":1,"concurrent":1})
    m.start_rat_hold(m.actors[10],m.actors[1],"ride",42);m.advance()
    check(m.actors[10].health==m.actors[10].maximum and m.actors[10].special_clip=="rat_escape","registered replacement runs with isolated copied state")
    check(m.snapshot().behavior_versions["classic:ratman.back_ride"].version==2,"replacement version is explicit in replay state")
    var invalid: Resource=InvalidRide.new();invalid.behavior_id=&"classic:ratman.back_ride"
    custom.hold_behaviors["classic:ratman.back_ride"]=invalid
    m=Model.new(custom);m.start(&"competitive",0,&"rat_lair",{"count":1,"concurrent":1})
    m.start_rat_hold(m.actors[10],m.actors[1],"ride",42);m.advance()
    check(m.actors[1].health==20 and m.actors[1].hidden_by==0 and m.actors[10].held_target==0,"rejected command cannot change health or leave an orphan hold")
    m=Model.new(rules);m.start(&"competitive")
    var snap: Dictionary=m.snapshot()
    check(snap.schema==25 and snap.content=="encounters.v31" and snap.behavior_versions=={"classic:ratman.back_ride":{"api":1,"version":1}},"combat records behaviour version independently of campaign saves")
    anim.update(m.actors,rules,art);check(snap==m.snapshot(),"presentation cannot change script state")
    var journey: RefCounted=preload("res://scripts/session/journey_session.gd").new(preload("res://content/first_journey.tres"),rules,0x4d4f4f4e)
    var rival: Dictionary=journey.rivals.records[0];journey.world.position=rival.position
    journey.begin_rival_encounter(rival.id,true)
    m=journey.combat.simulation
    m.actors[1].health=4;m.actors[1].x=155;m.actors[1].y=166
    m.actors[10].x=80;m.actors[10].y=166;m.actors[10].cooldown_remaining=0;m.actors[10].last_attack="heavy"
    var settled: Dictionary={};var executions: int=0
    for t in range(360):
        journey.combat.advance(Vector2i.ZERO,"idle")
        for e in m.events:
            if e.type=="execution":executions+=1
        if m.outcome()!="ongoing":
            journey.settle_battle()
            if settled.is_empty():settled=journey.snapshot()
    check(executions==1 and journey.snapshot()==settled,"actual rival execution cannot settle life/XP/possessions twice")
    check(journey.character.lives==4 and rival.character.experience==1,"execution retains one lost life and one rival XP")
    var checkpoint: Dictionary=journey.checkpoint()
    check(checkpoint.schema==16 and checkpoint.content=="journey.campaign.v14" and not journey.validate_checkpoint(checkpoint).is_empty(),"current campaign checkpoint still validates after execution")
    var copy: RefCounted=preload("res://scripts/session/journey_session.gd").new(preload("res://content/first_journey.tres"),rules,0x4d4f4f4e)
    check(copy.restore_checkpoint(checkpoint) and copy.checkpoint()==checkpoint,"Continue keeps settled life/XP/possessions and existing active-battle retreat policy")
    if failures==0:print("PASS: ",checked," execution/escape checks; real mirrored AI/human second strikes, complete frames, finite contacts, ride release/throw, Mudman deadline, script validation and snapshot isolation")
    quit(1 if failures else 0)
