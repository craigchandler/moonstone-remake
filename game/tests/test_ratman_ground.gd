extends SceneTree
const Session=preload("res://scripts/session/local_session.gd")
const Fixture=preload("res://debug/fixtures/ratman_ground_fixture.gd")
const Brain=preload("res://scripts/domain/ratman_combat.gd")
const Animator=preload("res://scripts/presentation/actor_animator.gd")
const Flat=preload("res://content/classic_art.tres")
const Layers=preload("res://content/generated/classic_layered_art.tres")
const Rules=preload("res://content/foundation_rules.tres")
var checks:int=0
var failures:int=0
func check(ok:bool,label:String)->void:
    checks+=1
    if not ok:failures+=1;push_error(label)
func _initialize()->void:run.call_deferred()
func run()->void:
    for mirror in [false,true]:
        var s:RefCounted=Session.new(Rules);var f:RefCounted=Fixture.new();f.mirror=mirror
        var replay:RefCounted=Session.new(Rules);var rf:RefCounted=Fixture.new();rf.mirror=mirror
        var animator:RefCounted=Animator.new()
        for n in f.length():
            f.advance(s);rf.advance(replay)
            var before:Dictionary=s.simulation.snapshot()
            animator.update(s.simulation.actors,Rules,Flat if n%2==0 else Layers)
            check(before==s.simulation.snapshot() and before==replay.simulation.snapshot() and s.simulation.events==replay.simulation.events,"deterministic landing replay and flat/layer isolation")
        check(f.verify(s),"natural missed flight returns promptly to melee; full tree wait retained "+str(mirror)+" "+JSON.stringify(f.checked))
        check(f.first_attack-f.landing<=2,"standing knight must not wait271 ticks after ground landing")
    # Independently recorded outputs of the pinned original C++ caster rules.
    var oracle:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ratman_decisions.json"))
    for row in oracle.cases:
        var expected:String={"stand":"idle","throw":"rat_leap"}.get(row.plan,row.plan)
        check(Brain.decision(Rules.ratman,row.depth_near,int(row.flags)!=0,int(row.hp),int(row.wait),int(row.distance))==expected,"original caster decision vector "+JSON.stringify(row))
    for mirrored in [false,true]:
        for distance in [20,35,40,41,45,50,51]:
            for depth in [0,4,5,6]:
                var s:RefCounted=Session.new(Rules);s.start(&"competitive",&"rat_lair",{"count":1,"concurrent":1})
                var m:RefCounted=s.simulation;var foe:Dictionary=m.actors[10]
                foe.x=100 if not mirrored else 220;foe.y=166;foe.cooldown_remaining=0;foe.entering=false
                m.actors[1].x=foe.x+distance*(-1 if mirrored else 1);m.actors[1].y=166-depth
                s.advance(Vector2i.ZERO,"idle")
                check(foe.action==("rat_leap" if depth>5 or distance>50 else ("rat_strike" if distance<=40 else "rat_bite")),"actual ground/lane decision "+str([mirrored,distance,depth]))
    # An actual successful ground hit starts the shared pause; a whiff does not.
    for move in ["rat_strike","rat_bite"]:
        for hit in [false,true]:
            var s:RefCounted=Session.new(Rules);s.start(&"competitive",&"rat_lair",{"count":1,"concurrent":1})
            var m:RefCounted=s.simulation;var a:Dictionary=m.actors[10]
            a.x=100;a.y=166;a.facing=1;a.cooldown_remaining=0;a.entering=false
            m.actors[1].x=135 if move=="rat_strike" else 145;m.actors[1].y=166 if hit else 139
            s.command(10,0,Vector2i.ZERO,move)
            for n in 55:m.advance()
            check(m.ratman_wait_steps==(15 if hit else 0),"only real ground contact starts15-step pause "+move+str(hit))
            check(a.cooldown_remaining==0,"no per-actor generic Ratman cooldown after hit/whiff")
    var s:RefCounted=Session.new(Rules);s.start(&"competitive",&"rat_lair",{"count":1,"concurrent":1})
    var m:RefCounted=s.simulation;var a:Dictionary=m.actors[10];var target:Dictionary=m.actors[1]
    a.x=100;a.y=166;a.cooldown_remaining=0;a.entering=false;target.x=135;target.y=166
    m.actors[11]=m.make_actor(11,0,2,"ratman",Vector2i(180,166),-1);m.actors[11].cooldown_remaining=0
    m.tick=400;m.ratman_wait_steps=15
    check(Brain.choose(m,a,target)=="idle" and m.ratman_wait_steps==14,"eligible ground handler consumes shared pause once")
    m.tick=401;Brain.choose(m,a,target)
    check(m.ratman_wait_steps==14,"shared counter is not drained at50Hz")
    m.tick=406;Brain.choose(m,a,target)
    check(m.ratman_wait_steps==13,"next six-tick source handler consumes one step")
    Brain.choose(m,m.actors[11],target)
    check(m.ratman_wait_steps==12,"second Ratman sees and consumes the same shared counter")
    for busy in ["flight","hurt","hold","entry"]:
        m.tick+=6;a.ratman.next_decision=0
        a.remaining=1 if busy=="flight" else 0;a.stagger_remaining=2 if busy=="hurt" else 0
        a.special_remaining=1 if busy=="hold" else 0;a.cooldown_remaining=3 if busy=="entry" else 0
        Brain.choose(m,a,target)
        check(m.ratman_wait_steps==12,"busy time cannot consume source wait "+busy)
    a.remaining=0;a.stagger_remaining=0;a.special_remaining=0;a.cooldown_remaining=0;a.ratman.next_decision=0
    target.y=160;m.tick+=6
    check(Brain.choose(m,a,target)=="rat_leap" and m.ratman_wait_steps==12,"out-of-depth source decision bypasses rather than burns ground wait")
    target.y=166;target.grab_remaining=1;a.ratman.next_decision=0;m.tick+=6
    check(Brain.choose(m,a,target)=="idle" and m.ratman_wait_steps==12,"held victim blocks melee without consuming wait")
    var snap:Dictionary=m.snapshot();snap.actors[10].ratman.next_decision=-1;snap.ratman_wait_steps=-1
    check(a.ratman.next_decision!=-1 and m.ratman_wait_steps==12,"snapshot cannot mutate shared or actor decision state")
    m.start(&"competitive",0,&"rat_lair",{"count":1,"concurrent":1})
    check(m.ratman_wait_steps==0 and m.actors[10].ratman.next_decision==0,"new encounter resets all Ratman clocks")
    check(m.snapshot().schema==25 and m.snapshot().ratman_versions=={"classic:ratman":{"api":1,"version":1}},"shared wait and handler cadence version combat independently of campaign")
    if failures==0:print("PASS: ",checks," Ratman checks:360 original decisions,56 lane/facing boundaries, real hit/whiff, shared pause/cadence, natural landing/perch replays and layer isolation")
    quit(1 if failures else 0)

