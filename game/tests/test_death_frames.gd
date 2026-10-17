extends SceneTree
const Session=preload("res://scripts/session/local_session.gd")
const Fixture=preload("res://debug/fixtures/finisher_fixture.gd")
const Animator=preload("res://scripts/presentation/actor_animator.gd")
const Scheduler=preload("res://scripts/presentation/combat_sound_cues.gd")
const DeathFixture=preload("res://debug/fixtures/death_review_fixture.gd")
var rules:Resource=preload("res://content/foundation_rules.tres")
var art:Resource=preload("res://content/classic_art.tres")
var sounds:Resource=preload("res://assets/classic/audio/sounds.tres")
var failures:int=0
func check(ok:bool,label:String)->void:
    if not ok:failures+=1;push_error(label)
func _initialize()->void:
    run.call_deferred()
func run()->void:
    for family in ["ratman","dragon"]:
        var base:Resource=art.animation_for(family)
        check(base.clips.idle.frames.size()==1 and base.clips.walk.frames.size()==4,"death imports preserve original idle and walk drawings "+family)
    check(art.animation_for("ratman").clips.hurt_a.frames.size()==4 and art.animation_for("dragon").clips.hurt_a.frames.size()==1,"death imports preserve living hurt reactions")
    var encs:Dictionary={"trogg_spear":"spear_lair","trogg_axe":"axe_lair","trogg_hammer":"hammer_lair","giant_troll":"troll_lair","balok":"balok_lair","ratman":"rat_lair","mudman":"mud_lair","dragon":"dragon_fight","guardian":"guardian_fight","black_knight":"black_knight_fight","knight":"duel"}
    var paths:int=0
    for kind in encs:
        var family:String="death_"+("knight" if kind=="black_knight" else kind)
        var animation:Resource=art.animation_for(family)
        for clip in rules.death_frames.clocks[family]:
            for mirror in [false,true]:
                var session:RefCounted=Session.new(rules);session.start(&"competitive",StringName(encs[kind]),{"count":1,"concurrent":1})
                var sim:RefCounted=session.simulation
                var actor:Dictionary=sim.actors[1 if kind=="knight" else 10]
                actor.health=0;actor.facing=-1 if mirror else 1
                sim.knock_down(actor,clip)
                var animator:RefCounted=Animator.new();var visited:Array=[]
                for age in range(actor.down_duration+1):
                    animator.update(sim.actors,rules,art)
                    var pose:Dictionary=animator.poses[actor.id]
                    if visited.is_empty() or visited[-1]!=pose.index:visited.append(pose.index)
                    check(not pose.is_empty() and pose.clip==clip,"death has no idle fallback "+kind+clip)
                    sim.advance()
                check(visited==animation.clips[clip].frames,"every own-death cel in source order "+kind+clip)
                check(actor.vanished if kind=="guardian" else not actor.vanished,"correct vanish/remains "+kind)
                paths+=1
    # All source poses of the long composites must display in ongoing co-op;
    # solo can end during the repeating final section after the source death delay.
    for name in ["spear","balok_a","balok_b","troll","mud_carry","mud_quick","guardian_close","guardian_far","dragon_death","guardian_death","hammer_a","hammer_b"]:
        for mirror in [false,true]:
            var session:RefCounted=Session.new(rules);var fixture:RefCounted=Fixture.new();fixture.choice=name;fixture.mirror=mirror
            var animator:RefCounted=Animator.new();var scheduler:RefCounted=Scheduler.new();var seen:Dictionary={}
            var total:int=1950 if name=="balok_b" else (1100 if name=="spear" else 900)
            for n in total:
                fixture.advance(session)
                var sim:RefCounted=session.simulation;sim.mode=&"cooperative"
                animator.update(sim.actors,rules,art)
                var before:Dictionary=sim.snapshot();scheduler.collect(sim,animator.poses,art,sounds)
                check(before==sim.snapshot(),"death/audio presentation cannot alter simulation")
                for id in animator.poses:
                    var actor:Dictionary=sim.actors[id]
                    if actor.hidden_by!=0:continue
                    var pose:Dictionary=animator.poses[id]
                    var key:String=actor.visual_kind+":"+pose.clip
                    if not seen.has(key):seen[key]=[]
                    if seen[key].is_empty() or seen[key][-1]!=pose.index:seen[key].append(pose.index)
            var clip:String="impale" if name=="spear" else ("eat_a" if name=="balok_a" else "eat_b")
            if name in ["spear","balok_a","balok_b"]:
                var family:String="spear_finishes" if name=="spear" else "balok_finishes"
                check(seen.get(family+":"+clip,[])==art.animation_for(family).clips[clip].frames,"complete repeat section is visible "+name+str(mirror))
            check(fixture.verify(session),"full composite finishes and releases its links "+name)
    check(rules.actor_definitions.trogg_hammer.defeat_clips.dagger=="defeat_a" and rules.actor_definitions.trogg_hammer.defeat_clips.lunge=="defeat_guts","hammer original dagger and thrust branches")
    check(rules.actor_definitions.ratman.defeat_clips.swing=="defeat_swing" and rules.actor_definitions.ratman.defeat_clips.heavy=="defeat_heavy","rat original swing and overhead branches")
    for name in ["audit_rat_victim~strike","audit_rat_victim~bite","audit_rat_throw~defeat","audit_rat_squeeze~defeat","audit_burn~burn","audit_bite~defeat","audit_guardian_kill~defeat"]:
        for mirror in [false,true]:
            var session:RefCounted=Session.new(rules);var fixture:RefCounted=DeathFixture.new();fixture.choice=name;fixture.mirror=mirror
            var animator:RefCounted=Animator.new();var visited:Array=[]
            for n in (2500 if name=="audit_burn~burn" else 450):
                fixture.advance(session)
                if name=="audit_burn~burn":session.simulation.actors[1].down_stop=0
                animator.update(session.simulation.actors,rules,art)
                var actor:Dictionary=session.simulation.actors[1];var pose:Dictionary=animator.poses[1]
                if actor.hidden_by==0 and (name.begins_with("audit_rat_victim") or name=="audit_burn~burn"):
                    if visited.is_empty() or visited[-1]!=pose.index:visited.append(pose.index)
            if name.begins_with("audit_rat_victim"):
                check(visited==art.animation_for("death_rat_victim").clips["strike" if name.ends_with("strike") else "bite"].frames,"Ratman victim includes knight frame-list tail "+name)
            if name=="audit_burn~burn":check(visited==art.animation_for("dragon_victim").clips.burn.frames,"all100 final flame cycles display without compression")
            check(fixture.verify(session),"player kill/remains/consumption "+name+str(mirror))
    for enc in ["dragon_fight","beast_lair"]:
        var session:RefCounted=Session.new(rules);session.start(&"competitive",StringName(enc),{"count":1,"concurrent":1})
        var sim:RefCounted=session.simulation;var victim:Dictionary=sim.actors[1];var monster:Dictionary=sim.actors[10]
        monster.health=0;sim.knock_down(monster,"defeat")
        victim.health=0;sim.knock_down(victim,"defeat")
        victim.facing=-monster.facing
        sim.select_player_death(victim,monster,"dragon_bite" if enc=="dragon_fight" else "beast_charge")
        if enc=="dragon_fight":sim.dragon_finish(monster,victim,"dragon_bite")
        var animator:RefCounted=Animator.new();var visited:Array=[]
        for n in 220:
            animator.update(sim.actors,rules,art)
            var pose:Dictionary=animator.poses[1]
            if visited.is_empty() or visited[-1]!=pose.index:visited.append(pose.index)
            sim.advance()
        check(victim.hidden_by==0 and victim.down_remaining==0,"dead creature cannot retain ownership of a simultaneous player kill "+enc)
        if enc=="beast_lair":check(victim.defeat_clip=="fallen_front" and visited==art.animation_for("war_beast").clips.fallen_front.frames,"simultaneous beast kill displays every front knockdown pose")
    if failures==0:print("PASS: "+str(paths)+" roster death paths in both facings, every native pose in order, full long co-op kill repeats, solo delay boundaries, source-specific variants, sounds and rule isolation")
    quit(1 if failures else 0)
