extends RefCounted

# Explicit diagnostic only. Fixed starts use production commands and live AI;
# neither the fixture nor its renderer changes timing, damage or vulnerability.
const Session=preload("res://scripts/session/local_session.gd")
const Rules=preload("res://content/foundation_rules.tres")
const Animator=preload("res://scripts/presentation/actor_animator.gd")
const Art=preload("res://content/generated/classic_layered_art.tres")
const ROSTER=["trogg_spear","trogg_axe","trogg_hammer","giant_troll","balok","war_beast","ratman","mudman","guardian","dragon","black_knight"]
var choice:String="rhythm_trogg_hammer-90"
var mirror:bool=false
var tick:int=0
var rows:Array=[]
var checked:Dictionary={}
func length()->int:return 240
func setup(session:RefCounted)->void:
    var parts:PackedStringArray=choice.trim_prefix("rhythm_").split("-")
    session.start(&"competitive",&"hammer_lair",{"count":1,"concurrent":1})
    var m:RefCounted=session.simulation
    var distance:int=int(parts[1]) if parts.size()>1 else 90
    m.actors[1].x=160;m.actors[1].y=166
    m.actors[10]=m.make_actor(10,0,2,parts[0],Vector2i(160+distance,166),-1)
    m.actors[10].cooldown_remaining=0
    if mirror:
        for a in m.actors.values():a.x=320-a.x;a.facing=-a.facing
func advance(session:RefCounted)->void:
    if tick==0:setup(session)
    session.advance(Vector2i.ZERO,"swing")
    for e in session.simulation.events:
        if e.type in ["attack","damage"]:
            var row:Dictionary=e.duplicate(true);row.tick=tick;rows.append(row)
    tick+=1
func verify(_session:RefCounted)->bool:
    checked={"completed":tick>=length(),"live_combat":not rows.is_empty()}
    return not checked.values().has(false)
func report()->Dictionary:return {"choice":choice,"mirror":mirror,"ticks":tick,"events":rows}

static func audit()->Dictionary:
    var cases:Array=[];var checks:int=0;var failures:Array=[]
    for kind in ROSTER:
        for distance in [45,70,90,110,150]:
            for mirrored in [false,true]:
                var a:RefCounted=Session.new(Rules);var b:RefCounted=Session.new(Rules)
                var fa:RefCounted=load("res://debug/fixtures/combat_recovery_review.gd").new()
                var fb:RefCounted=load("res://debug/fixtures/combat_recovery_review.gd").new()
                fa.choice="rhythm_"+kind+"-"+str(distance);fb.choice=fa.choice
                fa.mirror=mirrored;fb.mirror=mirrored
                var animator:RefCounted=Animator.new()
                for n in fa.length():
                    fa.advance(a);fb.advance(b)
                    var before:Dictionary=a.simulation.snapshot()
                    animator.update(a.simulation.actors,Rules,Art)
                    checks+=1
                    if before!=a.simulation.snapshot() or before!=b.simulation.snapshot() or a.simulation.events!=b.simulation.events:
                        failures.append(fa.choice+" replay/presentation tick "+str(n));break
                cases.append({"kind":kind,"distance":distance,"mirror":mirrored,"events":fa.rows,"knight_hp":a.simulation.actors[1].health,"monster_hp":a.simulation.actors[10].health,"outcome":a.simulation.outcome(),"state_hash":a.simulation.snapshot().hash()})
    return {"checks":checks,"failures":failures,"cases":cases}
static func batch(host:Node)->void:
    var result:Dictionary=audit()
    print("RECOVERY_ROSTER=",JSON.stringify(result))
    host.get_tree().quit(0 if result.failures.is_empty() else 1)
