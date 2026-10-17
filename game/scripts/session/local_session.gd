class_name LocalSession
extends RefCounted

const Simulation = preload("res://scripts/domain/combat_simulation.gd")
var simulation: RefCounted
var sequence: Dictionary = {}
var knight_profile: Dictionary = {}
var rival_profile: Dictionary = {}
var human_actors: Dictionary={1:1}

func _init(rules: Resource) -> void:
    simulation = Simulation.new(rules)

func start(mode: StringName, encounter: StringName = &"duel", overrides: Dictionary = {}) -> void:
    simulation.start(mode, 0, encounter, overrides)
    for actor in simulation.actors.values():
        if actor.team == 1 and actor.kind == "knight":
            for field in knight_profile: actor[field] = knight_profile[field]
    for actor in simulation.actors.values():
        if actor.team==2 and actor.kind=="black_knight":
            for field in rival_profile:actor[field]=rival_profile[field]
    sequence.clear()
    human_actors={1:1}

func command(actor_id: int, owner: int, direction: Vector2i, action: String, facing: int = 0) -> bool:
    var next: int = int(sequence.get(actor_id, 0)) + 1
    var input: Dictionary = {"actor": actor_id, "sequence": next,
        "tick": simulation.tick, "dx": direction.x, "dy": direction.y, "action": action}
    if facing != 0: input.facing = facing
    var accepted: bool = simulation.submit(owner, input)
    if accepted:
        sequence[actor_id] = next
    return accepted

