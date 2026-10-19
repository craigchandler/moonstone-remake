extends SceneTree

const Session=preload("res://scripts/session/local_session.gd")
const Effects=preload("res://scripts/presentation/combat_hit_effects.gd")
const Animator=preload("res://scripts/presentation/actor_animator.gd")
const Frame=preload("res://scripts/presentation/graphics/combat_frame.gd")
const Renderer=preload("res://scripts/presentation/graphics/classic_combat_renderer.gd")
const Recorder=preload("res://tests/support/draw_recorder.gd")
const Rules=preload("res://content/foundation_rules.tres")
const Art=preload("res://content/generated/classic_layered_art.tres")
var failures: int=0
var checks: int=0
var state_trace:=HashingContext.new()

func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failures+=1;push_error(label)

func fresh(move: String="swing",mirror: bool=false) -> RefCounted:
    var session: RefCounted=Session.new(Rules)
    session.start(&"competitive",&"balok_lair",{"count":1,"concurrent":1})
    var model: RefCounted=session.simulation
    model.actors[1].x=100;model.actors[1].y=166
    model.actors[10].x=135 if move=="upward" else (220 if move=="dagger" else 155)
    model.actors[10].y=166;model.actors[10].facing=-1
    model.actors[10].entering=false;model.actors[10].cooldown_remaining=0
    if move=="reverse":model.actors[1].facing=-1
    if mirror:
        for actor in model.actors.values():actor.x=320-actor.x;actor.facing=-actor.facing
    return session

func _initialize() -> void:run.call_deferred()

