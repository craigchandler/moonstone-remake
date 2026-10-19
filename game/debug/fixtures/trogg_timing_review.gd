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
func fight(move: String,facing: int,case: String) -> Dictionary:
    var axe: bool=move.begins_with("axe_")
    var m: RefCounted=Model.new(rules);m.start(&"competitive",0,&"axe_lair" if axe else &"hammer_lair",{"count":1,"concurrent":1})
    var foe: Dictionary=m.actors[10];var knight: Dictionary=m.actors[1]
    foe.x=160;foe.y=166;foe.facing=facing;foe.entering=false;foe.cooldown_remaining=0
    var distance: int=(100 if axe else 125) if move.ends_with("chop") else 80
    knight.x=160+facing*distance;knight.y=139 if case=="miss" else 166;knight.facing=-facing
    knight.health=1 if case=="lethal" else 1000;knight.maximum=knight.health
    var animator: RefCounted=Animator.new();var rows: Array=[];var hits: int=0;var parries: int=0;var ended: int=-1
    for age in range(120):
        if age==0:m.submit(0,{"actor":10,"sequence":1,"tick":m.tick,"dx":0,"dy":0,"action":move,"facing":facing})
        if knight.health>0:
            m.submit(1,{"actor":1,"sequence":age+1,"tick":m.tick,"dx":0,"dy":-1 if case=="evade" and age<20 else 0,"action":"block" if case=="block" else "idle"})
        m.advance();var before: Dictionary=m.snapshot();animator.update(m.actors,rules,art)
        check(before==m.snapshot(),"presentation isolation")
        for e in m.events:
            if e.type=="damage":hits+=1
            elif e.type=="parry":parries+=1
        rows.append({"age":age,"remaining":foe.remaining,"pose":animator.poses[10].index,"clip":animator.poses[10].clip,"flow":foe.attack_flow.duplicate(true),"health":knight.health,"events":m.events.duplicate(true)})
        if age>0 and ended<0 and foe.remaining==0:ended=age
    var total: int=25 if move.ends_with("swing") else 35
    if case=="miss":
        var first: int=12 if move.ends_with("swing") else 17
        var expected: Array=[]
        for i in range(5 if move.ends_with("swing") else 7):
            for n in range(5):expected.append(first+i)
        check(rows.slice(0,total).map(func(r:Dictionary)->int:return r.pose)==expected,"full original drawing order: "+move)
        check(ended==total,"full attack clock: "+move)
    check(hits==(1 if case in ["hit","lethal"] else 0),"once-only damage/defence: "+move+":"+case)
    check(knight.health==(0 if case=="lethal" else (1000-(3 if axe else 2) if case=="hit" else 1000)),"retained HP/damage: "+move+":"+case)
    if case=="block":check(parries==1,"one facing parry: "+move)
    if axe and case=="hit":
        check(foe.attack_flow.branch=="contact" and ended<total,"positive contact has finite short tail")
        check(rows.any(func(r:Dictionary)->bool:return r.clip=="attack_return"),"contact returns through original final drawing")
    if case in ["lethal","block"]:check(foe.attack_flow.get("branch","full")=="full","lethal/parry keep full path")
    return {"move":move,"facing":facing,"case":case,"ended":ended,"hits":hits,"parries":parries,"rows":rows,"state":m.snapshot()}
func cadence(move: String,defence: String="idle") -> Dictionary:
    var axe: bool=move.begins_with("axe_")
    var s: RefCounted=Session.new(rules);s.start(&"competitive",&"axe_lair" if axe else &"hammer_lair",{"count":1,"concurrent":1})
    var m: RefCounted=s.simulation;var foe: Dictionary=m.actors[10];var knight: Dictionary=m.actors[1]
    knight.x=220;knight.y=166;knight.health=10000;knight.maximum=10000
    foe.x=120 if move.ends_with("chop") else 140;foe.y=166;foe.entering=false;foe.cooldown_remaining=0
    var starts: Array=[];var actions: Array=[]
    for n in range(500):
        s.advance(Vector2i.ZERO,defence)
        for e in m.events:
            if e.type=="attack" and e.actor==10:starts.append(n);actions.append(e.move)
    return {"starts":starts,"moves":actions,"state":m.snapshot()}
func run_checks() -> Dictionary:
    var scenes: Dictionary={}
    for move in ["axe_swing","axe_chop","hammer_swing","hammer_chop"]:
        for facing in [1,-1]:
            for case in ["miss","hit","block","evade","lethal"]:
                scenes[move+":"+str(facing)+":"+case]=fight(move,facing,case)
    var repeats: Dictionary={}
    for move in ["axe_swing","axe_chop","hammer_swing","hammer_chop"]:
        repeats[move]=cadence(move)
    var starts: Array=repeats.axe_chop.starts
    check(starts.size()>=5,"live Axe repeats are measurable")
    for n in range(1,starts.size()):check(starts[n]-starts[n-1]==80,"observed Axe contact repeat80ticks")
    check(rules.geometry.trogg_hammer.attacks.hammer_chop[1].points.is_empty() and rules.geometry.trogg_hammer.attacks.hammer_chop[2].points.is_empty(),"original Hammer non-contact gap")
    check(rules.actor_definitions.trogg_hammer.attack_cooldown_ticks==50,"Hammer uses the shared ten-pass brawler pause at its five-tick cadence")
    return {"checks":checks,"failures":failures,"scenes":scenes,"cadences":repeats}
func report(host: Node) -> void:
    var result: Dictionary=run_checks();print("TROGG_TIMING_STATE=",JSON.stringify(result))
    if result.failures.is_empty():print("PASS:",result.checks," Trogg pose/phase/contact/defence and live-repeat checks")
    else:print("FAIL:",JSON.stringify(result.failures.slice(0,12)))
    host.get_tree().quit(0 if result.failures.is_empty() else 1)
