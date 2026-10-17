extends SceneTree

const Model = preload("res://scripts/domain/combat_simulation.gd")
const Session = preload("res://scripts/session/local_session.gd")
const Effects = preload("res://scripts/presentation/combat_hit_effects.gd")
const Animator = preload("res://scripts/presentation/actor_animator.gd")
var rules: Resource = preload("res://content/foundation_rules.tres")
var art: Resource = preload("res://content/classic_art.tres")
var failures: int = 0
var checks: int = 0

func check(ok: bool, label: String) -> void:
    checks += 1
    if not ok: failures += 1; push_error(label)

func fresh(mirror: bool = false) -> RefCounted:
    var s: RefCounted = Session.new(rules)
    s.start(&"competitive",&"troll_lair",{"count":1,"concurrent":1})
    var m: RefCounted = s.simulation
    m.actors[1].x = 100; m.actors[1].y = 166
    m.actors[10].x = 155; m.actors[10].y = 166
    m.actors[10].facing = -1; m.actors[10].entering = false
    m.actors[10].cooldown_remaining = 0
    if mirror:
        for a in m.actors.values(): a.x=320-a.x; a.facing=-a.facing
    return s

func _initialize() -> void:
    run.call_deferred()

func run() -> void:
    var burst: Resource = art.effects.blood_burst
    check(burst.clips.burst.frames.size()==5,"all five original separate hit drawings")
    var image: Image = burst.atlas_for("gore").get_image()
    for index in burst.clips.burst.frames:
        var pose: Dictionary = burst.sample("burst",index*6,30)
        var cell: Image = image.get_region(Rect2i(pose.region))
        check(not cell.is_invisible(),"blood drawing has visible pixels")
    for mirror in [false,true]:
        for lethal in [false,true]:
            for move in ["swing","heavy","lunge","upward","reverse","dagger"]:
                var s: RefCounted = fresh(mirror)
                var m: RefCounted = s.simulation
                if move=="upward": m.actors[10].x=m.actors[1].x+35*m.actors[1].facing
                if move=="dagger": m.actors[10].x=m.actors[1].x+120*m.actors[1].facing
                if move=="reverse": m.actors[1].facing=-m.actors[1].facing
                m.actors[10].health=1 if lethal else 40
                var hit_box: Rect2 = m.hurt_box_for(m.actors[10])
                var fx: RefCounted = Effects.new()
                var replay: RefCounted = Effects.new()
                s.command(1,1,Vector2i.ZERO,move)
                var emitted: int = 0
                var seen: Dictionary = {}
                var duration: int = 1+rules.moves[move].windup+rules.moves[move].active+rules.moves[move].recovery+65
                for t in range(duration):
                    m.advance()
                    var before: Dictionary = m.snapshot()
                    fx.update(m,art); replay.update(m,art)
                    check(before==m.snapshot(),"hit drawing never mutates combat state")
                    check(fx.active==replay.active,"effect replay is deterministic without gameplay RNG")
                    var one_update: Array = fx.active.duplicate(true)
                    fx.update(m,art)
                    check(fx.active==one_update,"repeated draw update never duplicates a hit")
                    for event in m.events:
                        if event.type!="hit_effect": continue
                        emitted+=1
                        check(hit_box.has_point(Vector2(event.x,event.y)),"effect anchored inside the actual struck box")
                        check(m.events.any(func(e: Dictionary)->bool:return e.type=="damage" and e.actor==10 and e.amount>0),"blood requires real positive contact damage")
                    for effect in fx.active:
                        var age: int = m.tick-effect.born
                        seen[burst.sample("burst",age,effect.duration).index]=true
                        check(age>=0 and age<30,"effect expires at its finite end")
                check(emitted==1,"one real hit effect per attack: "+move)
                check(seen.size()==5,"each blood drawing is displayed: "+move)
                check(fx.active.is_empty(),"blood does not become permanent floating remains")
                check(m.actors[10].health==(0 if lethal else 40-(rules.moves[move].damage)),"hit presentation preserves damage: "+move)
    # Misses and a replay clock reset cannot leave stale blood.
    var s: RefCounted = fresh()
    s.simulation.actors[10].y=190
    s.command(1,1,Vector2i.ZERO,"swing")
    var fx: RefCounted = Effects.new()
    for t in range(70):
        s.simulation.advance(); fx.update(s.simulation,art)
        check(fx.active.is_empty(),"depth miss has no blood")
    fx.active.append({"born":70,"duration":30});s.simulation.tick=0
    fx.update(s.simulation,art)
    check(fx.active.is_empty(),"rewind clears previous-fight blood")
    # Retail hurtByStalker only selects07FD for a lethal Heavy. Ordinary sweep
    # produces07FB; stalker AI has no downed-target pursuit/execution branch.
    for mirror in [false,true]:
        for move in ["troll_sweep","troll_smash"]:
            s=fresh(mirror)
            var m: RefCounted=s.simulation
            m.actors[10].x=20 if not mirror else 300
            m.actors[10].facing=1 if not mirror else -1
            m.actors[1].x=160
            m.actors[1].health=7
            s.command(10,0,Vector2i.ZERO,move)
            var poses: Dictionary={};var anim: RefCounted=Animator.new()
            var expected: String="flung" if move=="troll_smash" else "hop"
            for t in range(500):
                m.advance();anim.update(m.actors,rules,art)
                if m.actors[1].health==0:
                    check(m.actors[1].defeat_clip==expected,"distinct sweep/overhead lethal result")
                    poses[anim.poses[1].index]=true
            check(m.actors[1].health==0 and m.actors[1].down_remaining==0,"lethal club sequence settles")
            check(poses.size()==art.animation_for("death_knight").clips[expected].frames.size(),"every original victim-death drawing is visited")
            var final_pose: Dictionary=anim.poses[1]
            var final_pixels: Image=art.animation_for("death_knight").atlas_for("blue").get_image().get_region(Rect2i(final_pose.region))
            check(not final_pixels.is_invisible(),"overhead splatter/ordinary corpse retains final pixels")
            for t in range(80):
                s.advance(Vector2i.ZERO,"idle")
                check(not m.events.any(func(e:Dictionary)->bool:return e.type=="execution"),"Troll does not invent a kneeling execution")
    for argument in OS.get_cmdline_user_args():
        if argument.begins_with("--render-dir="):
            await render_samples(argument.trim_prefix("--render-dir="))
    if failures==0: print("PASS: ",checks," Troll contact blood, all strikes/daggers and both facings, lethal/nonlethal hits, five effect drawings, replay isolation, and separate sweep/crushing deaths")
    quit(1 if failures else 0)