func run() -> void:
    state_trace.start(HashingContext.HASH_SHA256)
    var burst: Resource=Art.effects.blood_burst
    check(burst.layers!=null and burst.atlases.is_empty(),"blood uses shared layer pages, without composite atlases")
    check(burst.clips.burst.frames.size()==5,"retain all five recovered splash drawings")
    for mirror in [false,true]:
        for lethal in [false,true]:
            for move in ["swing","heavy","lunge","upward","reverse","dagger"]:
                var session: RefCounted=fresh(move,mirror)
                var model: RefCounted=session.simulation
                var health: int=1 if lethal else model.actors[10].maximum
                model.actors[10].health=health
                var hit_box: Rect2=model.hurt_box_for(model.actors[10])
                var effects: RefCounted=Effects.new()
                var animator: RefCounted=Animator.new()
                var frame: RefCounted=Frame.new()
                var renderer: RefCounted=Renderer.new(Art)
                var emitted: int=0
                var seen: Dictionary={}
                check(session.command(1,1,Vector2i.ZERO,move),"real strike accepted: "+move)
                for tick in 160:
                    model.advance()
                    var before: Dictionary=model.snapshot()
                    state_trace.update(var_to_bytes(before))
                    # Exclude only the newly restored presentation event from the
                    # retained pre-fix trace; all gameplay events must still agree.
                    state_trace.update(var_to_bytes(model.events.filter(func(e: Dictionary)->bool:return e.type!="hit_effect")))
                    effects.update(model,Art);animator.update(model.actors,Rules,Art)
                    var once: Array=effects.active.duplicate(true)
                    effects.update(model,Art)
                    check(effects.active==once,"same tick cannot duplicate blood")
                    for event in model.events:
                        if event.type!="hit_effect":continue
                        emitted+=1
                        check(event.actor==10 and event.effect=="blood_burst","Balok receives the existing splash")
                        check(hit_box.has_point(Vector2(event.x,event.y)),"splash uses the actual contact pixel")
                        check(model.events.any(func(e: Dictionary)->bool:return e.type=="damage" and e.actor==10 and e.amount>0),"splash requires resolved damage")
                        check(event.facing==model.actors[1].facing,"splash follows the striking direction")
                    if not effects.active.is_empty():
                        var effect: Dictionary=effects.active[0]
                        var pose: Dictionary=burst.sample("burst",model.tick-effect.born,effect.duration)
                        seen[pose.index]=true
                        frame.capture(model,animator,effects,Rules,&"balok_lair",true,0,{},{})
                        var gore: RefCounted=Recorder.new();renderer.render(gore,frame)
                        frame.gore=false
                        var clean: RefCounted=Recorder.new();renderer.render(clean,frame)
                        var page: String=burst.layers.pages[0].resource_path
                        check(gore.commands.any(func(c: Array)->bool:return c[0]=="region" and c[1]==page),"normal renderer draws the shared blood layer")
                        check(not clean.commands.any(func(c: Array)->bool:return c[0]=="region" and c[1]==page),"gore off hides the splash immediately")
                        check(gore.commands.has(["transform",Vector2(effect.x,effect.y)*2,0.0,Vector2(effect.facing,1)]),"layer transform retains contact anchor and facing")
                        # A detached presentation frame cannot change later effects.
                        frame.effects[0].point=Vector2(-999,-999)
                        check(effects.active==once,"render frame cannot mutate transient history")
                    check(before==model.snapshot(),"effects, layers and gore setting cannot mutate combat/save state")
                check(emitted==1,"one splash per real Balok hit: "+move)
                check(seen.size()==5,"all five layered drawings play: "+move)
                check(effects.active.is_empty(),"blood expires after its existing finite clock")
                check(model.actors[10].health==maxi(0,health-int(Rules.moves[move].damage)),"Balok damage is unchanged: "+move)
                check(model.actors[10].health>0 or model.actors[10].down_remaining>0,"lethal hit retains the independent death sequence")
    for move in ["swing","dagger"]:
        var session: RefCounted=fresh(move)
        session.simulation.actors[10].y=194
        session.command(1,1,Vector2i.ZERO,move)
        var effects: RefCounted=Effects.new()
        for tick in 160:
            session.simulation.advance();effects.update(session.simulation,Art)
            check(effects.active.is_empty(),"depth miss never emits blood: "+move)
        check(session.simulation.actors[10].health==session.simulation.actors[10].maximum,"miss preserves health")
    var session: RefCounted=fresh()
    var effects: RefCounted=Effects.new()
    effects.active.append({"kind":"blood_burst","born":50,"duration":30,"x":150,"y":100,"facing":1})
    effects.last_tick=50
    effects.update(session.simulation,Art)
    check(effects.active.is_empty(),"new fight/rewind clears stale splash history")
    print("BALOK_GAMEPLAY_TRACE="+state_trace.finish().hex_encode())
    for argument in OS.get_cmdline_user_args():
        if argument.begins_with("--render-dir="):await render_samples(argument.trim_prefix("--render-dir="))
    if failures==0:print("PASS: ",checks," Balok sword/dagger contacts, five shared blood layers, both facings, lethal/nonlethal hits, gore isolation, expiry and unchanged combat state")
    quit(1 if failures else 0)

func render_samples(directory: String) -> void:
    var view: Node=load("res://scenes/arena.tscn").instantiate()
    view.session=fresh();view.managed_by_world=true;view.encounter=&"balok_lair"
    root.add_child(view);view.set_physics_process(false)
    view.session.command(1,1,Vector2i.ZERO,"swing")
    var captured: bool=false
    for tick in 60:
        view.session.simulation.advance()
        view.hit_effects.update(view.session.simulation,view.art)
        if view.hit_effects.active.is_empty():continue
        view.animator.update(view.session.simulation.actors,Rules,view.art)
        if view.session.simulation.tick-view.hit_effects.active[0].born!=12:continue
        var before: Dictionary=view.session.simulation.snapshot()
        for gore in [true,false]:
            view.gore_enabled=gore;view.queue_redraw()
            await process_frame;await RenderingServer.frame_post_draw
            check(root.get_texture().get_image().save_png(directory.path_join("hit-gore.png" if gore else "hit-clean.png"))==OK,"Balok layered screenshot saved")
        check(before==view.session.simulation.snapshot(),"graphical gore toggle leaves combat unchanged")
        captured=true;break
    check(captured,"graphical fixture reaches a real ordinary Balok hit")
    view.queue_free();await process_frame
