extends SceneTree

const Model = preload("res://scripts/domain/combat_simulation.gd")
const Rules = preload("res://scripts/content/combat_rules.gd")
var failures: int = 0

func check(condition: bool, message: String) -> void:
    if not condition:
        failures += 1
        push_error(message)

func command(actor: int, sequence: int, tick: int, dx: int = 0, action: String = "idle") -> Dictionary:
    return {"actor": actor, "sequence": sequence, "tick": tick, "dx": dx, "dy": 0, "action": action}

func ready_strike(model: RefCounted, id: int) -> void:
    model.actors[id].action = "swing"
    model.actors[id].remaining = model.rules.moves.swing.active + model.rules.moves.swing.recovery + 1

func _initialize() -> void:
    var rules: Resource = Rules.new()
    var model: RefCounted = Model.new(rules)
    model.start(&"competitive", 2)
    check(not model.submit(2, command(1, 1, 0)), "wrong player must not control actor")
    check(not model.submit(1, command(1, 1, 0, 2)), "invalid movement must be rejected")
    check(not model.submit(1, command(1, 1, 0, 0, "unknown")), "unknown action must be rejected")
    check(model.submit(1, command(1, 1, 0, 1)), "valid owned command should be accepted")
    check(not model.submit(1, command(1, 1, 0, -1)), "duplicate sequence must be rejected")
    model.advance()
    check(model.actors[1].x == 84, "one command should move once")
    model.advance()
    check(model.actors[1].x == 84, "consumed command must not be replayed")
    check(not model.submit(1, command(1, 2, 0)), "stale tick must be rejected")

    # Same tick blocks take effect before hits, regardless of actor ordering.
    model.start(&"competitive", 2)
    model.actors[1].x = 100
    model.actors[2].x = 125
    ready_strike(model, 1)
    check(model.submit(2, command(2, 1, 0, 0, "block")), "block accepted")
    model.advance()
    check(model.actors[2].health == 20, "same-tick facing block should parry all original sword damage")

    # Mutually lethal attacks should both resolve, not favour actor 1.
    model.start(&"competitive", 2)
    model.actors[1].x = 100
    model.actors[2].x = 125
    for id in [1, 2]:
        model.actors[id].health = 5
        ready_strike(model, id)
    model.advance()
    check(model.actors[1].health == 0 and model.actors[2].health == 0,
        "simultaneous strikes should allow simultaneous defeat")

    # Cooperative allies cannot damage one another; foes remain damageable.
    model.start(&"cooperative", 2)
    model.actors[1].x = 100
    model.actors[2].x = 120
    model.actors[3].x = 130
    ready_strike(model, 1)
    model.advance()
    check(model.actors[2].health == 20, "cooperative ally must be unharmed")
    check(model.actors[3].health == 35, "enemy should still take damage")
    check(not model.submit(0, command(3, 1, 1, 0, "heavy")), "actor cannot use a move outside its content definition")
    check(not model.submit(0, command(3, 1, 1, 0, "reverse")), "placeholder creature cannot use knight-only reverse strike")

    # A sweep may contact later in its active window, but only once per target.
    model.start(&"competitive", 2)
    model.actors[1].x = 100
    model.actors[2].x = 180
    ready_strike(model, 1)
    model.advance()
    check(model.actors[2].health == 20, "close swing pose must not hit a distant target")
    for step in range(int(rules.moves.swing.active / 3)): model.advance()
    check(model.actors[2].health == 15, "extended swing hits at visible sword contact beyond old reach")
    model.advance()
    check(model.actors[2].health == 15, "later sword contact must not damage the same target twice")
    check(model.actors[2].reaction == "hurt_a", "ordinary unblocked contact starts its reaction")
    var saved_x: int = model.actors[2].x
    for step in range(model.actors[2].stagger_remaining-1):
        model.submit(2, command(2, step + 1, model.tick, 1, "heavy"))
        model.advance()
        check(model.actors[2].x == saved_x and model.actors[2].remaining == 0,
            "staggered actor cannot move or attack")
    model.advance()
    check(model.actors[2].x == saved_x, "input consumed during stagger cannot fire later")
    check(model.submit(2, command(2, 50, model.tick, 1)), "fresh input after recovery accepted")
    model.advance()
    check(model.actors[2].x == saved_x + 2, "movement resumes after reaction")

    for facing in [1, -1]:
        for behind in [true, false]:
            model.start(&"competitive", 2)
            model.actors[1].x = 160
            model.actors[1].facing = facing
            model.actors[2].x = 160 + facing * (-35 if behind else 35)
            check(model.submit(1, command(1, 1, 0, 0, "reverse")), "reverse strike accepted")
            for step in range(1 + rules.moves.reverse.windup + rules.moves.reverse.active + rules.moves.reverse.recovery):
                model.advance()
            check(model.actors[1].facing == facing, "reverse strike must not turn the knight")
            check(model.actors[2].health == (17 if behind else 20),
                "reverse strike hits behind only, in either facing")

    # Guard faces the incoming blade, including a backward thrust.
    model.start(&"competitive", 2)
    model.actors[1].x = 160
    model.actors[2].x = 125
    model.actors[2].facing = 1
    model.actors[1].action = "reverse"
    model.actors[1].remaining = rules.moves.reverse.active + rules.moves.reverse.recovery + 1
    model.submit(2, command(2, 1, 0, 0, "block"))
    model.advance()
    check(model.actors[2].health == 20 and model.actors[2].reaction == "block",
        "correctly facing guard parries reverse damage and stays in its stance")
    check(model.actors[2].remaining == 0, "blocking reaction does not start an attack")

    for facing in [1, -1]:
        model.start(&"competitive", 2)
        model.actors[1].x = 160
        model.actors[1].facing = facing
        model.actors[2].x = 160 + facing * 135
        ready_strike(model, 1)
        for step in range(rules.moves.swing.active): model.advance()
        check(model.actors[2].health == 20, "target beyond the entire visible blade is missed")
    model.start(&"competitive", 2)
    model.actors[1].x = 100
    model.actors[2].x = 125
    model.actors[2].y = model.actors[1].y + rules.depth_tolerance + 1
    ready_strike(model, 1)
    for step in range(rules.moves.swing.active): model.advance()
    check(model.actors[2].health == 20, "sword cannot hit a target in a different lane")

    model.start(&"competitive", 2)
    model.actors[1].x = 100
    model.actors[2].x = 125
    model.actors[2].health = 1
    ready_strike(model, 1)
    model.advance()
    check(model.outcome() == "victory" and model.actors[2].down_remaining > 0,
        "lethal hit starts defeat and reports a win")
    check(not model.submit(2, command(2, 1, model.tick, 0, "swing")), "fallen actor cannot accept input")
    for step in range(model.actors[2].down_remaining): model.advance()
    check(model.actors[2].health == 0 and model.actors[2].down_remaining == 0,
        "fallen actor stays defeated after its animation finishes")
    model.actors[1].health = 0
    check(model.outcome() == "draw", "both teams down produces a draw")
    model.start(&"cooperative", 2)
    model.actors[1].health = 0
    check(model.outcome() == "ongoing", "cooperative fight continues while an ally lives")
    model.actors[2].health = 0
    check(model.outcome() == "defeat", "cooperative defeat requires all allies down")
    model.start(&"competitive", 2)
    check(model.actors[1].reaction_remaining == 0 and model.actors[2].down_remaining == 0,
        "restart clears reaction and defeat state")

    # Independent copies replay the same input to identical simulation state.
    var second: RefCounted = Model.new(rules)
    model.start(&"competitive", 2)
    second.start(&"competitive", 2)
    for current in range(100):
        var c: Dictionary = command(1, current + 1, current, 1 if current < 30 else 0,
            "swing" if current % 25 == 0 else "idle")
        model.submit(1, c)
        second.submit(1, c)
        model.advance()
        second.advance()
    check(model.snapshot() == second.snapshot(), "same inputs should produce same state")
    var copy: Dictionary = model.snapshot()
    copy.actors[1].health = 1
    check(model.actors[1].health != 1, "view snapshots must not mutate authoritative state")
    if failures == 0:
        print("PASS: authority, sweep contacts, single-hit limits, reverse directions, guards, stagger, defeat, both modes and replay")
    quit(0 if failures == 0 else 1)
