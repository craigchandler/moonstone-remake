extends RefCounted

const Model=preload("res://scripts/domain/combat_simulation.gd")
const Session=preload("res://scripts/session/local_session.gd")
const Animator=preload("res://scripts/presentation/actor_animator.gd")
var rules: Resource=preload("res://content/foundation_rules.tres")
var art: Resource=preload("res://content/classic_art.tres")
var checks: int=0
var failures: Array[String]=[]

func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failures.append(label)

func full(move: String,spec: Dictionary,facing: int) -> Dictionary:
    var model: RefCounted=Model.new(rules)
    var encounter: String=""
    for key in rules.encounters:
        if rules.encounters[key].creature==spec.kind:encounter=key;break
    model.start(&"competitive",0,StringName(encounter),{"count":1,"concurrent":1})
    var foe: Dictionary=model.actors[10]
    foe.x=160;foe.y=166;foe.facing=facing;foe.entering=false;foe.cooldown_remaining=0
    foe.special_remaining=0;foe.special_clip="";foe.interaction={};foe.visual_kind=""
    model.actors[1].x=285 if facing==1 else 35;model.actors[1].y=139
    var animator: RefCounted=Animator.new()
    var rows: Array=[]
    var expected: Array=[]
    for i in range(spec.pose_ids.size()):
        for n in range(int(spec.pose_ticks[i])):expected.append(int(spec.pose_ids[i]))
    for age in range(int(spec.total_ticks)+2):
        if age==0:
            check(model.submit(0,{"actor":10,"sequence":1,"tick":0,"dx":0,"dy":0,"action":move,"facing":facing}),"accepted full stroke "+move)
        model.advance()
        var before: Dictionary=model.snapshot()
        animator.update(model.actors,rules,art)
        check(before==model.snapshot(),"full-stroke presentation isolation")
        rows.append({"age":age,"pose":animator.poses[10].index,"clip":animator.poses[10].clip,"phase":animator.poses[10].get("phase",""),"remaining":foe.remaining,"x":foe.x,"events":model.events.duplicate(true)})
    check(rows.slice(0,int(spec.total_ticks)).map(func(r:Dictionary)->int:return r.pose)==expected,"independent retail drawing/hold sequence "+move)
    check(rows[int(spec.total_ticks)-1].remaining==1 and rows[int(spec.total_ticks)].remaining==0,"complete clock "+move)
    check(foe.x==160+facing*int(spec.advance_pixels),"existing total advance preserved "+move)
    check(model.actors[1].health==20,"miss does not damage off-lane target "+move)
    check(foe.facing==facing and foe.y==166,"committed facing/depth "+move)
    return {"move":move,"kind":spec.kind,"facing":facing,"rows":rows,"state":model.snapshot()}

func live(encounter: String,mode: String,facing: int) -> Dictionary:
    var a: RefCounted=Session.new(rules)
    var b: RefCounted=Session.new(rules)
    for s in [a,b]:
        s.start(StringName(mode),StringName(encounter),{"count":1,"concurrent":1})
        s.simulation.actors[1].health=1000;s.simulation.actors[1].maximum=1000
        if mode=="cooperative":
            # A staged idle human ally keeps the opening from being won by
            # the automatic companion before the creature can act.
            s.simulation.actors[2].health=1000;s.simulation.actors[2].maximum=1000
            s.simulation.actors[2].owner=2
        if facing<0 and encounter!="dragon_fight":
            for actor in s.simulation.actors.values():actor.x=320-actor.x;actor.facing=-actor.facing
        if encounter=="troll_lair":
            # Stage a usable mid-range lane; entrance routes are covered by
            # the retained encounter suites rather than a reflected entrance.
            s.simulation.actors[10].x=80 if facing==1 else 240
            s.simulation.actors[10].entering=false
            s.simulation.actors[1].x=220 if facing==1 else 100
    var attacks: Array=[]
    var events: Array=[]
    var animator: RefCounted=Animator.new()
    for n in range(480):
        var direction: Vector2i=Vector2i.UP if n>=160 and n<172 else Vector2i.ZERO
        var action: String="block" if n>=80 and n<160 else "idle"
        a.advance(direction,action);b.advance(direction,action)
        for event in a.simulation.events:
            if event.type=="attack" and event.actor==10:attacks.append({"tick":n,"move":event.move})
            if event.type in ["damage","hold","down","parry"]:events.append({"tick":n,"event":event.duplicate(true)})
        if n%12==0:
            check(a.simulation.snapshot()==b.simulation.snapshot(),"live deterministic replay "+encounter)
            var before: Dictionary=a.simulation.snapshot()
            animator.update(a.simulation.actors,rules,art)
            check(before==a.simulation.snapshot() and animator.poses.has(10),"live animation isolation "+encounter)
    check(not attacks.is_empty(),"live AI starts attacks "+encounter)
    return {"attacks":attacks,"events":events,"state":a.simulation.snapshot()}

func run_checks() -> Dictionary:
    var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://debug/fixtures/monster_timing.json"))
    var scenes: Dictionary={}
    for move in fixture.moves:
        var spec: Dictionary=fixture.moves[move]
        var clock: Dictionary=rules.moves[move]
        check([clock.windup,clock.active,clock.recovery]==spec.phase_ticks.map(func(n:Variant)->int:return int(n)),"retail full phase clock "+move)
        var clip: Dictionary=art.animation_for(spec.kind).clips[move]
        check(clip.weights==spec.source_holds.map(func(n:Variant)->int:return int(n)),"source holds retained "+move)
        for facing in [1,-1]:scenes[move+":"+str(facing)]=full(move,spec,facing)
    var lives: Dictionary={}
    for encounter in ["beast_lair","dragon_fight","balok_lair","troll_lair","mud_lair","rat_lair","guardian_fight"]:
        for mode in ["competitive","cooperative"]:
            for facing in [1,-1]:lives[encounter+":"+mode+":"+str(facing)]=live(encounter,mode,facing)
    return {"checks":checks,"failures":failures,"strict_scenes":scenes,"live_scenes":lives}

func report(host: Node) -> void:
    var result: Dictionary=run_checks()
    print("MONSTER_TIMING_STATE=",JSON.stringify(result))
    if failures.is_empty():print("PASS:",checks," consolidated monster timing checks;16 retail-hold scenes and28 live AI/replay scenes")
    else:print("FAIL:",JSON.stringify(failures.slice(0,16)))
    host.get_tree().quit(0 if failures.is_empty() else 1)
