extends RefCounted

# Explicit production-command diagnostics; high HP permits repeated recovery.
const Session=preload("res://scripts/session/local_session.gd")
const Rules=preload("res://content/foundation_rules.tres")
const Animator=preload("res://scripts/presentation/actor_animator.gd")
const Art=preload("res://content/generated/classic_layered_art.tres")
var choice:String="knight_rhythm"
var mirror:bool=false
var tick:int=0
var seed_value:int=12345
var events:Array=[]
var hurt_steps:Dictionary={1:0,10:0}
var completed_hurts:Array=[]
var failures:Array=[]
func length()->int:return 600
func setup(session:RefCounted)->void:
    session.start(&"competitive",&"black_knight_fight",{"combat_seed":seed_value,"knight_difficulty":2})
    var m:RefCounted=session.simulation
    m.actors[1].x=100;m.actors[10].x=180
    for a in m.actors.values():
        a.health=1000;a.maximum=1000
        if mirror:a.x=320-a.x;a.facing=-a.facing
func advance(session:RefCounted)->void:
    if tick==0:setup(session)
    session.advance(Vector2i.ZERO,"idle" if tick<120 else ("swing" if tick<420 else "heavy"))
    var m:RefCounted=session.simulation
    for e in m.events:
        if e.type in ["attack","damage","parry"]:
            var row:Dictionary=e.duplicate(true);row.tick=tick;events.append(row)
    # A fresh hit can land on the expiry step. Count each completed protected
    # path separately even when two complete recoveries are contiguous.
    for e in m.events:
        if e.type=="damage" and hurt_steps.has(e.actor) and hurt_steps[e.actor]>0:
            completed_hurts.append([e.actor,hurt_steps[e.actor]])
            if hurt_steps[e.actor]!=30:failures.append("hurt interrupted before expiry")
            hurt_steps[e.actor]=0
    for id in [1,10]:
        var actor:Dictionary=m.actors[id]
        if actor.stagger_remaining>0:
            hurt_steps[id]+=1
            if actor.remaining>0:failures.append("attack during committed hurt")
        elif hurt_steps[id]>0:
            completed_hurts.append([id,hurt_steps[id]])
            if hurt_steps[id]!=30:failures.append("hurt path shortened")
            hurt_steps[id]=0
    tick+=1
func verify(_session:RefCounted)->bool:
    return failures.is_empty() and tick>=length() and completed_hurts.any(func(row:Array)->bool:return row[0]==1) and events.any(func(e:Dictionary)->bool:return e.type=="attack" and e.actor==10)
func report()->Dictionary:
    return {"seed":seed_value,"mirror":mirror,"ticks":tick,"events":events,"completed_hurts":completed_hurts,"failures":failures}
static func audit()->Dictionary:
    var rows:Array=[]
    for seed_value in [12345,987654321]:
        for mirrored in [false,true]:
            var s:RefCounted=Session.new(Rules);var f:RefCounted=load("res://debug/fixtures/knight_rhythm_fixture.gd").new()
            f.seed_value=seed_value;f.mirror=mirrored
            var animator:RefCounted=Animator.new()
            for n in f.length():
                f.advance(s);var snap:Dictionary=s.simulation.snapshot();animator.update(s.simulation.actors,Rules,Art)
                if s.simulation.snapshot()!=snap:f.failures.append("presentation changed simulation")
            var result:Dictionary=f.report();result.valid=f.verify(s);result.state_hash=s.simulation.snapshot().hash();rows.append(result)
    return {"cases":rows,"valid":rows.all(func(row:Dictionary)->bool:return row.valid)}
static func batch(host:Node)->void:
    var result:Dictionary=audit();print("KNIGHT_RHYTHM=",JSON.stringify(result))
    print("PASS: knight decisions, complete recovery and deterministic layer-isolated replay" if result.valid else "FAIL: knight rhythm fixture")
    host.get_tree().quit(0 if result.valid else 1)