func advance(direction: Vector2i, action: String,additional: Dictionary={}) -> void:
    command(1,int(human_actors.get(1,1)),direction,action)
    for id in human_actors:
        if id==1:continue
        var input: Dictionary=additional.get(id,{"direction":Vector2i.ZERO,"action":"idle"})
        command(id,human_actors[id],input.direction,input.action)
    # Derived from authoritative attack clocks; no hidden AI timer/replay state.
    var creature_reserved: bool = false
    for actor in simulation.actors.values():
        var profile: Resource = simulation.rules.actor_definitions[actor.kind]
        if actor.health <= 0 or profile.ai_style not in [&"spearman", &"axeman"]:
            continue
        var move: Dictionary = simulation.rules.moves[actor.action if actor.remaining > 0 else profile.ai_move]
        var duration: int = move.windup + move.active + move.recovery
        var elapsed: int = 100000
        if actor.remaining > 0:
            elapsed = duration - actor.remaining
        elif actor.cooldown_remaining > 0:
            # The shortest axe move conservatively reserves a little longer
            # after a chop. No hidden last-attack clock is needed for replay.
            elapsed = duration + int(profile.attack_cooldown_ticks) - int(actor.cooldown_remaining)
        if actor.get("attack_flow",{}).has("started"):
            elapsed = simulation.tick-int(actor.attack_flow.started)
        if elapsed < int(move.group_spacing): creature_reserved = true
    for id in simulation.actors:
        var actor: Dictionary = simulation.actors[id]
        if actor.owner != 0 or actor.health <= 0:
            continue
        var nearest: Dictionary = {}
        var nearest_distance: int = 100000
        for other_id in simulation.actors:
            var other: Dictionary = simulation.actors[other_id]
            if other.team == actor.team or other.health <= 0 or other.hidden_by != 0:
                continue
            var distance: int = abs(int(other.x) - int(actor.x)) + abs(int(other.y) - int(actor.y))
            if distance < nearest_distance:
                nearest_distance = distance
                nearest = other
        # A downed knight remains a possible second-strike target during its
        # finite kneeling death. Living opponents keep priority in native co-op.
        if nearest.is_empty():nearest=simulation.Executions.target(simulation,actor)
        if not nearest.is_empty() and nearest.health<=0:
            var definition: Resource=simulation.rules.actor_definitions[actor.kind]
            var dx: int=signi(int(nearest.x)-int(actor.x))
            var dy: int=signi(int(nearest.y)-int(actor.y)) if abs(int(nearest.y)-int(actor.y))>int(definition.ai_depth) else 0
            var facing: int=dx if dx else actor.facing
            var separation: int=abs(int(nearest.x)-int(actor.x))
            var minimum: int=mini(definition.ai_keep_distance if definition.ai_keep_distance>0 else definition.execution_ai_range/2,definition.execution_ai_range)
            var step_x: int=facing if separation>definition.execution_ai_range else 0
            if separation<minimum:
                step_x=-facing
                if actor.x+step_x*definition.movement_per_tick<22 or actor.x+step_x*definition.movement_per_tick>298:step_x=facing
            var movement:=Vector2i(step_x,dy)
            command(id,0,movement,definition.execution_ai_move if movement==Vector2i.ZERO else "idle",dx if dx else actor.facing)
            continue
        if nearest.is_empty():
            command(id, 0, Vector2i.ZERO, "idle")
        else:
            var dx: int = signi(int(nearest.x) - int(actor.x))
            var dy: int = signi(int(nearest.y) - int(actor.y)) if abs(int(nearest.y) - int(actor.y)) > 4 else 0
            var definition: Resource = simulation.rules.actor_definitions[actor.kind]
            if actor.grab_remaining > 0:
                command(id, 0, Vector2i.DOWN, "block")
                continue
            if definition.ai_style == &"charger":
                # Simulation owns edge turns and committed per-pass lane.
                command(id, 0, Vector2i.ZERO, "beast_charge", actor.facing)
                continue
            if definition.ai_style == &"ratman":
                if actor.held_target != 0 or actor.special_remaining > 0 or nearest.grab_remaining > 0 or nearest.hidden_by != 0:
                    command(id, 0, Vector2i.ZERO, "idle")
                    continue
                var separation: int = abs(int(nearest.x) - int(actor.x))
                var attack: String = "rat_leap" if separation > 50 or dy != 0 else ("rat_strike" if separation <= 40 else "rat_bite")
                command(id, 0, Vector2i.ZERO, attack, dx if dx else actor.facing)
                continue
            if definition.ai_style == &"snatcher":
                var separation: int = abs(int(nearest.x) - int(actor.x))
                var attack: String = "idle"
                var movement := Vector2i(0, dy)
                if separation > 100: movement.x = dx
                elif dy == 0: attack = "mud_grab" if separation < 60 else "mud_reach"
                command(id, 0, movement, attack, dx if dx else actor.facing)
                continue
            if definition.ai_style == &"dragon":
                var separation: int = abs(int(nearest.x) - int(actor.x))
                var attack: String = "idle"
                var movement := Vector2i.ZERO
                if actor.remaining == 0 and actor.special_remaining == 0:
                    if simulation.tick % 6 == 0:
                        movement.y = dy
                        var step_x: int = dx if separation > 60 else (-dx if separation < 20 else 0)
                        if actor.x+step_x*5 > 30 and actor.x+step_x*5 < 100: movement.x=step_x
                    # Fixed left-hand Dragon: rear/lower its neck, never turn or
                    # leap across the arena. Two-phase choice from LAB_027B.
                    if (separation < 140) != actor.dragon_raised:
                        attack = "dragon_flight" if not actor.dragon_raised else "dragon_lower"
                    elif dy == 0:
                        if nearest.x <= 100: attack = "dragon_foot"
                        elif not actor.dragon_raised: attack = "dragon_claw"
                        elif separation <= 70 and not actor.dragon_hit: attack = "dragon_bite"
                        else: attack = "dragon_breath"
                command(id, 0, movement, attack, 1)
                continue
            if definition.ai_style == &"guardian":
                var separation: int = abs(int(nearest.x) - int(actor.x))
                var attack: String = "idle"
                var movement := Vector2i(0,dy)
                if separation > 140: movement.x = dx
                elif dy == 0:
                    attack = "guardian_lunge" if separation <= 100 else ("guardian_strike" if separation <= 130 else "guardian_grab")
                command(id, 0, movement, attack, dx if dx else actor.facing)
                continue
            if definition.ai_style == &"rival":
                var separation: int = abs(int(nearest.x) - int(actor.x))
                var attack: String = "idle"
                var movement := Vector2i(0,dy)
                if separation > 58: movement.x = dx
                elif separation < 25: movement.x = -dx
                if separation <= 65 and dy == 0:
                    if nearest.remaining > 0 and simulation.tick % 3 != 0: attack = "block"
                    else: attack = "heavy" if actor.last_attack != "heavy" and separation < 45 else "lunge"
                command(id, 0, movement, attack, dx if dx else actor.facing)
                continue
            if definition.ai_style == &"drake":
                var separation: int = abs(int(nearest.x) - int(actor.x))
                var depth: int = abs(int(nearest.y) - int(actor.y))
                var attack: String = "balok_pounce"
                if separation <= 120 and depth <= int(definition.ai_depth):
                    if separation <= 70: attack = "balok_hop"
                    elif separation <= 80 and actor.last_attack != "balok_swipe": attack = "balok_swipe"
                    else: attack = "balok_maul"
                command(id, 0, Vector2i.ZERO, attack, dx if dx else actor.facing)
                continue
            if definition.ai_style == &"stalker":
                var separation: int = abs(int(nearest.x) - int(actor.x))
                var depth: int = abs(int(nearest.y) - int(actor.y))
                var movement := Vector2i(0, signi(int(nearest.y) - int(actor.y)) if depth > int(definition.ai_depth) else 0)
                var attack: String = "idle"
                if separation > int(definition.ai_preferred_range): movement.x = dx
                elif separation < int(definition.ai_keep_distance): movement.x = -dx
                elif depth <= int(definition.ai_depth):
                    attack = definition.ai_secondary_move if separation >= int(definition.ai_close_range) and actor.last_attack != definition.ai_secondary_move else definition.ai_move
                command(id, 0, movement, attack, dx if dx else actor.facing)
                continue
            if definition.ai_style in [&"spearman", &"axeman"]:
                var separation: int = abs(int(nearest.x) - int(actor.x))
                dy = signi(int(nearest.y) - int(actor.y)) if abs(int(nearest.y) - int(actor.y)) > int(definition.ai_depth) else 0
                var movement := Vector2i(0, dy)
                var attack: String = "idle"
                if separation > int(definition.ai_preferred_range):
                    movement.x = dx
                elif separation < int(definition.ai_keep_distance) and actor.x - dx > 22 and actor.x - dx < 298:
                    movement.x = -dx
                elif dy == 0:
                    attack = definition.ai_secondary_move if definition.ai_style == &"axeman" and separation > int(definition.ai_close_range) else definition.ai_move
                if attack != "idle" and actor.remaining == 0 and actor.stagger_remaining == 0 and actor.cooldown_remaining <= 1:
                    if creature_reserved:
                        attack = "idle"
                    else:
                        creature_reserved = true
                # Keep facing the knight while approaching or backing away. Native timings
                # and target selection remain provisional, using the original profile.
                command(id, 0, movement, attack, dx if dx else actor.facing)
                continue
            var chosen: String = definition.ai_move if abs(int(nearest.x) - int(actor.x)) < int(definition.ai_preferred_range) and abs(int(nearest.y) - int(actor.y)) < 12 else "idle"
            command(id, 0, Vector2i(dx, dy) if chosen == "idle" else Vector2i(dx, 0), chosen)
    simulation.advance()
