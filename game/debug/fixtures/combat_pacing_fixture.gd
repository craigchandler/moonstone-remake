extends RefCounted

# Explicit review fixture: fixed starting positions/HP, then production commands,
# collision, animation and live AI. No original assets or runtime clocks changed.
var choice: String = "pacing_swing-miss-blue"
var mirror: bool = false
var tick: int = 0
var checked: Dictionary = {}
var rows: Array = []
var move: String = "swing"
var outcome: String = "miss"
var source: int = 1
var target: int = 10
var damage: int = 0
var attacks: Array = []
var destination: int = 158
var animator: RefCounted = preload("res://scripts/presentation/actor_animator.gd").new()
var art: Resource = preload("res://content/classic_art.tres")
func length() -> int:
    if outcome=="held":return 180
    return 430 if outcome=="evade" else (300 if outcome=="repeat" else 120)
func setup(session: RefCounted) -> void:
    var parts: PackedStringArray=choice.trim_prefix("pacing_").split("-")
    move=parts[0];outcome=parts[1]
    if move=="spear":move="spear_thrust"
    source=10 if move=="spear_thrust" else 1;target=1 if source==10 else 10
    session.start(&"competitive",&"spear_lair" if source==10 else &"black_knight_fight",{"count":2 if outcome=="evade" else 1,"concurrent":2 if outcome=="evade" else 1})
    var m: RefCounted=session.simulation
    if outcome=="evade":return
    var a: Dictionary=m.actors[source];var b: Dictionary=m.actors[target]
    a.x=80 if source==10 else 160;a.y=166;a.facing=1;a.entering=false;a.cooldown_remaining=0
    if move=="upward" and outcome in ["tall","lethal"]:
        m.actors[target]=m.make_actor(target,b.owner,b.team,"giant_troll",Vector2i(a.x+50,166),-1)
        b=m.actors[target]
    b.x=a.x+{"swing":45,"heavy":80,"reverse":-35,"lunge":80,"dagger":110,"spear_thrust":130,"upward":50}.get(move,45)
    b.y=139 if outcome in ["miss","cancel","held"] else 166
    b.health=1 if outcome=="lethal" else 1000;b.maximum=b.health
    b.facing=1 if move=="reverse" else -1;b.entering=false;b.cooldown_remaining=0
    if outcome=="cleave":
        m.actors[11]=m.make_actor(11,0,2,"black_knight",Vector2i(b.x,b.y),b.facing)
        m.actors[11].health=1;m.actors[11].cooldown_remaining=0
    if mirror:
        for actor in m.actors.values():actor.x=320-actor.x;actor.facing=-actor.facing
func advance(session: RefCounted) -> void:
    if tick==0:setup(session)
    var m: RefCounted=session.simulation
    if outcome=="held":
        session.command(source,m.actors[source].owner,Vector2i.ZERO,move)
        m.advance()
    elif outcome=="repeat":session.advance(Vector2i.ZERO,"idle")
    elif outcome=="evade":
        var live: bool=false
        for actor in m.actors.values():
            if actor.action!="spear_thrust" or actor.remaining<=0:continue
            live=true
            if actor.attack_flow.get("started",-1)==m.tick-1:
                var side: int=signi(m.actors[1].y-actor.y)
                if side==0:side=1 if actor.y<=158 else -1
                destination=clampi(actor.y+12*side,139,177)
        if not live:destination=158
        var dy: int=signi(destination-int(m.actors[1].y))
        if abs(destination-int(m.actors[1].y))<2:dy=0
        session.advance(Vector2i(0,dy),"idle")
    else:
        if tick==10:session.command(source,m.actors[source].owner,Vector2i.ZERO,move)
        if outcome=="block":session.command(target,m.actors[target].owner,Vector2i.ZERO,"block")
        if outcome=="cancel" and tick>10:session.command(source,m.actors[source].owner,Vector2i.UP,"idle")
        m.advance()
    animator.update(m.actors,m.rules,art)
    for event in m.events:
        if event.type=="damage":damage+=1
        if event.type=="attack" and event.actor==source:attacks.append(tick)
    var row: Dictionary={"tick":tick,"actors":{},"events":m.events.duplicate(true)}
    for id in m.actors:
        var a: Dictionary=m.actors[id]
        row.actors[id]={"x":a.x,"y":a.y,"health":a.health,"action":a.action,"remaining":a.remaining,"flow":a.attack_flow.duplicate(true),
            "reaction":a.reaction,"reaction_remaining":a.reaction_remaining,"pose":animator.poses.get(id,{}).get("index",-1)}
    rows.append(row);tick+=1
func verify(session: RefCounted) -> bool:
    var m: RefCounted=session.simulation
    if outcome=="held":checked={"held_cadence":attacks==[0,43,86,129,172],"no_hits":damage==0,"survived":m.actors[source].health>0}
    elif outcome=="evade":checked={"survived":m.actors[1].health==20,"repeated":attacks.size()>=5,"no_hits":damage==0}
    elif outcome=="repeat":
        var exact: bool=attacks.size()>=4
        for i in range(1,attacks.size()):exact=exact and attacks[i]-attacks[i-1]==65
        checked={"contact_cadence":exact,"one_hit_each":damage==attacks.size(),"survived":m.actors[1].health>0}
    elif outcome=="cleave":
        checked={"two_contacts":damage==2,"one_death":m.actors[11].health==0,"full_tail":m.actors[source].attack_flow.branch=="full","survivor":m.actors[target].health==995}
    else:
        var expected: int=0 if outcome in ["miss","cancel"] or (outcome=="block" and move!="dagger") else 1
        checked={"one_attack":attacks.size()==1,"damage_count":damage==expected,"survived":m.actors[source].health>0,
            "outcome":m.actors[target].health==(1 if outcome=="lethal" else 1000)-int(m.rules.moves[move].damage)*expected if outcome!="lethal" else m.actors[target].health==0}
    for key in checked:
        if not checked[key]:push_error(choice+" failed: "+key)
    return not checked.values().has(false)
func report() -> Dictionary:return {"choice":choice,"mirror":mirror,"checks":checked,"rows":rows}

static func batch(host: Node) -> void:
    # Fast exported-state acceptance: same fixture/model/animator, explicit ticks.
    # Graphical and audio acceptance remain separate ordinary frame-loop runs.
    var cases: Array=[]
    for name in ["swing","heavy","lunge","reverse","dagger","spear"]:
        for result in ["miss","hit","block","lethal"]:cases.append(name+"-"+result+"-blue")
    cases.append_array(["spear-repeat-blue","spear-evade-blue","swing-cleave-blue"])
    for name in ["swing","heavy","lunge","reverse","dagger"]:cases.append(name+"-cancel-blue")
    var states: Dictionary={}
    for name in cases:
        for mirrored in [false,true]:
            var fixture: RefCounted=load("res://debug/fixtures/combat_pacing_fixture.gd").new()
            fixture.choice="pacing_"+name;fixture.mirror=mirrored
            var session: RefCounted=load("res://scripts/session/local_session.gd").new(preload("res://content/foundation_rules.tres"))
            fixture.advance(session)
            while fixture.tick<fixture.length():fixture.advance(session)
            if not fixture.verify(session):host.get_tree().quit(1);return
            states[name+("-mirror" if mirrored else "")]={"state":session.simulation.snapshot(),"trace":fixture.report()}
    print("PACING_BATCH_STATE=",JSON.stringify(states))
    print("PASS:64 deterministic pacing scenarios; explicit ticks, separate from graphics/audio acceptance")
    host.get_tree().quit()
