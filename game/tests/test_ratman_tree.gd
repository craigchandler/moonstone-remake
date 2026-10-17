extends SceneTree
const Model=preload("res://scripts/domain/combat_simulation.gd")
const Animator=preload("res://scripts/presentation/actor_animator.gd")
const Cues=preload("res://scripts/presentation/combat_sound_cues.gd")
var rules: Resource=preload("res://content/foundation_rules.tres")
var art: Resource=preload("res://content/classic_art.tres")
var pack: Resource=preload("res://assets/classic/audio/sounds.tres")
var failures: int=0
func check(ok: bool,label: String) -> void:
    if not ok:failures+=1;push_error(label)
func fresh() -> RefCounted:
    var m: RefCounted=Model.new(rules);m.start(&"cooperative",0,&"rat_lair",{"count":2,"concurrent":2})
    m.actors[10].cooldown_remaining=0;m.actors[11].cooldown_remaining=9999
    m.actors[1].x=280;m.actors[1].y=177;m.actors[1].health=100;m.actors[1].maximum=100
    m.actors[2].x=20;m.actors[2].y=177
    return m
func escape(m: RefCounted,pressed: bool) -> void:
    if pressed:m.submit(1,{"actor":1,"sequence":m.tick+1,"tick":m.tick,"dx":0,"dy":1,"action":"block"})
    m.advance()
func _initialize() -> void:
    var anim: RefCounted=Animator.new()
    for facing in [-1,1]:
        var m: RefCounted=fresh();m.actors[10].x=370 if facing<0 else -50
        m.submit(0,{"actor":10,"sequence":1,"tick":0,"dx":0,"dy":0,"action":"rat_leap","facing":facing})
        for tick in range(100):m.advance()
        var first: int=-1
        for tick in range(20):
            m.advance();anim.update(m.actors,rules,art)
            check(not m.actors[10].rat_perch_near,"far perch is authoritative")
            if first<0:first=anim.poses[10].index
            check(anim.poses[10].index==first,"stationary far perch does not alternate")
        m.actors[1].x=205
        for tick in range(20):
            m.advance();anim.update(m.actors,rules,art)
            check(m.actors[10].rat_perch_near and anim.poses[10].index!=first,"near perch selected by source distance threshold")
        m.actors[1].x=160;m.actors[1].y=157;m.advance()
        check(m.actors[1].grabbed_by==10,"real rope capture in either facing")
        m.actors[10].health=13;m.actors[10].maximum=13
        var found: Dictionary={};var changes: Array=[];var sounds: RefCounted=Cues.new()
        for tick in range(100):
            var hp: int=m.actors[10].health
            escape(m,true);anim.update(m.actors,rules,art)
            var batch: Dictionary=sounds.collect(m,anim.poses,art,pack)
            check(sounds.collect(m,anim.poses,art,pack).cues.is_empty(),"second render cannot double cues")
            if hp!=m.actors[10].health:changes.append(m.actors[10].health)
            if m.actors[10].health>0:
                check(m.actors[1].hidden_by==10 and m.rat_perch.owner==10 and m.actors[10].rest_height==-98,"surviving counter retains victim and fixed tree")
                if anim.poses[10].clip=="rat_squeeze_hit":found[anim.poses[10].index]=true
            if m.actors[10].health==0:break
        check(changes==[8,3,0],"three full sword counters, no every-tick damage")
        check(found.size()==3,"all counterattack drawings appear before repeat")
        check(m.actors[1].health==100 and m.actors[1].hidden_by==0 and m.actors[1].grab_remaining==0 and m.rat_perch.owner==0,"living victim released only on holder death")
        check(m.actors[10].visual_kind=="ratman" and m.actors[10].defeat_clip=="rat_release" and m.actors[10].rest_height==-98,"lethal counter uses elevated source release, without ground teleport")
        for tick in range(18):m.advance()
        check(m.actors[10].down_remaining==0 and m.actors[10].rest_height==-98,"finite release settles at its original placement")
    var m: RefCounted=fresh();m.start_rat_hold(m.actors[10],m.actors[1],"squeeze",600)
    m.actors[10].health=1000;m.actors[10].maximum=1000
    for tick in range(29):escape(m,false)
    check(m.actors[1].health==100,"intro has no early squeeze damage")
    escape(m,false);check(m.actors[1].health==99,"first idle squeeze at intro boundary")
    for tick in range(12):escape(m,false)
    check(m.actors[1].health==98,"one idle damage per full twelve-tick loop")
    for tick in range(700):escape(m,true)
    check(m.actors[1].hidden_by==10 and m.actors[10].health>0,"squeeze has no fabricated600tick release")
    # An ordinary co-op kill frees a victim without resurrection/second counter.
    m.actors[10].health=0;m.knock_down(m.actors[10],"defeat");m.advance()
    check(m.actors[1].hidden_by==0 and m.actors[1].grab_remaining==0,"ally kill releases holder reservation")
    var session: RefCounted=preload("res://scripts/session/local_session.gd").new(rules)
    var fixture: RefCounted=preload("res://debug/fixtures/ratman_tree_fixture.gd").new()
    session.start(&"competitive",&"rat_lair")
    for tick in range(fixture.length()):fixture.advance(session)
    check(fixture.verify(),"complete playable-command fixture")
    var snap: Dictionary=session.simulation.snapshot();anim.update(session.simulation.actors,rules,art)
    check(session.simulation.snapshot()==snap,"animation cannot mutate corrected hold")
    check(snap.schema==22 and snap.content=="encounters.v27","new replay clock versions combat only")
    if failures==0:print("PASS: both-facing real tree route/contact, stable near/far perch, repeated full counter drawings/cadence, retained hold/tree, lethal elevated release, cue deduplication, idle drain/timeout, co-op rescue and render isolation")
    quit(1 if failures else 0)
