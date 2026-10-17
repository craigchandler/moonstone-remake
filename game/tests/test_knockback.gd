extends SceneTree
const Session=preload("res://scripts/session/local_session.gd")
const Fixture=preload("res://debug/fixtures/knockback_fixture.gd")
const Animator=preload("res://scripts/presentation/actor_animator.gd")
const Scheduler=preload("res://scripts/presentation/combat_sound_cues.gd")
var rules:Resource=preload("res://content/foundation_rules.tres")
var art:Resource=preload("res://content/classic_art.tres")
var sound:Resource=preload("res://assets/classic/audio/sounds.tres")
var failures:int=0
func check(ok:bool,label:String)->void:
    if not ok:failures+=1;push_error(label)
func _initialize()->void:run.call_deferred()
func run()->void:
    for kind in ["troll","balok","guardian","guardian_release","dragon","fire"]:
        for state in (["alive","dead","edge","edge_dead"] if kind=="troll" else ["alive","dead"]):
            for mirror in [false,true]:
                var session:RefCounted=Session.new(rules);var replay:RefCounted=Session.new(rules)
                var fixture:RefCounted=Fixture.new();fixture.choice="knock_"+kind+"~"+state;fixture.mirror=mirror
                var other:RefCounted=Fixture.new();other.choice=fixture.choice;other.mirror=mirror
                var animator:RefCounted=Animator.new();var scheduler:RefCounted=Scheduler.new()
                for n in fixture.length():
                    fixture.advance(session);other.advance(replay)
                    var sim:RefCounted=session.simulation;var before:Dictionary=sim.snapshot()
                    animator.update(sim.actors,rules,art);scheduler.collect(sim,animator.poses,art,sound)
                    check(sim.snapshot()==before and sim.snapshot()==replay.simulation.snapshot(),"motion replay and art/audio isolation "+fixture.choice)
                check(fixture.verify(session),"real contact, exact hop steps, facing, stable landing and living/death completion "+fixture.choice+str(mirror))
    # Two simultaneous per-actor hops, their opposite directions and interruption
    # must remain independent; snapshots own their nested motion progress.
    var session:RefCounted=Session.new(rules);session.start(&"competitive")
    var sim:RefCounted=session.simulation
    for a in sim.actors.values():a.cooldown_remaining=10000;a.x=160
    sim.start_hop_recovery(sim.actors[1],1);sim.start_hop_recovery(sim.actors[2],-1)
    var snapshot:Dictionary=sim.snapshot();snapshot.actors[1].motion.next_step=99
    check(sim.actors[1].motion.next_step==1,"snapshot cannot mutate motion progress")
    for n in 19:sim.advance()
    check(sim.actors[1].x==255 and sim.actors[2].x==65,"simultaneous opposite hops retain all four independent table steps")
    # A terminal state must discard any unfinished movement, without starting
    # another hop unless the new hit itself requires that path.
    sim.start_hop_recovery(sim.actors[1],-1);var x:int=sim.actors[1].x
    sim.actors[1].health=0;sim.knock_down(sim.actors[1],"defeat")
    for n in 30:sim.advance()
    check(sim.actors[1].x==x and sim.actors[1].motion.is_empty(),"ordinary death cancels previous hop remainder")
    for x0 in [10,320]:
        session.start(&"competitive");sim=session.simulation
        for actor in sim.actors.values():actor.cooldown_remaining=10000
        sim.actors[1].x=x0
        session.command(1,1,Vector2i.UP,"idle");sim.advance()
        check(sim.actors[1].x==x0 and sim.actors[1].y==164,"real vertical input moves depth without snapping a source overshoot")
        var direction:int=1 if x0<22 else -1
        session.command(1,1,Vector2i(direction,0),"idle");sim.advance()
        check(sim.actors[1].x==x0+2*direction,"real horizontal input returns gradually from hop overshoot")
    if failures==0:print("PASS:28 real-contact hop paths, exact95px steps and source edge consumption, living/dead settled positions, forced facings, independent simultaneous/replayed motion, interruption and native art/audio isolation")
    quit(1 if failures else 0)
