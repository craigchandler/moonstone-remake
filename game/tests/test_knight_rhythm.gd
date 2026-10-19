extends SceneTree
const Brain=preload("res://scripts/domain/knight_combat.gd")
const Session=preload("res://scripts/session/local_session.gd")
const Rules=preload("res://content/foundation_rules.tres")
const Animator=preload("res://scripts/presentation/actor_animator.gd")
const Art=preload("res://content/generated/classic_layered_art.tres")
class Rolls extends RefCounted:
    var values:Array=[]
    var calls:int=0
    func percent()->int:
        var v:int=values[calls];calls+=1;return v
    func next_value()->int:calls+=1;return 17
var checks:int=0
var failures:int=0
func check(ok:bool,label:String)->void:
    checks+=1
    if not ok:failures+=1;push_error(label)
func fresh(kind:String="black_knight",seed_value:int=12345)->RefCounted:
    var s:RefCounted=Session.new(Rules);s.start(&"competitive",&"black_knight_fight",{"combat_seed":seed_value})
    var m:RefCounted=s.simulation;m.actors[1].x=100
    m.actors[10]=m.make_actor(10,0,2,kind,Vector2i(180,166),-1)
    for a in m.actors.values():a.health=1000;a.maximum=1000;a.cooldown_remaining=0
    return s
