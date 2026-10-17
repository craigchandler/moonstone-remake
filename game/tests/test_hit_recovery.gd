extends SceneTree
const Session=preload("res://scripts/session/local_session.gd")
const Fixture=preload("res://debug/fixtures/hit_recovery_fixture.gd")
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
    var cases:Array=[]
    for kind in ["hammer","rat"]:
        for move in ["swing","heavy","lunge","reverse","upward","dagger"]:cases.append("recover_"+kind+"~"+move)
    cases.append_array(["recover_troll~troll_sweep","recover_balok~balok_swipe","recover_guardian~guardian_lunge","recover_guardian_release~guardian_grab","recover_dragon~dragon_foot","recover_fire~ground_fire"])
    for name in cases:
        for mirror in [false,true]:
            var session:RefCounted=Session.new(rules);var replay:RefCounted=Session.new(rules)
            var fixture:RefCounted=Fixture.new();fixture.choice=name;fixture.mirror=mirror
            var other:RefCounted=Fixture.new();other.choice=name;other.mirror=mirror
            var animator:RefCounted=Animator.new();var scheduler:RefCounted=Scheduler.new();var visited:Array=[]
            for n in fixture.length():
                fixture.advance(session);other.advance(replay)
                var sim:RefCounted=session.simulation;var actor:Dictionary=sim.actors[fixture.target]
                var before:Dictionary=sim.snapshot()
                animator.update(sim.actors,rules,art);scheduler.collect(sim,animator.poses,art,sound)
                check(sim.snapshot()==before and sim.snapshot()==replay.simulation.snapshot(),"input replay and presentation/audio isolation "+name)
                if actor.reaction==fixture.expected_clip:
                    var pose:Dictionary=animator.poses[fixture.target]
                    if visited.is_empty() or visited[-1]!=pose.index:visited.append(pose.index)
                    check(actor.y==fixture.recovery_y,"held movement cannot cancel committed recovery "+name)
            var animation:Resource=art.animation_for(fixture.expected_family)
            check(visited==animation.clips[fixture.expected_clip].frames,"every surviving-hit/landing pose displays in order "+name+str(mirror))
            check(fixture.verify(session),"real contact and complete recovery "+name+str(mirror))
            check(session.simulation.actors[fixture.target].y<fixture.recovery_y,"input resumes after landing/recovery "+name)
    check(rules.actor_definitions.trogg_hammer.reaction_clips.lunge=="hurt_c" and rules.actor_definitions.trogg_hammer.reaction_clips.reverse=="hurt_c","Hammer source thrust and reverse variants")
    check(rules.actor_definitions.ratman.reaction_clips.swing=="hurt_b" and rules.actor_definitions.ratman.reaction_clips.heavy=="hurt_heavy","Ratman source swing and overhead variants")
    check(art.animation_for("knight_finishes").clips.hop.frames.size()==4 and rules.recovery.duration("knight_finishes","hop",0)==54,"hop retains kneeling6546 return before idle")
    for family in ["ratman","dragon"]:
        var base:Resource=art.animation_for(family)
        check(base.clips.idle.frames.size()==1 and base.clips.walk.frames.size()==4,"recovery imports preserve unrelated idle/walk "+family)
    # The stationary flame is a Dragon object; both lethal and protected living
    # contacts use its hop path, without changing its34 damage before protection.
    for protection in [0,1,2]:
        var session:RefCounted=Session.new(rules);var fixture:RefCounted=Fixture.new();fixture.choice="recover_fire~ground_fire";fixture.reset(session)
        var sim:RefCounted=session.simulation;var knight:Dictionary=sim.actors[1]
        knight.health=20;knight.maximum=20;knight.dragon_damage_shift=protection
        for n in 3:sim.advance()
        check(knight.health==maxi(0,20-(34>>protection)),"flame object damage/protection unchanged")
        check(knight.defeat_clip=="hop" and knight.visual_kind=="death_knight" if protection==0 else knight.reaction=="hop" and knight.visual_kind=="knight_finishes","flame object uses lethal or living hop instead of breath/burn")
    # A later real contact may interrupt recovery. Its own artwork must replace
    # the hop family, and a lethal hit must clear the living lock entirely.
    var session:RefCounted=Session.new(rules);var fixture:RefCounted=Fixture.new();fixture.choice="recover_balok~balok_swipe"
    while fixture.hit_tick<0 and fixture.tick<100:fixture.advance(session)
    var sim:RefCounted=session.simulation;var knight:Dictionary=sim.actors[1]
    sim.actors[10].cooldown_remaining=10000
    sim.actors[20]=sim.make_actor(20,0,2,&"knight",Vector2i(knight.x-25,166),1)
    var health:int=knight.health
    session.command(20,0,Vector2i.ZERO,"swing")
    for n in 15:sim.advance()
    check(knight.health==health-5 and knight.reaction=="hurt_a" and knight.visual_kind.is_empty() and knight.motion.is_empty(),"second surviving contact replaces hop artwork, movement and recovery")
    var interrupted_x:int=knight.x
    for n in 60:sim.advance()
    check(knight.x==interrupted_x,"interrupted hop cannot resume its remaining steps after another hit")
    sim.actors[20].cooldown_remaining=0;knight.health=1
    session.command(20,0,Vector2i.ZERO,"swing")
    for n in 20:sim.advance()
    check(knight.health==0 and knight.reaction_remaining==0 and knight.stagger_remaining==0 and knight.visual_kind=="death_knight","later lethal contact clears living recovery and retains completed death family")
    if failures==0:print("PASS:36 real-contact recovery replays, source Hammer/Ratman variants, all living/landing poses, committed input boundary and later movement, flame-object death/protection, native sounds and rule isolation")
    quit(1 if failures else 0)