func render_samples(directory: String) -> void:
    var view: Node=load("res://scenes/arena.tscn").instantiate()
    view.session=fresh();view.managed_by_world=true;view.encounter=&"troll_lair"
    root.add_child(view);view.set_physics_process(false)
    view.session.command(1,1,Vector2i.ZERO,"swing")
    var captured: bool=false
    for t in range(60):
        view.session.simulation.advance()
        view.hit_effects.update(view.session.simulation,art)
        if view.hit_effects.active.is_empty():continue
        view.animator.update(view.session.simulation.actors,rules,art)
        view.queue_redraw();await process_frame;await RenderingServer.frame_post_draw
        check(root.get_texture().get_image().save_png(directory.path_join("hit-gore.png"))==OK,"rendered Troll blood screenshot")
        view.gore_enabled=false;view.queue_redraw()
        await process_frame;await RenderingServer.frame_post_draw
        check(root.get_texture().get_image().save_png(directory.path_join("hit-clean.png"))==OK,"rendered gore-off screenshot")
        captured=true
        break
    check(captured,"graphical fixture reached ordinary sword hit")
    for move in ["troll_sweep","troll_smash"]:
        view.session=fresh();view.hit_effects.reset();view.gore_enabled=true
        var m: RefCounted=view.session.simulation
        m.actors[10].x=20;m.actors[10].facing=1;m.actors[1].x=160
        m.actors[1].health=7
        view.session.command(10,0,Vector2i.ZERO,move)
        var elapsed: int=0
        for t in range(130):
            m.advance()
            if m.actors[1].health>0: continue
            elapsed+=1
            if elapsed!=(60 if move=="troll_smash" else 80): continue
            view.animator.update(m.actors,rules,art);view.queue_redraw()
            await process_frame;await RenderingServer.frame_post_draw
            check(root.get_texture().get_image().save_png(directory.path_join(move+"-death.png"))==OK,"rendered lethal club sequence")
            break
    view.queue_free();await process_frame
