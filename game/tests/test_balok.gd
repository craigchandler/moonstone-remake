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
    var animations: Resource = art.animation_for("balok")
    check(animations.poses.size() == 26 and animations.clips.size() == 13, "all 26 Balok poses and 13 semantic clips are available")
    for variant in ["purple", "blue", "purple_clean", "blue_clean"]:
        var texture: Texture2D = animations.atlas_for(variant)
        for pose in animations.poses:
            check(Rect2(Vector2.ZERO, texture.get_size()).encloses(pose.region), "Balok pose stays inside atlas")
            check(pose.offset == Vector2(-160, -160), "Balok poses share original foot anchor")
    for move in ["balok_swipe", "balok_maul"]:
        var clip: Dictionary = animations.clips[move]
        var contacts: Array = rules.geometry.balok.attacks[move]
        check(contacts.size() == clip.phases.active.size(), "Balok active artwork/contact counts match")
        for i in range(contacts.size()):
            check(not contacts[i].points.is_empty() and contacts[i].weight == clip.weights[clip.frames.find(clip.phases.active[i])], "Balok active contact holds match artwork")
    var model: RefCounted = Model.new(rules)
    var animator: RefCounted = Animator.new()
    for facing in [1, -1]:
        for move in ["balok_swipe", "balok_maul", "balok_hop", "balok_pounce"]:
            for defence in ["idle", "block", "evade"]:
                model.start(&"competitive", 0, &"balok_lair")
                model.actors[1].x = 160
                model.actors[1].facing = -facing
                model.actors[10].x = 160 - facing * (150 if move == "balok_pounce" else 75)
                model.actors[10].x = clampi(model.actors[10].x, 22, 298)
                model.actors[10].facing = facing
                model.actors[10].cooldown_remaining = 0
                command(model, 10, move)
                model.advance()
                var duration: int = rules.moves[move].windup + rules.moves[move].active + rules.moves[move].recovery
                var damage_count: int = 0
                var peak: int = 0
                var target_x: int = model.actors[10].leap_to_x
                var target_y: int = model.actors[10].leap_to_y
                for step in range(duration + 2):
                    if model.actors[1].health > 0: command(model, 1, "block" if defence == "block" else "idle", Vector2i.UP if defence == "evade" and step < 10 else Vector2i.ZERO)
                    # Steering input cannot retarget a committed attack.
                    command(model, 10, "idle", Vector2i(-facing, 1) if step < duration else Vector2i.ZERO)
                    model.advance()
                    animator.update(model.actors, rules, art)
                    peak = maxi(peak, -int(model.actors[10].height))
                    if move in ["balok_pounce", "balok_hop"]:
                        check(model.actors[10].leap_to_x == target_x and model.actors[10].leap_to_y == target_y, "moving target cannot redirect locked pounce")
                    for event in model.events:
                        check(event.type != "parry", "Balok attacks cannot be parried")
                        if event.type == "damage":
                            damage_count += 1
                            check(event.amount == (20 if move in ["balok_pounce","balok_hop"] else 5) and not event.blocked, "Balok landing knocks out; claws deal five HP through guard")
                            check(animator.poses[10].clip == ("lift" if move=="balok_maul" else move), "Balok contact switches into matching active or lift artwork")
                            if move in ["balok_pounce", "balok_hop"]:
                                check(abs(int(model.actors[10].height)) <= 20, "pounce only damages near landing")
                check(model.actors[1].health == (20 if defence == "evade" else (0 if move in ["balok_pounce","balok_hop"] else 15)), "Balok hit/guard/sidestep in either facing: " + move + "/" + defence + "/" + str(facing))
                check(damage_count == (0 if defence == "evade" else 1), "one damage event per Balok attack")
                check(model.actors[10].height == 0, "Balok finishes grounded")
                if move in ["balok_pounce", "balok_hop"]:
                    check(peak == int(rules.moves[move].leap_peak), "native leap reaches specified arc peak")
                    check(model.actors[10].x == target_x and model.actors[10].y == target_y, "native leap lands at its locked spot")
                if move == "balok_swipe" and defence != "evade":
                    check(model.actors[1].facing == -facing, "Balok swipe uses source attacker-facing XOR2 while its hop travels with the attacker")

    # Airborne bodies use the same vertical offset for rendering, sword contacts and daggers.
    model.start(&"competitive", 0, &"balok_lair")
    model.actors[1].x = 150
    model.actors[10].x = 150
    model.actors[10].height = -96
    var airborne: Rect2 = model.hurt_box_for(model.actors[10])
    model.actors[10].height = 0
    check(model.hurt_box_for(model.actors[10]).position.y - airborne.position.y == 96, "authoritative height shifts hurt box with art")
    model.actors[10].cooldown_remaining = 0
    command(model, 10, "balok_pounce")
    model.advance()
    for step in range(30): model.advance()
    check(model.actors[10].height < 0, "fixture reaches actual flight")
    var copy: Dictionary = model.snapshot()
    copy.actors[10].leap_to_x = -999
    check(model.actors[10].leap_to_x >= 22, "leap snapshot cannot modify authoritative target")
    # A real dagger at body height falls below an actor at the leap peak.
    model.actors[10].remaining = rules.moves.balok_pounce.recovery + rules.moves.balok_pounce.active / 2 + 1
    model.actors[1].x = 150
    model.actors[10].leap_from_x = 235
    model.actors[10].leap_to_x = 235
    model.projectiles.clear()
    model.projectiles.append({"id": 1, "actor": 1, "team": 1, "x": 228, "y": 166, "height": -43, "facing": 1, "ttl": 1})
    model.advance()
    check(model.actors[10].health == 30 and model.actors[10].height <= -90, "dagger passes under the raised Balok body")

    var session: RefCounted = Session.new(rules)
    for distance in [60, 75, 100, 145]:
        session.start(&"competitive", &"balok_lair")
        session.simulation.actors[1].x = 210
        session.simulation.actors[10].x = 210 - distance
        session.simulation.actors[10].cooldown_remaining = 0
        session.advance(Vector2i.ZERO, "idle")
        check(session.simulation.actors[10].action == ("balok_hop" if distance == 60 else ("balok_swipe" if distance == 75 else ("balok_maul" if distance == 100 else "balok_pounce"))), "Balok AI chooses close hop, swipe, maul or long pounce")
    session.start(&"competitive", &"balok_lair")
    session.simulation.actors[1].health = 10000
    session.simulation.actors[1].maximum = 10000
    var last_start: int = -1
    var previous_duration: int = 0
    var starts: int = 0
    for step in range(650):
        # A direct landing is lethal regardless of inflated fixture HP.
        # Evade committed airborne lanes so repeat AI remains testable.
        var foe: Dictionary=session.simulation.actors[10]
        session.simulation.actors[1].y=139 if foe.action in ["balok_pounce","balok_hop"] and foe.remaining>0 else 166
        session.advance(Vector2i.ZERO, "idle")
        for event in session.simulation.events:
            if event.type != "attack" or event.actor != 10: continue
            check(step >= 49, "Balok entry allows a defensive opening")
            if last_start >= 0: check(step - last_start >= previous_duration + 30, "Balok cannot chain attacks without recovery/cooldown")
            last_start = step
            var move: Dictionary = rules.moves[event.move]
            previous_duration = move.windup + move.active + move.recovery
            starts += 1
    check(starts >= 3, "live Balok AI completes repeated cycles")
    var second: RefCounted = Session.new(rules)
    session.start(&"cooperative", &"balok_lair")
    second.start(&"cooperative", &"balok_lair")
    for step in range(600):
        var direction := Vector2i(0, -1 if step % 100 < 15 else (1 if step % 100 < 30 else 0))
        var action: String = "dagger" if step % 30 == 0 else "heavy"
        session.advance(direction, action)
        second.advance(direction, action)
        check(session.simulation.snapshot() == second.simulation.snapshot(), "Balok trajectories/AI/co-op replay deterministically")
    check(session.simulation.snapshot().schema == 22, "airborne state versions combat snapshot")

    var journey: RefCounted = Journey.new(load("res://scripts/content/world_definition.gd").new(), rules, 1234)
    journey.world.position = Vector2i(100, 71)
    for step in range(25):
        if journey.travel(Vector2i.RIGHT): break
    check(journey.world.active_lair == "grassland_east" and journey.combat.simulation.encounter == &"balok_lair", "East lair routes into Balok encounter")
    check(journey.combat.simulation.actors[10].health == 30 and journey.combat.simulation.spawn_remaining == 0, "one normal 30-health Balok in new encounter")
    check(not journey.prepare_loot(), "ongoing Balok encounter cannot award loot")
    var reward: Dictionary = journey.lair_loot.grassland_east.duplicate(true)
    journey.combat.simulation.actors[10].health = 0
    check(journey.prepare_loot(), "Balok victory opens pre-rolled loot")
    journey.return_to_map()
    check(journey.world.cleared.size() == 1 and journey.world.cleared.has("grassland_east"), "only East clears on Balok victory")
    check(journey.inventory.gold == reward.gold + 10 and journey.inventory.items == reward.items, "Balok rewards transfer once without reroll")

    for mirrored in [false, true]:
        var arena: Node = load("res://scenes/arena.tscn").instantiate()
        arena.demo = true
        arena.balok_demo = true
        arena.mirror_demo = mirrored
        root.add_child(arena)
        arena.set_physics_process(false)
        var seen: Dictionary = {}
        for step in range(arena.demo_length()):
            arena.advance_demo()
            arena.animator.update(arena.session.simulation.actors, rules, art)
            for event in arena.session.simulation.events:
                if event.type == "attack": seen[event.move] = true
        check(arena.session.simulation.outcome() == "victory" and arena.session.simulation.actors[1].health == 20, "staged Balok showcase wins without damage in both facings")
        for move in ["balok_pounce", "balok_hop", "balok_swipe", "balok_maul", "dagger", "heavy", "swing"]:
            check(seen.has(move), "showcase includes " + move)
        check(arena.session.simulation.actors[10].down_remaining == 0 and arena.session.simulation.actors[10].height == 0, "Balok death completes on the ground")
        arena.queue_free()
    await process_frame
    if failures == 0:
        print("PASS: Balok art/contact phases, airborne/landing collision, locked aim, guards/sidesteps/both facings, swipe turn, AI choices/cadence/co-op/replay, East loot and full-health mirrored showcases")
    quit(1 if failures else 0)
