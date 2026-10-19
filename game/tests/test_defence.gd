extends SceneTree
const Model = preload("res://scripts/domain/combat_simulation.gd")
const Session = preload("res://scripts/session/local_session.gd")
var failures: int = 0
func check(condition: bool, message: String) -> void:
    if not condition:
        failures += 1
        push_error(message)

func input_for(model: RefCounted, action: String, direction: Vector2i = Vector2i.ZERO) -> void:
    model.submit(1, {"actor":1,"sequence":model.tick + 1,"tick":model.tick,
        "dx":direction.x,"dy":direction.y,"action":action})

func _initialize() -> void:
    var rules: Resource = load("res://content/foundation_rules.tres")
    var session: RefCounted = Session.new(rules)
    session.start(&"competitive", &"spear_lair")
    var last_attack: int = -1000
    var starts: int = 0
    var dodges: Dictionary = {}
    var directions: Dictionary = {}
    var destination: int = 166
    var spear: Dictionary = rules.moves.spear_thrust
    var duration: int = spear.windup + spear.active + spear.recovery
    for current in range(430): # includes the new off-screen approach before five attacks
        # Anticipated sidesteps through ordinary input, no health/AI overrides.
        # This fixture proves evasion/contact rules, not human reaction time.
        var live_thrust: bool = false
        for actor in session.simulation.actors.values():
            if actor.action == "spear_thrust" and actor.remaining>0: live_thrust=true
            if actor.action == "spear_thrust" and duration - actor.remaining == 0:
                var side: int = signi(int(session.simulation.actors[1].y)-int(actor.y))
                if side==0: side=1 if actor.y<=158 else -1
                destination = clampi(actor.y+12*side,139,177)
                dodges[current] = true
        if not live_thrust: destination=158 # recover floor space during the real gap
        var dy: int = signi(destination - int(session.simulation.actors[1].y))
        if abs(destination - int(session.simulation.actors[1].y)) < 2: dy = 0
        if dy: directions[dy] = true
        session.advance(Vector2i(0,dy), "idle")
        for event in session.simulation.events:
            if event.type == "attack" and event.move == "spear_thrust":
                check(session.simulation.tick - last_attack >= 30, "two spearmen must leave a response gap between attacks")
                last_attack = session.simulation.tick
                starts += 1
        check(session.simulation.actors[1].health == 20, "timed lane changes must avoid both live Troggs")
    check(starts >= 5 and dodges.size() >= 5 and directions.size() == 2, "fixture exercises repeated up/down dodges against both enemies")

    # Isolate one spearman to measure actual cadence through the AI/model boundary.
    session.start(&"competitive", &"spear_lair")
    session.simulation.actors[11].health = 0
    session.simulation.spawn_remaining = 0
    session.simulation.actors[1].facing = -1
    var attack_ticks: Array[int] = []
    for current in range(430):
        session.simulation.actors[1].health=10000
        session.simulation.actors[1].maximum=10000
        session.advance(Vector2i.ZERO,"idle")
        for event in session.simulation.events:
            if event.type == "attack" and event.actor == 10:
                attack_ticks.append(session.simulation.tick)
                check(session.simulation.actors[10].remaining == 25,
                    "unshortened spear stroke is the sampled 0.50s; contact has a separate tail")
    check(attack_ticks.size() >= 3 and attack_ticks[0] >= 25, "encounter entry leaves time to take control")
    for i in range(1,attack_ticks.size()):
        var seconds: float = float(attack_ticks[i] - attack_ticks[i-1]) / rules.tick_rate
        check(is_equal_approx(seconds,1.30), "unblocked contact cadence matches four consecutive montage gaps")

    # Close visual overlap is insufficient if the spear is in the adjacent lane.
    var model: RefCounted = Model.new(rules)
    for facing in [1,-1]:
        for depth in [5,6,12]:
            model.start(&"competitive",0,&"spear_lair")
            model.actors[10].x = 160 - facing * 120
            model.actors[10].facing = facing
            model.actors[1].x = 160
            model.actors[1].y = 166 + depth
            model.actors[10].action = "spear_thrust"
            model.actors[10].remaining = spear.active + spear.recovery + 1
            for tick in range(spear.active): model.advance()
            check(model.actors[1].health == (17 if depth == 5 else 20), "spear lane boundary works in both facings")

    # Heavy preparation, blade and first recovery segment are committed.
    # Last five recovery ticks allow a fresh evade/guard command.
    for phase in ["windup","active","recovery"]:
        for action in ["idle","block"]:
            model.start(&"competitive",2)
            input_for(model,"heavy")
            model.advance()
            if phase == "active":
                for step in range(rules.moves.heavy.windup): model.advance()
            elif phase == "recovery":
                for step in range(rules.moves.heavy.windup + rules.moves.heavy.active): model.advance()
            var x: int = model.actors[1].x
            input_for(model,action,Vector2i.RIGHT if action == "idle" else Vector2i.ZERO)
            model.advance()
            check(model.actors[1].remaining > 0 and model.actors[1].x == x and not model.actors[1].guarding,
                "heavy commitment cannot turn into a free evade/guard")


    model.start(&"competitive",2)
    model.actors[1].x = 100
    model.actors[2].x = 125
    model.actors[2].action = "swing"
    model.actors[2].remaining = rules.moves.swing.active + rules.moves.swing.recovery + 1
    model.advance()
    var x: int = model.actors[1].x
    for step in range(29):
        input_for(model,"idle",Vector2i.UP)
        model.advance()
    check(model.actors[1].x == x and model.actors[1].y == 166,
        "complete source hurt sequence remains committed under repeated movement")
    check(model.actors[1].reaction_remaining == 1,
        "the last protected hurt drawing is still visible")
    input_for(model,"idle",Vector2i.UP)
    model.advance()
    check(model.actors[1].y == 164 and model.actors[1].reaction_remaining == 0,
        "movement resumes exactly when the full hurt sequence completes")
    if failures == 0:
        print("PASS: repeated live dual-Trogg evasion, attack spacing, lane boundary, defensive cancels and full knight hurt recovery")
    quit(1 if failures else 0)
