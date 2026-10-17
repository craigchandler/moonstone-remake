extends SceneTree
const Session=preload("res://scripts/session/local_session.gd")
const Fixture=preload("res://debug/fixtures/guardian_fixture.gd")
const Animator=preload("res://scripts/presentation/actor_animator.gd")
const Scheduler=preload("res://scripts/presentation/combat_sound_cues.gd")
var rules:Resource=preload("res://content/foundation_rules.tres")
var art:Resource=preload("res://content/classic_art.tres")
var sound:Resource=preload("res://assets/classic/audio/sounds.tres")
var failures:int=0
func check(ok:bool,label:String)->void:
    if not ok:failures+=1;push_error(label)
func _initialize()->void:run.call_deferred()
func run()->void:
    for kind in ["close","far","overlap","miss_low","escape","depth","double","crush","crush_dead","crush_zero","rescue_close","rescue_far","rescue_crush","rescue_dead","interrupt","late_hit"]:
        for mirror in [false,true]:
            var session:RefCounted=Session.new(rules);var replay:RefCounted=Session.new(rules)
            var fixture:RefCounted=Fixture.new();fixture.choice="guard_"+kind;fixture.mirror=mirror
            var other:RefCounted=Fixture.new();other.choice=fixture.choice;other.mirror=mirror
            var animator:RefCounted=Animator.new();var scheduler:RefCounted=Scheduler.new();var poses:Dictionary={};var cues:Dictionary={}
            for n in fixture.length():
                fixture.advance(session);other.advance(replay)
                var sim:RefCounted=session.simulation;var before:Dictionary=sim.snapshot()
                animator.update(sim.actors,rules,art)
                for cue in scheduler.collect(sim,animator.poses,art,sound).cues:cues[cue.key]=int(cues.get(cue.key,0))+1
                check(sim.snapshot()==before and sim.snapshot()==replay.simulation.snapshot(),"Guardian replay/art/sound isolation "+kind)
                var holder:Dictionary=sim.actors[10];var victim:Dictionary=sim.actors[1]
                if not holder.interaction.is_empty():
                    var phase:String=holder.interaction.stage;var index:int=animator.poses[10].index
                    if not poses.has(phase):poses[phase]=[]
                    if poses[phase].is_empty() or poses[phase][-1]!=index:poses[phase].append(index)
                if victim.hidden_by==10:
                    check(victim.grabbed_by==10 and victim.grab_remaining>0 and victim.motion.is_empty(),"held knight has one owner and no independent hop")
                    if victim.health<=0:check(victim.down_remaining>0,"lethal crush cannot skip the pending release")
            check(fixture.verify(session),"source Guardian stages and consequences "+kind+str(mirror))
            if kind in ["crush","crush_dead","crush_zero"]:
                for key in ["guardian_072","guardian_073","guardian_078"]:check(cues.get(key,0)==1,"crush callback does not replay opening sounds "+key)
            if kind in ["close","far","crush","crush_dead","miss_low"]:
                for phase in poses:check(poses[phase]==art.animation_for("guardian_finishes").clips[phase].frames,"every original Guardian drawing displays once in stage order "+kind+"/"+phase)
    # Both windows are inclusive and distinct despite their overlap. Test the
    # actual gate operation rather than substituting a135px split.
    for far in [false,true]:
        for distance in [119,120,129,130,135,140,141,150,151]:
            var session:RefCounted=Session.new(rules);session.start(&"competitive",&"guardian_fight",{"count":1,"concurrent":1})
            var sim:RefCounted=session.simulation;var holder:Dictionary=sim.actors[10];var victim:Dictionary=sim.actors[1]
            holder.x=60;victim.x=60+distance
            sim.Guardian.gate(sim,holder,victim,far)
            check((victim.hidden_by==10)==(distance>=130 and distance<=150 if far else distance>=120 and distance<=140),"source inclusive capture window "+str(far)+"/"+str(distance))
    # A pending crush may not steal another creature's newly acquired target.
    var session:RefCounted=Session.new(rules);var fixture:RefCounted=Fixture.new();fixture.choice="guard_crush"
    for n in 5:fixture.advance(session)
    var sim:RefCounted=session.simulation;var victim:Dictionary=sim.actors[1]
    sim.actors[20]=sim.make_actor(20,0,2,"ratman",Vector2i(victim.x,victim.y),-1)
    sim.start_rat_hold(sim.actors[20],victim,"ride",90)
    for n in 10:sim.advance()
    check(victim.hidden_by==20 and victim.grabbed_by==20 and victim.health==20 and sim.actors[10].interaction.is_empty(),"Guardian abort preserves an independently owned Ratman hold")
    check(rules.moves.guardian_grab.no_contact and rules.moves.guardian_strike.no_contact,"unarmed source drawings never use the prototype reach fallback")
    if failures==0:print("PASS:32 Guardian command replays, exact close/far and crush callback schedules, all weighted poses, damage/control/death waits, inclusive overlapping gates, horizontal escape, depth quirk, repeated edge capture, real co-op interruption and independent hold ownership")
    quit(1 if failures else 0)
