extends SceneTree
const Model=preload("res://scripts/domain/combat_simulation.gd")
const Animator=preload("res://scripts/presentation/actor_animator.gd")
var rules: Resource=preload("res://content/foundation_rules.tres")
var art: Resource=preload("res://content/classic_art.tres")
var failures: int=0
var checks: int=0
func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failures+=1;push_error(label)
func send(m: RefCounted,kind: String,dy: int=0) -> void:
    check(m.submit(1,{"actor":1,"sequence":m.tick+1,"tick":m.tick,"dx":0,"dy":dy,"action":kind}),"owned input")
func fresh(facing: int=1,tall: bool=false) -> RefCounted:
    var m: RefCounted=Model.new(rules);m.start(&"competitive",2)
    m.actors[1].x=160;m.actors[1].facing=facing
    m.actors[2]=m.make_actor(2,2,2,"giant_troll" if tall else "knight",Vector2i(160+50*facing,166 if tall else 139),-facing)
    m.actors[2].health=1000;m.actors[2].maximum=1000
    return m
func _initialize() -> void:
    for facing in [1,-1]:
        var m: RefCounted=fresh(facing)
        var animator: RefCounted=Animator.new();var poses: Array=[]
        send(m,"upward");m.advance()
        for age in range(42):
            var before: Dictionary=m.snapshot();animator.update(m.actors,rules,art)
            check(before==m.snapshot(),"animator cannot change active clock")
            check(m.actors[1].remaining==42-age,"42 tick full clock")
            poses.append(animator.poses[1].index)
            m.advance()
        check(m.actors[1].remaining==0 and m.actors[2].health==1000,"full miss ends without damage")
        check(poses==[51,51,51,51,51,51,52,52,52,52,52,52]+[53,53,53,53,53,53,53,53,53,53,53,53,53,53,53,53,53,53,53,53,53,53,53,53]+[54,54,54,54,54,54],"all four authored poses retain1/1/4/1 holds")
        m=fresh(facing,true);send(m,"upward");m.advance()
        var contacts: int=0
        for age in range(60):
            m.advance()
            for event in m.events:
                if event.type=="damage":
                    contacts+=1;check(event.amount==4,"unchanged upward damage")
        check(contacts==1 and m.actors[2].health==996,"extended live blade damages each target once")
        for age in range(42):
            for action in ["idle","block"]:
                m=fresh(facing);send(m,"upward");m.advance()
                for n in range(age):m.advance()
                var y: int=m.actors[1].y
                send(m,action,1 if action=="idle" else 0);m.advance()
                var allowed: bool=age<6 or age>=36
                check((m.actors[1].y!=y if action=="idle" else m.actors[1].guarding)==allowed,"windup/return cancel; active phase commits")
    var m: RefCounted=fresh();var starts: Array=[]
    for n in range(180):
        send(m,"upward");m.advance()
        for event in m.events:
            if event.type=="attack" and event.actor==1:starts.append(n)
    check(starts==[0,43,86,129,172],"held repeat is43 ticks without invented cooldown")
    check(m.snapshot().schema==25 and m.snapshot().content=="encounters.v31","clock change versions content without changing snapshot shape")
    if failures==0:print("PASS:",checks," upward checks; mirrored seven-pass poses, full/held clocks, once-only tall-target damage, every-age cancel/commit and presentation isolation")
    quit(1 if failures else 0)
