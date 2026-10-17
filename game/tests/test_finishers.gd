extends SceneTree

const Session=preload("res://scripts/session/local_session.gd")
const Fixture=preload("res://debug/fixtures/finisher_fixture.gd")
const Animator=preload("res://scripts/presentation/actor_animator.gd")
var rules: Resource=preload("res://content/foundation_rules.tres")
var art: Resource=preload("res://content/classic_art.tres")
var failures: int=0

func check(ok: bool, label: String) -> void:
    if not ok: failures+=1;push_error(label)

func _initialize() -> void:
    for name in ["spear","balok_a","balok_b","balok_release","troll","mud_carry","mud_quick","mud_escape","mud_interrupt","guardian_close","guardian_far","guardian_death","dragon_death","hammer_a","hammer_b"]:
        for mirror in [false,true]:
            var session: RefCounted=Session.new(rules)
            var replay: RefCounted=Session.new(rules)
            var fixture: RefCounted=Fixture.new(); fixture.choice=name;fixture.mirror=mirror
            var second: RefCounted=Fixture.new(); second.choice=name;second.mirror=mirror
            var animator: RefCounted=Animator.new()
            for tick in range(fixture.length()):
                fixture.advance(session);second.advance(replay)
                if tick%17==0:
                    check(session.simulation.snapshot()==replay.simulation.snapshot(),"interaction clocks replay: "+name)
                    var before: Dictionary=session.simulation.snapshot()
                    animator.update(session.simulation.actors,rules,art)
                    check(before==session.simulation.snapshot(),"art cannot mutate finishes: "+name)
                    for id in animator.poses:
                        var a: Dictionary=session.simulation.actors[id]
                        var family: String=a.kind if a.visual_kind.is_empty() else a.visual_kind
                        check(art.animation_for(family).clips.has(animator.poses[id].clip),"no idle fallback in a finish: "+name+"/"+animator.poses[id].clip)
                var foe: Dictionary=session.simulation.actors[10]
                var victim: Dictionary=session.simulation.actors[1]
                if victim.health<=0 and victim.hidden_by!=0:
                    check(victim.down_remaining>0,"results wait for the full composite: "+name)
                if name=="balok_release":check(victim.health in [10,5],"Balok shaking does not invent extra damage")
                if name.begins_with("guardian") and foe.special_clip.begins_with("release"):
                    check(victim.hidden_by==0 and victim.grab_remaining==0,"Guardian release shows the independent knight immediately")
            check(fixture.verify(session),"native contact/finish/end boundary: "+name+" facing "+str(mirror))
            if name in ["balok_a","balok_b"]:
                check(session.simulation.actors[1].visual_kind=="balok_finishes" and session.simulation.actors[1].down_remaining==0,"Balok leaves independent original victim remains")
                animator.update(session.simulation.actors,rules,art)
                check(animator.poses[1].index==art.animation_for("balok_finishes").clips["remains_a" if name=="balok_a" else "remains_b"].frames[-1],"Balok original remains show the final pose, not the airborne opening")
    # The carry decrements before input: the final tick is already too late.
    for escape_at in [238,239,240]:
        var session: RefCounted=Session.new(rules)
        session.start(&"cooperative",&"mud_lair",{"count":1,"concurrent":1})
        var model: RefCounted=session.simulation
        var mud: Dictionary=model.actors[10]
        mud.interaction={};mud.visual_kind=""
        model.Finishers.begin(model,mud,model.actors[1],"mud")
        for tick in range(escape_at):model.advance()
        session.command(1,1,Vector2i.DOWN,"block");model.advance()
        check(model.actors[1].health>0 if escape_at==238 else model.actors[1].health==0,"Mudman escape/expiry boundary")
    # Another knight can interrupt a holder through ordinary sword damage.
    var session: RefCounted=Session.new(rules)
    session.start(&"cooperative",&"balok_lair",{"count":1,"concurrent":1})
    var model: RefCounted=session.simulation
    model.actors[10].x=160;model.actors[2].x=120;model.actors[2].facing=1
    model.Finishers.begin(model,model.actors[10],model.actors[1],"balok")
    session.command(2,0,Vector2i.ZERO,"lunge")
    for tick in range(35):model.advance()
    check(model.actors[1].hidden_by==0 and model.actors[1].health>0,"co-op sword rescue releases the living victim")
    var snapshot: Dictionary=model.snapshot();snapshot.actors[10].interaction.test="changed"
    check(not model.actors[10].interaction.has("test"),"snapshot deeply isolates interaction state")
    if failures==0:print("PASS: real contacts in both facings, fifteen finishes/deaths/interruptions, native replay and art isolation, living Balok release without drain, Mudman pre-expiry escape/final-tick swallow and emergence sword counter, co-op rescue, composite result waits and snapshot isolation")
    quit(1 if failures else 0)