func _initialize()->void:run.call_deferred()
func run()->void:
    var oracle:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/knight_decisions.json"))
    for row in oracle.cases:
        var random:RefCounted=Rolls.new();random.values=row.rolls
        var result:String=Brain.decision(Rules.knight_ai,row,random)
        check(result==row.action and random.calls==row.draws,"independent original68000 choice/draw count "+JSON.stringify(row))
        check(row.cooldown==55,"retail decisions do not impose or consume a cooldown")
    for kind in ["knight","black_knight"]:
        for move in ["swing","heavy","lunge","reverse","dagger","upward"]:
            var s:RefCounted=fresh(kind);var m:RefCounted=s.simulation
            m.actors[10].x=145 if move!="reverse" else 65
            if move=="dagger":m.actors[10].x=210
            if move=="lunge":m.actors[10].x=180
            if move=="upward":m.actors[10].rest_height=-30
            s.command(1,1,Vector2i.ZERO,move)
            var hit_tick:int=-1
            for n in 70:
                m.advance()
                if m.events.any(func(e:Dictionary)->bool:return e.type=="damage" and e.actor==10):hit_tick=m.tick;break
            check(hit_tick>=0,"actual knight hurt "+kind+move)
            var victim:Dictionary=m.actors[10]
            check(victim.stagger_remaining==30 and victim.reaction_remaining==30,"matching full six-hold recovery "+kind+move)
            check(m.AttackFlow.hurt_protected(Rules,victim),"both knight kinds protected during ordinary hurt")
            var animator:RefCounted=Animator.new();var poses:Array=[]
            var expected:Array=Art.animation_for(kind).clips[victim.reaction].frames
            var x:int=victim.x
            for age in 30:
                var before:Dictionary=m.snapshot();animator.update(m.actors,Rules,Art)
                check(before==m.snapshot(),"hurt artwork cannot change readiness or RNG")
                var index:int=animator.poses[10].index
                if poses.is_empty() or poses[-1]!=index:poses.append(index)
                s.command(10,0,Vector2i.RIGHT,"swing");m.advance()
                if age<29:check(victim.remaining==0 and victim.x==x,"held input cannot bypass hurt recovery")
            check(poses==expected,"all hurt drawings finish in source order")
            check(victim.remaining==40 and victim.stagger_remaining==0 and not m.AttackFlow.hurt_protected(Rules,victim),"expiry step permits immediate fresh attack")
    # Ordinary source hurt policy must not leak into distinct victim/impact
    # paths; the existing spear hurt variant keeps its complete36-tick clock.
    for move in ["rat_strike","spear_thrust"]:
        var special:RefCounted=fresh("knight");var sm:RefCounted=special.simulation
        sm.actors[1]=sm.make_actor(1,1,1,"ratman" if move=="rat_strike" else "trogg_spear",Vector2i(100,166),1)
        sm.actors[1].cooldown_remaining=0
        sm.actors[10].x=135 if move=="rat_strike" else 190
        special.command(1,1,Vector2i.ZERO,move)
        for n in 40:
            sm.advance()
            if sm.events.any(func(e:Dictionary)->bool:return e.type=="damage" and e.actor==10):break
        check(sm.actors[10].reaction_remaining==36,"special hurt drawing clock retained "+move)
        check(sm.actors[10].stagger_remaining==(8 if move=="rat_strike" else 36),"commit only the final matching ordinary reaction "+move)
    # Busy actions neither cancel themselves into a guard nor consume random draws.
    var s:RefCounted=fresh();var m:RefCounted=s.simulation;var a:Dictionary=m.actors[10]
    s.command(10,0,Vector2i.ZERO,"heavy");m.advance()
    var seed_before:int=m.knight_random_state
    for n in 40:
        s.advance(Vector2i.ZERO,"swing")
        check(m.knight_random_state==seed_before,"committed attack/hurt cannot draw AI RNG")
        if a.stagger_remaining>0:break
    var lane:RefCounted=fresh();var lm:RefCounted=lane.simulation
    lm.actors[1].y=150
    var lane_seed:int=lm.knight_random_state
    var lane_plan:Dictionary=Brain.choose(lm,lm.actors[10],lm.actors[1])
    check(lane_plan.action=="walk" and lane_plan.direction.y==-1 and lm.knight_random_state==lane_seed,"misaligned lane approaches before attack decisions and RNG")
    for offset in [5,6,7,-5,-6,-7]:
        var alignment:RefCounted=fresh();var am:RefCounted=alignment.simulation
        am.actors[1].y=166+offset
        var started:bool=false
        for n in 90:
            alignment.advance(Vector2i.ZERO,"idle")
            if am.events.any(func(e:Dictionary)->bool:return e.type=="attack" and e.actor==10):started=true;break
        check(started,"decision cadence cannot oscillate past an adjacent lane "+str(offset))
    # Live AI must be reproducible yet vary with encounter seed. Rendering cannot
    # consume the AI stream; all persistent random/decision state is snapshotted.
    var histories:Array=[]
    for seed_value in [12345,12345,987654321]:
        var live:RefCounted=fresh("black_knight",seed_value);var animator:RefCounted=Animator.new();var rows:Array=[]
        for n in 500:
            live.advance(Vector2i.ZERO,"idle")
            var before:Dictionary=live.simulation.snapshot();animator.update(live.simulation.actors,Rules,Art)
            check(before==live.simulation.snapshot(),"live classic layers leave deterministic AI untouched")
            for e in live.simulation.events:
                if e.type=="attack":rows.append([n,e.actor,e.move])
        histories.append(rows)
    check(histories[0]==histories[1] and histories[0]!=histories[2],"same seed replays; different seed changes attack choices")
    check(histories[0].size()>3,"original decisions return to repeated attacks without blanket55 delay")
    check(Rules.actor_definitions.black_knight.attack_cooldown_ticks==0 and Rules.actor_definitions.black_knight.entry_attack_delay_ticks==50,"remove unsupported repeat delay; retain entrance grace")
    var snap:Dictionary=m.snapshot();snap.knight_random_state=0;snap.actors[10].knight_ai.last_action="corrupt"
    check(m.knight_random_state!=0 and a.knight_ai.last_action!="corrupt","snapshot detaches random and decision state")
    check(m.snapshot().schema==25 and m.snapshot().knight_ai_versions=={"classic:knight_ai":{"api":1,"version":1}},"new state is explicit and versioned")
    check(preload("res://debug/fixtures/knight_rhythm_fixture.gd").audit().valid,"mirrored ordinary-input fights finish full recoveries")
    if failures==0:print("PASS: ",checks," knight rhythm checks;1080 executed-original decisions, both full protected hurt paths, six moves, repeated input, seeded live AI and classic layer isolation")
    quit(1 if failures else 0)
