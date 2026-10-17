extends SceneTree
const Model=preload("res://scripts/domain/combat_simulation.gd")
const Session=preload("res://scripts/session/local_session.gd")
const Animator=preload("res://scripts/presentation/actor_animator.gd")
var rules:Resource=preload("res://content/foundation_rules.tres")
var art:Resource=preload("res://content/classic_art.tres")
var failures:int=0
func check(ok:bool,label:String)->void:
    if not ok:failures+=1;push_error(label)
func fresh(encounter:String)->RefCounted:
    var m:RefCounted=Model.new(rules)
    m.start(&"competitive",0,StringName(encounter),{"count":1,"concurrent":1})
    m.actors[10].cooldown_remaining=0
    m.actors[1].health=1000;m.actors[1].maximum=1000
    return m
func attack(m:RefCounted,move:String,facing:int=1)->void:
    check(m.submit(0,{"actor":10,"sequence":m.tick+1,"tick":m.tick,"dx":0,"dy":0,"action":move,"facing":facing}),"accepted "+move)
    m.advance()
func _initialize()->void:
    # Stream reaches the far side; a committed lane can be evaded. A guard
    # alone cannot stop it. No extra orange projectile is created.
    for lane in [166,139]:
        var m:RefCounted=fresh("dragon_fight")
        m.actors[1].x=245;m.actors[1].y=lane;m.actors[10].x=75
        attack(m,"dragon_claw")
        var animator:RefCounted=Animator.new()
        var saw:bool=false
        for n in range(110):
            m.advance();animator.update(m.actors,rules,art)
            for e in m.events:
                if e.type=="damage":
                    saw=true
                    check(animator.poses[10].clip=="dragon_claw" and animator.poses[10].phase=="active","stream contacts align with visible fire")
            check(m.projectiles.is_empty(),"low fire is the original stream, not another projectile")
        check(saw==(lane==166),"far stream hits its lane and misses a sidestep")
    # Two opposite transitions retain their height and never cross the arena.
    var m:RefCounted=fresh("dragon_fight")
    m.actors[1].x=150
    attack(m,"dragon_flight")
    for n in range(78):m.advance();check(m.actors[10].x<=100,"neck rearing stays left")
    check(m.actors[10].height==-70 and m.actors[10].dragon_raised,"raised neck persists")
    m.advance();check(m.actors[10].height==-70,"idle does not drop the raised neck")
    m.actors[10].cooldown_remaining=0;attack(m,"dragon_lower")
    for n in range(54):m.advance()
    check(m.actors[10].height==-30 and not m.actors[10].dragon_raised,"lowered neck persists")
    # Downward fire is a stationary original-CEL object, with per-pose contact
    # points, a finite lifetime and one hit per victim.
    m=fresh("dragon_fight");m.actors[1].x=250;m.actors[1].y=139
    attack(m,"dragon_breath")
    for n in range(7):m.advance()
    check(m.projectiles.size()==1 and m.projectiles[0].kind=="dragon_fire","downward breath creates original fire object")
    var origin:int=m.projectiles[0].x
    for n in range(12):m.advance()
    check(m.projectiles[0].x==origin,"ground fire does not fly like a dagger")
    for n in range(150):m.advance()
    check(m.projectiles.is_empty(),"ground fire expires")
    # Both flight directions curl/spin and give a defender an escape window.
    for facing in [1,-1]:
        m=fresh("rat_lair");m.actors[10].x=40 if facing==1 else 280
        # Ground flight: another Ratman already owns the single tree slot.
        m.rat_perch.owner=99
        m.actors[1].x=160
        attack(m,"rat_leap",facing)
        var lowest:int=0
        var saw_hold:bool=false
        for n in range(110):
            m.advance();lowest=mini(lowest,m.actors[10].height)
            if m.actors[1].grab_remaining>0:saw_hold=true;break
        check(lowest < -55,"Ratman curls into a high flight arc")
        check(saw_hold,"flight makes contact in both directions")
        if saw_hold:
            check(m.submit(1,{"actor":1,"sequence":m.tick+1,"tick":m.tick,"dx":0,"dy":1,"action":"block"}),"escape accepted")
            m.advance()
            var holder_hp: int=m.actors[10].health
            check(m.actors[1].grab_remaining==0 and m.actors[1].hidden_by==10 and m.actors[1].health==1000 and m.actors[10].special_clip=="rat_escape","guard+down plays the owned shake-off composite without victim damage")
            for tick in range(30):m.advance()
            check(m.actors[1].hidden_by==0 and m.actors[10].health==holder_hp,"shake-off frees the knight without damaging the Ratman")
    # A live co-op ally can rescue the held knight. Squeeze and ride have
    # distinct consequences and their composite poses end before results.
    m=fresh("rat_lair");m.start_rat_hold(m.actors[10],m.actors[1],"squeeze",600)
    for n in range(60):m.advance()
    check(m.actors[1].health<1000 and m.actors[1].grab_remaining>0,"squeeze drains over time")
    m.knock_down(m.actors[10],"defeat")
    m.actors[10].health=0;m.advance()
    check(m.actors[1].grab_remaining==0 and m.actors[1].hidden_by==0,"killing holder releases victim")
    m=fresh("rat_lair");m.actors[1].x=120
    m.start_rat_hold(m.actors[10],m.actors[1],"ride",2)
    m.advance();m.advance()
    check(m.actors[1].health==995 and m.actors[1].hidden_by==0 and m.actors[10].special_clip=="rat_air","nonlethal ride releases a living knight, without execution art")
    for n in range(102):m.advance()
    check(m.actors[10].x>=260 and m.actors[10].cooldown_remaining>0,"Ratman retreats before attacking again")
    m=fresh("rat_lair");m.actors[1].health=5
    m.start_rat_hold(m.actors[10],m.actors[1],"ride",2)
    m.advance();m.advance()
    check(m.actors[1].health==0 and m.actors[10].special_clip=="rat_throw_finish" and m.actors[1].down_remaining>0,"ride execution waits for composite finish")
    m=fresh("rat_lair");m.actors[1].health=1
    m.actors[2]=m.make_actor(2,2,1,"knight",Vector2i(250,166),-1)
    m.start_rat_hold(m.actors[10],m.actors[1],"squeeze",600)
    for n in range(150):m.advance()
    check(not m.actors[10].terminal_clip.is_empty(),"hanging finish keeps its terminal art")
    m.actors[10].cooldown_remaining=0;attack(m,"rat_leap")
    check(m.actors[10].rest_height==0 and m.actors[10].terminal_clip.is_empty(),"holder resumes on ground against surviving co-op knight")
    m=fresh("dragon_fight");m.actors[1].health=0;m.knock_down(m.actors[1],"defeat")
    m.dragon_finish(m.actors[10],m.actors[1],"dragon_bite")
    check(m.actors[1].hidden_by==10 and m.actors[10].special_remaining==312,"bite uses original long finish")
    m=fresh("dragon_fight");m.actors[1].health=0;m.knock_down(m.actors[1],"defeat")
    m.dragon_finish(m.actors[10],m.actors[1],"dragon_claw")
    var animator:RefCounted=Animator.new();animator.update(m.actors,rules,art)
    check(m.actors[1].visual_kind=="dragon_victim" and animator.poses[1].clip=="burn","fire death selects original burning knight")
    # Replay includes all special clocks; renderer/clean variants do not mutate it.
    for encounter in ["dragon_fight","rat_lair"]:
        var a:RefCounted=Session.new(rules);a.start(&"cooperative",StringName(encounter))
        var b:RefCounted=Session.new(rules);b.start(&"cooperative",StringName(encounter))
        for n in range(650):
            a.advance(Vector2i.ZERO,"idle");b.advance(Vector2i.ZERO,"idle")
            check(a.simulation.snapshot()==b.simulation.snapshot(),"special combat replay")
        var snap:Dictionary=a.simulation.snapshot();animator.update(a.simulation.actors,rules,art)
        check(snap==a.simulation.snapshot(),"render isolation")
    if failures==0:print("PASS: original fire contacts, lane evasion, stationary flames, neck phases, both Ratman flights, hold counter/rescue, distinct execution clocks and co-op replay")
    quit(1 if failures else 0)
