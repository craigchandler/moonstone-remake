extends SceneTree
const Session=preload("res://scripts/session/local_session.gd")
const Fixture=preload("res://debug/fixtures/beast_review_fixture.gd")
const Animator=preload("res://scripts/presentation/actor_animator.gd")
const Scheduler=preload("res://scripts/presentation/combat_sound_cues.gd")
var rules:Resource=preload("res://content/foundation_rules.tres")
var art:Resource=preload("res://content/classic_art.tres")
var pack:Resource=preload("res://assets/classic/audio/sounds.tres")
var failures:int=0
func check(ok:bool,label:String)->void:
    if not ok:failures+=1;push_error(label)
func _initialize():
    var clips:Dictionary=art.animation_for("war_beast").clips
    for key in ["defeat_a","defeat","defeat_b"]:
        check(clips[key].frames.size()==12,"full hit prefix and resolved collapse have12 poses: "+key)
    check(clips.impact_same.frames.size()==4 and clips.impact_opposite.frames.size()==4,"both knight knockdowns include landing/recovery")
    check(clips.ejected.frames.size()==8,"ejected knight includes frame-set switch and terminal collapse")
    for name in ["beast_die_chop","beast_die_swing","beast_hit","beast_hit_rear","beast_same"]:
        for mirror in [false,true]:
            var session:RefCounted=Session.new(rules)
            var fixture:RefCounted=Fixture.new();fixture.choice=name;fixture.mirror=mirror
            var animator:RefCounted=Animator.new();var scheduler:RefCounted=Scheduler.new()
            var visited:Array=[];var seen_sound:Dictionary={};var clip:String=""
            for n in range(fixture.length()):
                fixture.advance(session)
                var sim:RefCounted=session.simulation
                var before:Dictionary=sim.snapshot()
                animator.update(sim.actors,rules,art)
                var sound:Dictionary=scheduler.collect(sim,animator.poses,art,pack)
                for cue in sound.cues:seen_sound[cue.key]=true
                check(sim.snapshot()==before,"frame/audio playback cannot change mechanics")
                var id:int=10 if name.begins_with("beast_die_") else 1
                var actor:Dictionary=sim.actors[id];var pose:Dictionary=animator.poses[id]
                var wanted:bool=(id==10 and actor.health==0) or (id==1 and actor.visual_kind=="war_beast" and actor.hidden_by==0)
                if wanted:
                    clip=pose.clip
                    if not pose.index in visited:visited.append(pose.index)
            var expected:String="defeat_a" if name=="beast_die_chop" else ("defeat" if name=="beast_die_swing" else ("ejected" if name=="beast_same" else ("impact_same" if name=="beast_hit_rear" else "impact_opposite")))
            check(visited==clips[expected].frames,"every recovered visible pose renders in source order, no skipped hit/death frames: "+name+str(mirror))
            check(not seen_sound.is_empty(),"restored path has native sound cues")
            check(fixture.verify(session),"real-contact result: "+name)
    if failures==0:print("PASS: every restored beast hit/collapse and knight fall/landing/recovery/death pose renders in order in both facings, with native sounds and isolated rules")
    quit(1 if failures else 0)
