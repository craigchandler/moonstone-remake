extends SceneTree
const Review=preload("res://debug/fixtures/combat_recovery_review.gd")
const Session=preload("res://scripts/session/local_session.gd")
const Rules=preload("res://content/foundation_rules.tres")
const Flow=preload("res://scripts/domain/attack_flow.gd")
var checks:int=0
var failures:int=0
func check(ok:bool,label:String)->void:
    checks+=1
    if not ok:failures+=1;push_error(label)
func fresh(kind:String,distance:int=45)->RefCounted:
    var s:RefCounted=Session.new(Rules);s.start(&"competitive",&"hammer_lair",{"count":1,"concurrent":1})
    s.simulation.actors[1].x=100
    s.simulation.actors[10]=s.simulation.make_actor(10,0,2,kind,Vector2i(100+distance,166),-1)
    s.simulation.actors[10].health=1000;s.simulation.actors[10].maximum=1000
    return s
func _initialize()->void:run.call_deferred()
func run()->void:
    # The last protected step must become an actionable step. Commands can
    # start an attack before this step's simultaneous contact collection.
    for kind in Review.ROSTER+["knight"]:
        var s:RefCounted=fresh(kind,160);var m:RefCounted=s.simulation;var foe:Dictionary=m.actors[10]
        foe.cooldown_remaining=0;foe.stagger_remaining=2;foe.reaction="hurt_a";foe.reaction_remaining=2
        var attack:String=Rules.actor_definitions[kind].allowed_moves[0]
        s.command(10,0,Vector2i.ZERO,attack);m.advance()
        check(foe.stagger_remaining==1 and foe.remaining==0,"penultimate hurt step remains committed "+kind)
        s.command(10,0,Vector2i.ZERO,attack);m.advance()
        check(foe.stagger_remaining==0 and m.events.any(func(e:Dictionary)->bool:return e.type=="attack" and e.actor==10),"expiry step can act before becoming vulnerable "+kind)
    # Actual surviving contact: only the three shared brawlers clear cooldown.
    # Inspect before another tick can decrement it, and retain damage/one hit.
    for kind in Review.ROSTER:
        for move in ["swing","heavy","lunge","reverse","upward","dagger"]:
            var s:RefCounted=fresh(kind,{"reverse":-35,"dagger":110,"lunge":80}.get(move,45));var m:RefCounted=s.simulation;var foe:Dictionary=m.actors[10]
            foe.cooldown_remaining=500
            if move=="dagger" and kind in ["ratman","war_beast"]:m.actors[1].y+=5
            if move=="upward" and kind in ["ratman","war_beast","black_knight","trogg_spear"]:foe.height=-30;foe.rest_height=-30
            s.command(1,1,Vector2i.ZERO,move)
            var contact:bool=false
            for n in 90:
                m.advance()
                if m.events.any(func(e:Dictionary)->bool:return e.type=="damage" and e.actor==10):contact=true;break
            check(contact,"real surviving contact "+kind+" "+move)
            if not contact:continue
            check(foe.health==1000-int(Rules.moves[move].damage),"per-contact damage retained "+kind+" "+move)
            check(foe.cooldown_remaining==0 if kind.begins_with("trogg_") else foe.cooldown_remaining>400,"source-specific cooldown reset "+kind+" "+move)
            if kind=="war_beast":
                check(foe.beast.stage==("hurt_a" if move in ["heavy","upward"] else "hurt_b") and foe.special_duration==(54 if move in ["heavy","upward"] else 42),"dedicated Beast hurt/impact path retained")
            elif Rules.recovery.committed(kind,foe.reaction):
                var duration:int=Rules.recovery.duration(kind,foe.reaction,0)
                check(foe.stagger_remaining==duration and foe.reaction_remaining==duration,"complete source hurt clock "+kind+" "+move)
    # Data is explicit and independent of animation files. In particular, the
    # Troll remains targetable; no invented universal counterattack armour.
    for kind in ["giant_troll"]:
        var s:RefCounted=fresh(kind);var foe:Dictionary=s.simulation.actors[10]
        foe.reaction="hurt_a";foe.stagger_remaining=10
        check(not Flow.hurt_protected(Rules,foe),"source targetability retained "+kind)
    var beast_session:RefCounted=fresh("war_beast")
    var beast:Dictionary=beast_session.simulation.actors[10]
    beast_session.simulation.Beast.hurt(beast,"swing")
    check(Flow.hurt_protected(Rules,beast),"dedicated Beast hurt state is protected")
    beast_session.simulation.Beast.impact(beast)
    check(not Flow.hurt_protected(Rules,beast),"source Beast impact is targetable again")
    check(Rules.recovery.duration("trogg_hammer","hurt_b",0)==25,"Hammer five hurt holds share its five-tick attack cadence")
    check(Rules.recovery.duration("ratman","hurt_b",0)==30 and Rules.recovery.duration("knight_finishes","hop",0)==54,"unchanged generated source clocks fall through")
    for distance in [64,65,66,100,101,120,121]:
        var s:RefCounted=fresh("trogg_hammer",distance);var m:RefCounted=s.simulation;m.actors[10].cooldown_remaining=0
        s.advance(Vector2i.ZERO,"idle")
        var a:Dictionary=m.actors[10]
        check(a.action==("idle" if distance<=65 or distance>120 else ("hammer_swing" if distance<=100 else "hammer_chop")),"Hammer source ordinary/overhead/backoff boundary "+str(distance))
        if distance<=65:check(a.x==100+distance+1,"inclusive source backoff")
    # Every committed generic hurt path retains all original drawings. Rendering
    # each tick cannot shorten a clock or clear the domain protection window.
    for kind in Review.ROSTER:
        if kind=="war_beast":continue
        var animation:Resource=Review.Art.animation_for(kind)
        for clip in animation.clips:
            if not clip.begins_with("hurt") or not Rules.recovery.committed(kind,clip):continue
            var s:RefCounted=fresh(kind,160);var m:RefCounted=s.simulation;var a:Dictionary=m.actors[10]
            var duration:int=Rules.recovery.duration(kind,clip,0)
            a.reaction=clip;a.reaction_remaining=duration;a.reaction_duration=duration;a.stagger_remaining=duration
            var seen:Array=[];var animator:RefCounted=Review.Animator.new()
            for age in duration:
                var before:Dictionary=m.snapshot();animator.update(m.actors,Rules,Review.Art)
                check(m.snapshot()==before,"hurt rendering cannot mutate authority")
                var pose:int=animator.poses[10].index
                if seen.is_empty() or seen[-1]!=pose:seen.append(pose)
                m.advance()
            check(seen==animation.clips[clip].frames,"all original hurt drawings remain visible "+kind+" "+clip)
    # Two recovering brawlers becoming ready together must still reserve one
    # attack slot; expiry cannot bypass the existing group-spacing scheduler.
    var group:RefCounted=fresh("trogg_hammer",70)
    var gm:RefCounted=group.simulation
    gm.actors[11]=gm.make_actor(11,0,2,"trogg_hammer",Vector2i(30,166),1)
    for id in [10,11]:
        gm.actors[id].stagger_remaining=1;gm.actors[id].reaction="hurt_b"
        gm.actors[id].reaction_remaining=1;gm.actors[id].cooldown_remaining=0
    group.advance(Vector2i.ZERO,"idle")
    check(gm.events.filter(func(e:Dictionary)->bool:return e.type=="attack" and e.actor in [10,11]).size()==1,"shared expiry retains group attack reservation")
    var result:Dictionary=Review.audit();checks+=result.checks
    for failure in result.failures:check(false,str(failure))
    for row in result.cases:
        if row.kind=="trogg_hammer" and row.distance in [60,70,90]:
            check(row.events.filter(func(e:Dictionary)->bool:return e.type=="damage" and e.actor==1).size()>=3,"held Z permits repeated Hammer counterattacks "+str(row.distance))
    check(result.cases.size()==110,"all eleven original monsters, five distances, both facings")
    if failures==0:print("PASS: ",checks," recovery/cooldown/spacing checks;110 whole-roster held-input live-AI replays; deterministic state/events and classic-layer isolation")
    quit(1 if failures else 0)
