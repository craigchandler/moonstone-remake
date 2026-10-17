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
        "tick": model.tick, "dx": direction.x, "dy": direction.y, "action": action}), "fixture input accepted")

func _initialize() -> void:
    run_checks.call_deferred()

func run_checks() -> void:
    var rules: Resource = load("res://content/foundation_rules.tres")
    var art: Resource = load("res://content/classic_art.tres")
    var animations: Resource = art.animation_for("giant_troll")
    check(animations.poses.size() == 18 and animations.clips.size() == 8, "all traced troll poses/clips are available")
    for variant in ["purple", "blue", "purple_clean", "blue_clean"]:
        var texture: Texture2D = animations.atlas_for(variant)
        for pose in animations.poses:
            check(Rect2(Vector2.ZERO, texture.get_size()).encloses(pose.region), "large club poses fit atlas")
            check(pose.offset == Vector2(-192, -224), "troll poses retain common foot anchor")
    for move in ["troll_sweep", "troll_smash"]:
        var clip: Dictionary = animations.clips[move]
        var frames: Array = rules.geometry.giant_troll.attacks[move]
        check(clip.phases.active.size() == frames.size(), "troll active poses match contact geometry")
        for i in range(frames.size()):
            check(not frames[i].points.is_empty() and frames[i].weight == clip.weights[clip.frames.find(clip.phases.active[i])], "troll frame holds match contact timing")

    var model: RefCounted = Model.new(rules)
    var animator: RefCounted = Animator.new()
    for facing in [1, -1]:
        for move in ["troll_sweep", "troll_smash"]:
            for defence in ["idle", "block", "evade"]:
                model.start(&"competitive", 0, &"troll_lair")
                model.actors[10].x = 160 - facing * 140
                model.actors[10].y = 166
                model.actors[10].facing = facing
                model.actors[10].cooldown_remaining = 0
                model.actors[10].entering = false # staged close-range stroke, past entrance
                model.actors[1].x = 160
                model.actors[1].facing = -facing
                command(model, 10, move)
                model.advance()
                var duration: int = rules.moves[move].windup + rules.moves[move].active + rules.moves[move].recovery
                var start_x: int = model.actors[10].x
                var damage_count: int = 0
                for step in range(duration + 2):
                    command(model, 1, "block" if defence == "block" else "idle", Vector2i.UP if defence == "evade" and step < 10 else Vector2i.ZERO)
                    # Attempts to turn the committed troll cannot redirect its club/lunge.
                    command(model, 10, "idle", Vector2i(-facing, 1) if step < duration else Vector2i.ZERO)
                    model.advance()
                    animator.update(model.actors, rules, art)
                    for event in model.events:
                        if event.type == "damage":
                            damage_count += 1
                            check(event.amount == 7 and not event.blocked, "club deals full original 7 damage through guard")
                            check(animator.poses[10].clip == move and animator.poses[10].phase == "active", "club hits only on matching active artwork")
                        check(event.type != "parry", "troll club cannot be parried")
                check(model.actors[1].health == (20 if defence == "evade" else 13), "guard cannot stop club; actual sidestep evades in both facings: " + move + "/" + defence + "/" + str(facing))
                check(damage_count == (0 if defence == "evade" else 1), "one club stroke deals damage at most once")
                check(model.actors[10].x == start_x + (32 * facing if move == "troll_sweep" else 0), "sweep steps 32 pixels forward; smash stays planted")
                check(model.actors[10].y == 166 and model.actors[10].facing == facing, "club attack retains lane and facing")

    var session: RefCounted = Session.new(rules)
    session.start(&"competitive", &"troll_lair")
    session.simulation.actors[1].x = 220
    session.simulation.actors[10].x = 70
    session.advance(Vector2i.ZERO, "idle")
    check(session.simulation.actors[10].x == 71, "stalker walks towards an out-of-reach knight")
    for previous in ["", "troll_smash", "troll_sweep"]:
        session.start(&"competitive", &"troll_lair")
        session.simulation.actors[1].x = 200
        session.simulation.actors[10].x = 60
        session.simulation.actors[10].cooldown_remaining = 0
        session.simulation.actors[10].last_attack = previous
        session.advance(Vector2i.ZERO, "idle")
        check(session.simulation.actors[10].action == ("troll_sweep" if previous == "troll_smash" else "troll_smash"), "mid-range troll alternates smash with advancing sweep")
    # Durable target isolates uninterrupted repeat timing from player defeat.
    session.start(&"competitive", &"troll_lair")
    session.simulation.actors[1].x = 220
    session.simulation.actors[1].health = 10000
    session.simulation.actors[1].maximum = 10000
    session.simulation.actors[10].x = 80
    var last_start: int = -1
    var last_duration: int = 0
    var seen: Dictionary = {}
    for step in range(700):
        session.advance(Vector2i.ZERO, "idle")
        for event in session.simulation.events:
            if event.type != "attack" or event.actor != 10: continue
            check(step >= 49, "troll gives its entry opening")
            if last_start >= 0: check(step - last_start >= last_duration + 80, "troll cannot chain attacks without its recovery/cooldown")
            var move: Dictionary = rules.moves[event.move]
            last_duration = move.windup + move.active + move.recovery
            last_start = step
            seen[event.move] = true
    check(seen.has("troll_smash") and seen.has("troll_sweep"), "normal AI uses both club attacks")
    var second: RefCounted = Session.new(rules)
    session.start(&"cooperative", &"troll_lair")
    second.start(&"cooperative", &"troll_lair")
    for step in range(500):
        var direction := Vector2i(0, -1 if step % 100 < 15 else (1 if step % 100 < 30 else 0))
        var action: String = "dagger" if step % 30 == 0 else "heavy"
        session.advance(direction, action)
        second.advance(direction, action)
        check(session.simulation.snapshot() == second.simulation.snapshot(), "troll attack memory/stride/co-op replay deterministically")
    var copied: Dictionary = session.simulation.snapshot()
    check(copied.schema == 22 and copied.content == "encounters.v27", "new authoritative attack memory versions snapshot/content")
    copied.actors[10].last_attack = "corrupt"
    check(session.simulation.actors[10].last_attack != "corrupt", "snapshot cannot mutate troll attack memory")
    for mode in [&"competitive", &"cooperative"]:
        model.start(mode, 0, &"troll_lair")
        check(model.actors[10].health == 40 and model.spawn_remaining == 0, "one full-strength 40hp troll in native test lair")
        check(model.actors[1].health == 20 and model.actors[1].daggers == 10, "normal fresh knight kit enters troll lair")
        if mode == &"cooperative":
            model.actors[1].health = 0
            check(model.outcome() == "ongoing", "living AI ally can continue fighting troll")
        model.actors[10].health = 0
        check(model.outcome() == "victory", "troll defeat clears lair in solo/co-op")

    var journey: RefCounted = Journey.new(load("res://scripts/content/world_definition.gd").new(), rules, 1234)
    journey.world.position = Vector2i(80, 112)
    for step in range(20):
        if journey.travel(Vector2i.RIGHT): break
    check(journey.world.active_lair == "grassland_south" and journey.combat.simulation.encounter == &"troll_lair", "South lair routes into troll encounter")
    var reward: Dictionary = journey.lair_loot.grassland_south.duplicate(true)
    check(not journey.prepare_loot(), "ongoing troll encounter grants no reward")
    journey.combat.simulation.actors[10].health = 0
    check(journey.prepare_loot(), "actual troll victory opens loot")
    journey.return_to_map()
    check(journey.world.cleared.has("grassland_south") and journey.world.cleared.size() == 1, "only South clears on troll victory")
    check(journey.inventory.gold == reward.gold + 10 and journey.inventory.items == reward.items, "troll victory awards exactly its pre-rolled loot")

    for mirrored in [false, true]:
        var arena: Node = load("res://scenes/arena.tscn").instantiate()
        arena.demo = true
        arena.troll_demo = true
        arena.mirror_demo = mirrored
        root.add_child(arena)
        arena.set_physics_process(false)
        var events: Dictionary = {}
        for step in range(arena.demo_length()):
            arena.advance_demo()
            arena.animator.update(arena.session.simulation.actors, rules, art)
            for event in arena.session.simulation.events:
                if event.type == "attack": events[event.move] = true
        check(arena.session.simulation.outcome() == "victory" and arena.session.simulation.actors[1].health == 20, "staged troll visual fixture wins without damage in either facing")
        check(events.has("troll_smash") and events.has("troll_sweep") and events.has("heavy") and events.has("lunge"), "showcase demonstrates both club moves and knight counters")
        check(arena.session.simulation.actors[10].down_remaining == 0, "troll collapse completes before capture ends")
        arena.queue_free()
    await process_frame
    if failures == 0:
        print("PASS: troll art/contact phases, unblockable 7-damage strikes, sidesteps/stride/commit in both facings, AI attack memory/cadence/replay/co-op, South lair loot and full-health mirrored showcases")
    quit(1 if failures else 0)
