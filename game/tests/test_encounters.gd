extends SceneTree

const Model = preload("res://scripts/domain/combat_simulation.gd")
const Rules = preload("res://scripts/content/combat_rules.gd")
const Session = preload("res://scripts/session/local_session.gd")
var failures: int = 0

func check(condition: bool, message: String) -> void:
    if not condition:
        failures += 1
        push_error(message)

func command(id: int, sequence: int, tick: int, action: String) -> Dictionary:
    return {"actor": id, "sequence": sequence, "tick": tick, "dx": 0, "dy": 0, "action": action}

func _initialize() -> void:
    var rules: Resource = Rules.new()
    var model: RefCounted = Model.new(rules)
    model.start(&"competitive", 2)
    model.actors[1].x = 100
    model.actors[2].x = 260
    check(model.submit(1, command(1, 1, 0, "dagger")), "throw accepted with ammunition")
    model.advance()
    for step in range(rules.moves.dagger.windup - 1): model.advance()
    check(model.actors[1].daggers == 10 and model.projectiles.is_empty(), "windup does not consume ammunition")
    model.advance()
    check(model.actors[1].daggers == 9 and model.projectiles.size() == 1, "release consumes one dagger")
    for step in range(40): model.advance()
    check(model.actors[2].health == 17 and model.projectiles.is_empty(), "flying dagger hits once then disappears")
    check(model.actors[1].daggers == 9, "recovery cannot throw a second dagger")
    model.actors[1].daggers = 0
    check(not model.submit(1, command(1, 2, model.tick, "dagger")), "empty ammunition rejects throw")

    # A hit before release cancels the throw without losing ammunition.
    model.start(&"competitive", 2)
    model.actors[1].x = 100
    model.actors[2].x = 125
    model.submit(1, command(1, 1, 0, "dagger"))
    model.actors[2].action = "swing"
    model.actors[2].remaining = rules.moves.swing.active + rules.moves.swing.recovery + 1
    for step in range(30): model.advance()
    check(model.actors[1].daggers == 10 and model.projectiles.is_empty(), "interrupt before release preserves ammunition")

    for facing in [1, -1]:
        for guarded in [true, false]:
            model.start(&"competitive", 2)
            model.actors[1].x = 160
            model.actors[1].facing = facing
            model.actors[2].x = 160 + facing * 95
            model.actors[2].facing = -facing
            model.submit(1, command(1, 1, 0, "dagger"))
            for step in range(40):
                model.submit(2, command(2, step + 1, model.tick, "block" if guarded else "idle"))
                model.advance()
            check(model.actors[2].health == 17, "original dagger bypasses guard in both facings")

    model.start(&"cooperative", 2)
    model.actors[1].x = 100
    model.actors[2].x = 140
    model.actors[3].x = 230
    model.submit(1, command(1, 1, 0, "dagger"))
    for step in range(40): model.advance()
    check(model.actors[2].health == 20 and model.actors[3].health == 37, "dagger passes through allies to hit enemy")

    var fast_rules: Resource = Rules.new()
    fast_rules.dagger_speed = 180
    var fast: RefCounted = Model.new(fast_rules)
    fast.start(&"competitive", 2)
    fast.actors[1].x = 100
    fast.actors[2].x = 220
    fast.actors[3] = fast.make_actor(3, 0, 2, "knight", Vector2i(165, 166), -1)
    fast.submit(1, command(1, 1, 0, "dagger"))
    for step in range(rules.moves.dagger.windup + 1): fast.advance()
    check(fast.actors[3].health == 17 and fast.actors[2].health == 20, "swept projectile selects nearest target despite ID order and high speed")

    model.start(&"competitive", 2)
    model.actors[1].x = 100
    model.actors[2].x = 260
    model.submit(1, command(1, 1, 0, "dagger"))
    for step in range(rules.moves.dagger.windup + 1): model.advance()
    var copied: Dictionary = model.snapshot()
    copied.projectiles[0].x = -999
    check(model.projectiles[0].x > 0, "projectile snapshot is isolated from simulation")
    model.actors[1].health = 0
    for step in range(30): model.advance()
    check(model.actors[2].health == 17, "released dagger survives its thrower's defeat")

    model.start(&"competitive", 0, &"spear_lair")
    check(model.actors.size() == 3 and model.spawn_remaining == 2, "lair opens with two of four Troggs")
    check(model.actors[1].health == 20 and model.actors[10].health == 15, "lair combat uses separate native encounter health")
    check(not model.submit(0, command(10, 1, 0, "block")), "Trogg cannot use knight guard")
    check(not model.submit(1, command(10, 1, 0, "spear_thrust")), "human cannot command the creature")
    var malformed: Dictionary = command(10, 1, 0, "idle")
    malformed.facing = 0
    check(not model.submit(0, malformed), "facing override must be a valid direction")
    model.actors[10].health = 0
    model.advance()
    check(model.actors.has(12) and model.spawn_remaining == 1, "defeat admits exactly one replacement")
    model.actors[11].health = 0
    model.actors[12].health = 0
    model.advance()
    check(model.actors.has(13) and model.spawn_remaining == 0 and model.outcome() == "ongoing", "remaining wave prevents early victory")
    model.actors[13].health = 0
    model.advance()
    check(model.outcome() == "victory", "lair clears only when all four enemies are down")
    model.start(&"cooperative", 2, &"spear_lair")
    model.actors[1].health = 0
    check(model.outcome() == "ongoing", "living ally can finish lair")
    model.actors[2].health = 0
    model.actors[10].health = 0
    model.advance()
    check(model.outcome() == "defeat" and not model.actors.has(12), "last ally defeat stops additional spawning")

    for facing in [1, -1]:
        for guarded in [true, false]:
            model.start(&"competitive", 0, &"spear_lair")
            model.actors[10].x = 160 - facing * 120
            model.actors[10].facing = facing
            model.actors[10].cooldown_remaining = 0 # isolate a thrust from the encounter entry delay
            model.actors[1].x = 160
            model.actors[1].facing = -facing
            model.submit(0, command(10, 1, 0, "spear_thrust"))
            for step in range(1 + rules.moves.spear_thrust.windup + rules.moves.spear_thrust.active + rules.moves.spear_thrust.recovery):
                model.submit(1, command(1, step + 1, model.tick, "block" if guarded else "idle"))
                model.advance()
            check(model.actors[1].health == (20 if guarded else 17), "long-range original spear contacts hit once or are fully blocked")
            check(model.actors[10].cooldown_remaining > 0, "Trogg recovers between attacks")

    var session: RefCounted = Session.new(rules)
    session.start(&"competitive", &"spear_lair")
    session.simulation.actors[1].x = 150
    session.simulation.actors[10].x = 80
    session.advance(Vector2i.ZERO, "idle")
    check(session.simulation.actors[10].x == 79 and session.simulation.actors[10].facing == 1,
        "Trogg retreats while facing the knight")
    var second: RefCounted = Session.new(rules)
    session.start(&"cooperative", &"spear_lair")
    second.start(&"cooperative", &"spear_lair")
    for current in range(500):
        var direction := Vector2i(1 if current < 35 else 0, -1 if current >= 35 and current < 40 else 0)
        var action: String = "dagger" if current % 30 == 0 else ("block" if current % 30 < 15 else "lunge")
        session.advance(direction, action)
        second.advance(direction, action)
        check(session.simulation.snapshot() == second.simulation.snapshot(), "creature AI, projectiles and waves replay deterministically")
    if failures == 0:
        print("PASS: dagger release/ammo/interruption/guards/sweep, wave completion, authority, spear contacts, retreat and encounter replay")
    quit(1 if failures else 0)
