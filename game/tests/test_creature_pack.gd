extends SceneTree

const Model=preload("res://scripts/domain/combat_simulation.gd")
const Session=preload("res://scripts/session/local_session.gd")
const Animator=preload("res://scripts/presentation/actor_animator.gd")
var rules: Resource=preload("res://content/foundation_rules.tres")
var art: Resource=preload("res://content/classic_art.tres")
var failures: int=0
var additions: Array[String]=["hammer_lair","beast_lair","rat_lair","mud_lair","dragon_fight","guardian_fight","black_knight_fight"]

func check(ok: bool,label: String) -> void:
    if not ok:
        failures+=1
        push_error(label)

func session_for(encounter: String, protection: int=0) -> RefCounted:
    var session: RefCounted=Session.new(rules)
    session.knight_profile={"health":1000,"maximum":1000,"dragon_damage_shift":protection}
    session.start(&"competitive",StringName(encounter),{"count":1,"concurrent":1})
    return session

func _initialize() -> void:
    for encounter in additions:
        print("CHECKING: ",encounter)
        var kind: String=rules.encounters[encounter].creature
        var animation: Resource=art.animation_for(kind)
        check(animation!=null and animation.atlas_for("purple")!=null and animation.atlas_for("purple_clean")!=null,"native art and clean variants: "+kind)
        for clip in ["idle","walk","walk_away","walk_toward","hurt_a","hurt_b","defeat"]:
            check(animation.clips.has(clip) and not animation.sample(clip,0).is_empty(),"complete baseline clip: "+kind+"/"+clip)
        for move in rules.actor_definitions[kind].allowed_moves:
            check(animation.clips.has(move),"original named attack poses: "+kind+"/"+move)
        var live: RefCounted=session_for(encounter)
        var replay: RefCounted=session_for(encounter)
        var seen: Dictionary={}
        var animator: RefCounted=Animator.new()
        var initial: int=live.simulation.actors[1].health
        for step in range(850):
            live.advance(Vector2i.ZERO,"idle")
            replay.advance(Vector2i.ZERO,"idle")
            if step%25==0: check(live.simulation.snapshot()==replay.simulation.snapshot(),"all authoritative AI clocks replay: "+encounter)
            for event in live.simulation.events:
                if event.type=="attack": seen[event.move]=true
            if step%20==0:
                var before: Dictionary=live.simulation.snapshot()
                animator.update(live.simulation.actors,rules,art)
                check(live.simulation.snapshot()==before and animator.poses.has(10),"rendering has no rule effects: "+kind)
        check(not seen.is_empty(),"live AI attacks: "+kind)
        check(live.simulation.actors[1].health<initial,"live attacks reach a normal stationary knight: "+kind)
        var co_op: RefCounted=Session.new(rules)
        co_op.start(&"cooperative",StringName(encounter),{"count":3,"concurrent":2})
        check(co_op.simulation.actors.has(2) and co_op.simulation.actors[2].team==1 and co_op.simulation.spawn_remaining==1,"co-op and wave overrides: "+kind)
    # Explicit escape/expiry transitions, including a holder dying mid-grab.
    for encounter in ["mud_lair","rat_lair"]:
        var session: RefCounted=session_for(encounter)
        var model: RefCounted=session.simulation
        model.actors[1].grabbed_by=10
        model.actors[1].grab_remaining=3
        if encounter=="mud_lair":
            model.actors[10].interaction={}
            model.Finishers.begin(model,model.actors[10],model.actors[1],"mud")
        session.advance(Vector2i.DOWN,"block")
        check(model.actors[1].health==1000 and (model.actors[1].grab_remaining==0 or (encounter=="mud_lair" and model.actors[10].special_clip=="release")),"guard+down begins release without damage: "+encounter)
        # A Ratman counter can kill the holder. Use a living fresh opponent for expiry.
        session=session_for(encounter)
        model=session.simulation
        if encounter=="rat_lair": model.actors[10].hold_kind="ride"
        model.actors[1].grabbed_by=10
        model.actors[1].grab_remaining=1
        if encounter=="mud_lair":
            model.actors[10].interaction={}
            model.Finishers.begin(model,model.actors[10],model.actors[1],"mud")
            model.actors[10].interaction.duration=1
        session.advance(Vector2i.ZERO,"idle")
        check(model.actors[1].health==(0 if encounter=="mud_lair" else 995),"unescaped hold has its distinct consequence: "+encounter)
        session=session_for(encounter)
        model=session.simulation
        model.actors[1].grabbed_by=10
        model.actors[1].grab_remaining=30
        model.actors[10].health=0
        session.advance(Vector2i.ZERO,"idle")
        check(model.actors[1].grab_remaining==0,"dead holder releases target: "+encounter)
    var unprotected: RefCounted=session_for("dragon_fight")
    var protected: RefCounted=session_for("dragon_fight",1)
    for session in [unprotected,protected]:
        session.simulation.actors[1].x=245
        for step in range(600): session.advance(Vector2i.ZERO,"block")
    var base_loss: int=1000-unprotected.simulation.actors[1].health
    var protected_loss: int=1000-protected.simulation.actors[1].health
    check(base_loss>0 and base_loss==protected_loss*2,"carried talisman halves actual dragon fire through guard")
    var rival: RefCounted=session_for("black_knight_fight")
    rival.simulation.actors[1].y=139
    for step in range(520): rival.advance(Vector2i.ZERO,"idle")
    check(rival.simulation.actors[10].damage_bonus==0 and rival.simulation.actors[10].maximum==20,"Black Knight retains its entry stats; no invented combat-time growth")
    if failures==0: print("PASS: seven native creature types, attack/clean art, live AI damage, deterministic replay, render isolation, co-op/waves, hold escape/expiry/dead holder, actual dragon talisman protection and stable rival stats")
    quit(1 if failures else 0)
