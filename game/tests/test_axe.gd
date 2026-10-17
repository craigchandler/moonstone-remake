extends SceneTree

const Model = preload("res://scripts/domain/combat_simulation.gd")
const Session = preload("res://scripts/session/local_session.gd")
const Animator = preload("res://scripts/presentation/actor_animator.gd")
const Journey = preload("res://scripts/session/journey_session.gd")
var failures: int = 0

func check(condition: bool, message: String) -> void:
    if not condition:
        failures += 1
        push_error(message)

func command(model: RefCounted, id: int, action: String, direction := Vector2i.ZERO) -> void:
    check(model.submit(int(model.actors[id].owner), {"actor": id, "sequence": model.tick + 1,
        "tick": model.tick, "dx": direction.x, "dy": direction.y, "action": action}), "valid fixture input accepted")

func _initialize() -> void:
    run_checks.call_deferred()

func run_checks() -> void:
    var rules: Resource = load("res://content/foundation_rules.tres")
    var art: Resource = load("res://content/classic_art.tres")
    var animations: Resource = art.animation_for("trogg_axe")
    check(animations.poses.size() == 81 and animations.clips.size() == 13, "axe import has all 81 traced poses and13 clips")
    for variant in ["purple", "blue", "purple_clean", "blue_clean"]:
        var texture: Texture2D = animations.atlas_for(variant)
        for pose in animations.poses:
            check(Rect2(Vector2.ZERO, texture.get_size()).encloses(pose.region), "axe pose fits atlas")
            check(pose.offset == Vector2(-128, -128), "axe pose retains original foot anchor")
    for move in ["axe_swing", "axe_chop"]:
        var clip: Dictionary = animations.clips[move]
        var frames: Array = rules.geometry.trogg_axe.attacks[move]
        check(clip.phases.active.size() == frames.size(), "axe contacts match active artwork")
        for i in range(frames.size()):
            check(not frames[i].points.is_empty() and frames[i].weight == clip.weights[clip.frames.find(clip.phases.active[i])], "axe contact weights align with baked frames")
    for death in ["defeat_split", "defeat_guts"]:
        check(animations.clips[death].clean_fallback == "defeat", "clean axe deaths substitute generic collapse")

    var model: RefCounted = Model.new(rules)
    var animator: RefCounted = Animator.new()
    for facing in [1, -1]:
        for move in ["axe_swing", "axe_chop"]:
            for defence in ["idle", "block", "evade", "wrong_guard"]:
                model.start(&"competitive", 0, &"axe_lair")
                model.spawn_remaining = 0
                model.actors.erase(11)
                model.actors[10].x = 160 - facing * (90 if move == "axe_swing" else 115)
                model.actors[10].y = 166
                model.actors[10].facing = facing
                model.actors[10].cooldown_remaining = 0
                model.actors[1].x = 160
                model.actors[1].facing = facing if defence == "wrong_guard" else -facing
                command(model, 10, move)
                var damage_events: int = 0
                var parry_events: int = 0
                var duration: int = rules.moves[move].windup + rules.moves[move].active + rules.moves[move].recovery
                for step in range(duration + 2):
                    command(model, 1, "block" if defence in ["block", "wrong_guard"] else "idle",
                        Vector2i.UP if defence == "evade" and step < 10 else Vector2i.ZERO)
                    model.advance()
                    animator.update(model.actors, rules, art)
                    for event in model.events:
                        if event.type == "damage":
                            damage_events += 1
                            check(animator.poses[10].clip == move and animator.poses[10].phase == "active", "axe damage displays a matching active attack pose")
                        if event.type == "parry": parry_events += 1
                var safe: bool = defence in ["block", "evade"]
                check(model.actors[1].health == (20 if safe else 17), "both axe attacks can hit, face-block or sidestep in either facing: " + move + "/" + defence + "/" + str(facing))
                check(damage_events == (0 if safe else 1), "each axe stroke damages once at most")
                check(parry_events == (1 if defence == "block" else 0), "only a facing guard parries an axe")

    var session: RefCounted = Session.new(rules)
    for distance in [90, 110, 140]:
        session.start(&"competitive", &"axe_lair")
        session.simulation.actors.erase(11)
        session.simulation.spawn_remaining = 0
        session.simulation.actors[1].x = 200
        session.simulation.actors[10].x = 200 - distance
        session.simulation.actors[10].y = 166
        session.simulation.actors[10].cooldown_remaining = 0
        session.advance(Vector2i.ZERO, "idle")
        var actor: Dictionary = session.simulation.actors[10]
        check(actor.action == ("axe_swing" if distance == 90 else ("axe_chop" if distance == 110 else "idle")), "axe AI selects close swing, further chop, or approach")
        if distance == 140: check(actor.x == 61 and actor.facing == 1, "axe AI closes the distance instead of spear-style withdrawal")

    # An explicitly durable stationary target isolates cadence across many cycles.
    session.start(&"competitive", &"axe_lair")
    session.simulation.actors[1].x = 160
    session.simulation.actors[10].x = 70
    session.simulation.actors[11].x = 275
    session.simulation.actors[1].health = 10000
    session.simulation.actors[1].maximum = 10000
    var starts: Array[int] = []
    var previous: Dictionary = {}
    var saw: Dictionary = {}
    for step in range(600):
        session.advance(Vector2i.ZERO, "block")
        for event in session.simulation.events:
            if event.type != "attack" or event.actor < 10: continue
            starts.append(step)
            saw[event.move] = true
            check(step >= 34, "axe entry gives an opening to move or guard")
            if starts.size() > 1: check(step - starts[-2] >= 35, "dual axe openings are spaced apart")
            if previous.has(event.actor): check(step - int(previous[event.actor]) >= 65, "axe contact continuation plus cooldown prevents rapid chains")
            previous[event.actor] = step
    check(starts.size() >= 6 and saw.has("axe_swing") and saw.has("axe_chop"), "both axe moves occur across sustained normal AI cycles")

    var second: RefCounted = Session.new(rules)
    session.start(&"cooperative", &"axe_lair")
    second.start(&"cooperative", &"axe_lair")
    for step in range(500):
        var direction := Vector2i(0, -1 if step % 90 < 15 else (1 if step % 90 < 30 else 0))
        var action: String = "dagger" if step % 30 == 0 else "block"
        session.advance(direction, action)
        second.advance(direction, action)
        check(session.simulation.snapshot() == second.simulation.snapshot(), "axe AI/co-op/attacks replay deterministically")
    for mode in [&"competitive", &"cooperative"]:
        model.start(mode, 0, &"axe_lair")
        check(model.spawn_remaining == 2 and model.actors[10].kind == "trogg_axe" and model.actors[1].health == 20, "normal axe lair starts four enemies with two active and the usual knight kit")
        check(not model.submit(0, {"actor": 10, "sequence": 1, "tick": 0, "dx": 0, "dy": 0, "action": "spear_thrust"}), "axe Trogg cannot borrow a spear move")
        for id in [10, 11, 12, 13]:
            check(model.actors.has(id), "axe wave fills next slot")
            model.actors[id].health = 0
            model.advance()
        check(model.outcome() == "victory", "axe lair clears after all four, in solo and AI co-op")

    var journey: RefCounted = Journey.new(load("res://scripts/content/world_definition.gd").new(), rules, 1234)
    journey.world.position = Vector2i(82, 33)
    for step in range(20):
        if journey.travel(Vector2i.RIGHT): break
    check(journey.world.active_lair == "grassland_north" and journey.combat.simulation.encounter == &"axe_lair", "North lair routes into axe combat")
    check(not journey.prepare_loot(), "unfinished axe fight awards no loot")
    journey.combat.simulation.spawn_remaining = 0
    for actor in journey.combat.simulation.actors.values():
        if actor.team == 2: actor.health = 0
    check(journey.prepare_loot(), "axe victory uses the normal pre-rolled loot flow")
    journey.collect_all_loot()
    journey.return_to_map()
    check(journey.world.cleared.has("grassland_north"), "axe victory clears only the North lair")

    # Exercise the same explicit normal-rule showcase used by native captures.
    for mirrored in [false, true]:
        var arena: Node = load("res://scenes/arena.tscn").instantiate()
        arena.demo = true
        arena.axe_demo = true
        arena.mirror_demo = mirrored
        root.add_child(arena)
        arena.set_physics_process(false)
        var showcase_events: Dictionary = {}
        for step in range(arena.demo_length()):
            arena.advance_demo()
            arena.animator.update(arena.session.simulation.actors, rules, art)
            for event in arena.session.simulation.events: showcase_events[event.type] = true
        check(arena.session.simulation.outcome() == "victory" and arena.session.simulation.actors[1].health == 20, "axe visual fixture wins without damage in either facing")
        check(showcase_events.has("parry") and showcase_events.has("damage") and showcase_events.has("down"), "axe visual fixture includes guard, damage and deaths")
        arena.queue_free()
    await process_frame
    if failures == 0:
        print("PASS: axe art/contact phases, both facings, guard/sidestep, approach/two moves, group and repeat cadence, replay, four-enemy waves/co-op, North lair loot and mirrored visual fixtures")
    quit(1 if failures else 0)
