class_name CombatSimulation
extends RefCounted

const Knight = preload("res://scripts/domain/knight_combat.gd")
const Ratman = preload("res://scripts/domain/ratman_combat.gd")
const Balok = preload("res://scripts/domain/balok_combat.gd")
const Math = preload("res://scripts/domain/character_math.gd")

const EncounterScaling = preload("res://scripts/domain/encounter_scaling_host.gd")
const EntryPlacement = preload("res://scripts/domain/entry_placement_host.gd")
const AttackFlow = preload("res://scripts/domain/attack_flow.gd")
const Beast = preload("res://scripts/domain/war_beast.gd")
const Finishers = preload("res://scripts/domain/combat_finishers.gd")
const RatHold = preload("res://scripts/domain/ratman_hold.gd")
const HoldBehaviors = preload("res://scripts/domain/hold_behavior_host.gd")
const Executions = preload("res://scripts/domain/kneeling_execution.gd")
const Knockback = preload("res://scripts/domain/knockback.gd")
const Guardian = preload("res://scripts/domain/guardian_combat.gd")

# Pure fixed-tick state. Input adapters submit data; rendering never changes rules.
# These prototype timings are provisional, not an original-game parity claim.
var rules: Resource
var mode: StringName = &"competitive"
var tick: int = 0
var actors: Dictionary = {}
var last_sequence: Dictionary = {}
var pending: Dictionary = {}
var events: Array[Dictionary] = []
var encounter: StringName = &"duel"
var spawn_remaining: int = 0
var next_creature_id: int = 10
var projectiles: Array[Dictionary] = []
var next_projectile_id: int = 1
var encounter_settings: Dictionary = {}
var rat_perch: Dictionary = {}
var ratman_wait_steps: int = 0
var knight_random_state: int = 0x4b4e4947
var beast_lane_toggle: int = 0
var balok_finish_toggle: int = 0
var entry_state: Dictionary = {}

func _init(rule_set: Resource) -> void:
    rules = rule_set

func start(new_mode: StringName, second_player_peer: int = 0, new_encounter: StringName = &"duel", overrides: Dictionary = {}) -> void:
    assert(new_mode in [&"competitive", &"cooperative"])
    mode = new_mode
    tick = 0
    last_sequence.clear()
    pending.clear()
    events.clear()
    projectiles.clear()
    next_projectile_id = 1
    rat_perch = {}
    ratman_wait_steps = 0
    knight_random_state = maxi(2,int(overrides.get("combat_seed",0x4b4e4947)) & 0xffffffff)
    beast_lane_toggle = 0
    balok_finish_toggle = 0
    entry_state = {}
    encounter = new_encounter
    encounter_settings = rules.encounters.get(String(encounter), {}).duplicate(true)
    for key in ["count", "concurrent"]:
        if overrides.has(key): encounter_settings[key] = clampi(int(overrides[key]), 1, 60 if key == "count" else 4)
    if rules.encounters.get(String(encounter),{}).get("creature","")=="black_knight":
        encounter_settings["knight_difficulty"]=clampi(int(overrides.get("knight_difficulty",0)),0,7)
    encounter_settings["moon_phase"] = clampi(int(overrides.get("moon_phase", 1)), 0, 7)
    if encounter_settings.has("entry_profile"):
        entry_state=EntryPlacement.prepare(rules,String(encounter_settings.entry_profile),String(overrides.get("arena_site","")),2 if mode==&"cooperative" else 1)
    spawn_remaining = 0
    next_creature_id = 10
    actors = {
        1: make_actor(1, 1, 1, "knight", Vector2i(82, 166), 1),
        2: make_actor(2, second_player_peer, 2 if mode == &"competitive" else 1,
                      "knight", Vector2i(212, 166), -1)
    }
    if mode == &"cooperative":
        actors[3] = make_actor(3, 0, 2, "troll", Vector2i(278, 169), -1)
    if encounter != &"duel":
        assert(rules.encounters.has(String(encounter)))
        var content: Dictionary = encounter_settings
        actors = {1: make_actor(1, 1, 1, "knight", Vector2i(150, 166), 1)}
        if mode == &"cooperative":
            actors[2] = make_actor(2, second_player_peer, 1, "knight", Vector2i(180, 166), -1)
        for actor in actors.values():
            actor.health = int(content.knight_health)
            actor.maximum = int(content.knight_health)
        spawn_remaining = int(content.count)
        if content.creature == "ratman":
            # LAB_018C creates LAB_0870 before the wave. +52 converts the
            # original depth to this importer's foot anchor. The flat arena
            # currently uses source entry102; obstacle-derived depth is pending.
            rat_perch = {"x":160,"y":154,"height":-98,"owner":0}
        fill_wave_slots()

func make_actor(id: int, owner: int, team: int, kind: String, position: Vector2i, facing: int) -> Dictionary:
    var definition: Resource = rules.actor_definitions[kind]
    var maximum: int = definition.maximum_health
    if kind == "ratman": maximum = 7 if encounter_settings.get("moon_phase",1) == 0 else (12 if encounter_settings.get("moon_phase",1) == 4 else 5)
    var result: Dictionary = {"id": id, "owner": owner, "team": team, "kind": kind, "x": position.x,
            "y": position.y, "facing": facing, "health": maximum, "maximum": maximum,
            "action": "idle", "last_attack": "", "attack_flow": {}, "height": 0,
            "leap_from_x": position.x, "leap_from_y": position.y, "leap_to_x": position.x, "leap_to_y": position.y, "remaining": 0, "guarding": false, "flash": 0,
            "reaction": "", "reaction_remaining": 0, "stagger_remaining": 0, "down_remaining": 0, "down_duration": 0, "hit_targets": [],
            "damage_bonus": 0, "moon_damage_shift":0, "defeat_clip": "defeat", "daggers": definition.maximum_daggers,
            "dragon_damage_shift": 0, "grabbed_by": 0, "grab_remaining": 0,
            "dragon_raised": false, "dragon_hit": false, "rest_height": 0, "endurance_stat": 1,
            "leap_from_height": 0, "leap_to_height": 0,
            "held_target": 0, "hold_kind": "", "hold_elapsed": 0,
            "rat_phase_elapsed":0,"rat_perch_near":false,
            "special_clip": "", "special_remaining": 0, "special_duration": 0,
            "hidden_by": 0, "visual_kind": "", "terminal_clip": "",
            "terminal_elapsed":71,"terminal_duration":72,
            "rat_tree": false, "beast_pass": 0, "beast_phase": 0,
            "entering": false, "beast": {}, "motion": {},
            "interaction": {}, "reaction_duration": 0, "vanished": false,
            "cooldown_remaining": definition.entry_attack_delay_ticks}
    if kind=="black_knight":Knight.state(result)
    if kind=="ratman":Ratman.state(result)
    if kind=="balok":Balok.state(result)
    return result

func submit(peer: int, command: Dictionary) -> bool:
    # This is also the future network authority boundary. No remote code/resources.
    for field in ["actor", "sequence", "tick", "dx", "dy"]:
        if typeof(command.get(field)) != TYPE_INT:
            return false
    var id: int = command.actor
    if not actors.has(id) or actors[id].owner != peer or actors[id].health <= 0:
        return false
    if command.tick != tick or command.sequence <= int(last_sequence.get(id, -1)):
        return false
    if abs(command.dx) > 1 or abs(command.dy) > 1:
        return false
    if command.has("facing") and (typeof(command.facing) != TYPE_INT or command.facing not in [-1, 1]):
        return false
    if typeof(command.get("action")) != TYPE_STRING:
        return false
    if command.action not in ["idle", "block"] and not rules.moves.has(command.action):
        return false
    var definition: Resource = rules.actor_definitions[actors[id].kind]
    if command.action == "block" and not definition.can_block:
        return false
    if command.action == "dagger" and actors[id].daggers <= 0:
        return false
    if command.action not in ["idle", "block"] and not command.action in definition.allowed_moves:
        return false
    last_sequence[id] = command.sequence
    pending[id] = command.duplicate(true)
    return true

func advance() -> void:
    events.clear()
    Finishers.advance(self)
    Beast.advance(self)
    # Stable actor ordering makes same seed/state/commands repeatable.
    var ids: Array = actors.keys()
    ids.sort()
    var strikes: Array[Dictionary] = []
    for id in ids:
        var actor: Dictionary = actors[id]
        actor.height = actor.rest_height
        actor.flash = maxi(0, actor.flash - 1)
        actor.cooldown_remaining = maxi(0, actor.cooldown_remaining - 1)
        if actor.health <= 0:
            actor.down_remaining = maxi(0, actor.down_remaining - 1)
            Knockback.advance(actor,tick,rules.knockback)
            if actor.hidden_by!=0 and actors.get(actor.hidden_by,{}).get("special_remaining",0)>0:
                actor.down_remaining=maxi(2,actor.down_remaining)
            if actor.get("down_stop",0)>0 and actor.down_duration-actor.down_remaining>=actor.down_stop:
                actor.down_remaining=0
            if actor.kind == "guardian" and actor.down_remaining == 0: actor.vanished = true
            continue
        if not actor.get("beast",{}).is_empty(): continue
        if not actor.interaction.is_empty(): continue
        if actor.grabbed_by != 0 and not actors.get(actor.grabbed_by, {}).get("interaction", {}).is_empty(): continue
        var command: Dictionary = pending.get(id, {})
        if actor.entering and (actor.x < 22 or actor.x > 298):
            # Standard Trogg/Troll entries keep walking from the source list's
            # off-screen x. Do not clamp them straight onto the arena floor.
            actor.x += int(rules.actor_definitions[actor.kind].movement_per_tick)*actor.facing
            if (actor.facing > 0 and actor.x >= 28) or (actor.facing < 0 and actor.x <= 292):
                actor.entering = false
            continue
        actor.entering = false
        if actor.special_remaining > 0:
            actor.special_remaining -= 1
            if actor.kind == "ratman" and actor.special_clip == "rat_air":
                advance_leap(actor, rules.moves.rat_retreat, actor.special_duration-actor.special_remaining)
            if actor.special_remaining == 0:
                var ended_clip: String=actor.special_clip
                actor.special_clip = ""
                release_rat_perch(actor)
                actor.cooldown_remaining = rules.actor_definitions[actor.kind].attack_cooldown_ticks
                for other in actors.values():
                    if other.hidden_by != id: continue
                    if other.health > 0: other.hidden_by = 0
                    elif actor.kind=="ratman" and ended_clip in ["rat_throw_finish","rat_squeeze_finish"]:
                        settle_rat_victim(actor,other,ended_clip)
                    elif actor.kind=="dragon" and ended_clip=="execution_bite":
                        other.hidden_by=0;other.vanished=true;other.down_remaining=0
            continue
        if actor.hidden_by != 0 and actor.grab_remaining == 0:
            var finisher: Dictionary = actors.get(actor.hidden_by, {})
            if not finisher.is_empty() and finisher.health > 0 and finisher.special_remaining > 0: continue
            actor.hidden_by = 0
        if actor.held_target != 0:
            # The victim's authoritative command drives escape/counter/expiry.
            continue
        if actor.grab_remaining > 0:
            var holder: Dictionary = actors.get(actor.grabbed_by, {})
            var escaped: bool = holder.is_empty() or holder.health <= 0 or (command.get("action", "") == "block" and command.get("dy", 0) > 0)
            if not holder.is_empty() and holder.kind == "ratman":
                advance_rat_hold(holder, actor, escaped)
                continue
            if escaped:
                actor.grab_remaining = 0
                actor.grabbed_by = 0
                actor.stagger_remaining = 0
                events.append({"type": "escape", "actor": id})
            else:
                actor.grab_remaining -= 1
                if actor.grab_remaining == 0:
                    var amount: int = actor.health if holder.kind == "mudman" else mini(6, actor.health)
                    actor.health -= amount
                    actor.grabbed_by = 0
                    actor.flash = 7
                    if actor.health == 0: knock_down(actor, "defeat")
                    events.append({"type": "damage", "actor": id, "attacker": holder.id, "amount": amount, "move": "hold", "blocked": false})
                continue
        if actor.reaction_remaining > 0:
            actor.reaction_remaining -= 1
            Knockback.advance(actor,tick,rules.knockback)
            if actor.reaction_remaining == 0:
                actor.reaction = ""
                actor.visual_kind = ""
        if actor.stagger_remaining > 0:
            actor.stagger_remaining -= 1
            # The expiry step can act before contact collection. Otherwise a
            # live blade can re-hit an unprotected actor that is still blocked.
            if actor.stagger_remaining > 0: continue
        # Content defines preparation/recovery commitment; live blades remain locked.
        if actor.remaining > 0 and rules.actor_definitions[actor.kind].can_cancel_attacks and not command.is_empty():
            var evading: bool = command.action == "block" or (command.action == "idle" and (command.dx != 0 or command.dy != 0))
            if evading and AttackFlow.cancelable(rules,actor):
                actor.remaining = 0
                actor.action = "idle"
                actor.attack_flow = {}
        if actor.remaining == 0 and not command.is_empty() and (command.action != "idle" or command.dx != 0 or command.dy != 0):
            actor.reaction = ""
            actor.reaction_remaining = 0
            actor.visual_kind = ""
        actor.guarding = command.get("action", "idle") == "block" and actor.remaining == 0
        if actor.remaining > 0:
            actor.remaining -= 1
            var move: Dictionary = move_for(actor)
            if actor.kind=="balok" and actor.action in Balok.FLIGHTS and actor.remaining==move.recovery:
                Balok.land(rules,actor,tick)
            if actor.attack_flow.get("branch","") == "contact":
                if actor.remaining == 0:
                    actor.action = "idle"
                    actor.cooldown_remaining = rules.actor_definitions[actor.kind].attack_cooldown_ticks
                continue
            if actor.remaining >= int(move.active) + int(move.recovery) and int(move.get("windup_step", 0)) != 0:
                var step: int = int(move.windup_step)
                if move.has("windup_distance"):
                    # Rescale the existing total advance with the phase clock.
                    # Integer differences preserve the endpoint and both facings.
                    var age: int = int(move.windup)+int(move.active)+int(move.recovery)-actor.remaining
                    step = int(int(move.windup_distance)*age/int(move.windup))-int(int(move.windup_distance)*(age-1)/int(move.windup))
                actor.x = clampi(actor.x + step * int(actor.facing), 22, 298)
            if actor.remaining <= int(move.recovery) + int(move.active) and actor.remaining > int(move.recovery):
                var elapsed: int = int(move.recovery) + int(move.active) - actor.remaining
                if move.has("leap_range"): advance_leap(actor, move, elapsed + 1)
                if move.has("charge_speed"):
                    advance_beast(actor, elapsed)
                if actor.action == "dagger":
                    if elapsed == 0: release_dagger(actor)
                else:
                    if move.get("ground_fire", false) and (elapsed == 0 or (move.windup == 0 and elapsed == 1)): release_fire(actor, move)
                    strikes.append({"attacker": actor, "move": move, "elapsed": elapsed})
            elif actor.kind == "ratman" and actor.action == "rat_leap" and actor.remaining <= int(move.recovery):
                actor.rest_height = actor.leap_to_height
                actor.height = actor.rest_height
                if actor.rat_tree:
                    var watched: Dictionary=nearest_opponent(actor)
                    actor.rat_perch_near=not watched.is_empty() and abs(watched.x-actor.x)<60
                    # Only a completed journey to the reserved tree enables
                    # the rope's original contact points. Ground landings do not.
                    for other in actors.values():
                        if other.team == actor.team or other.health <= 0 or other.grab_remaining > 0 or other.hidden_by != 0: continue
                        var box: Rect2 = hurt_box_for(other)
                        for p in rules.geometry.ratman.points_for("rat_perch", 1 if actor.rat_perch_near else 0, 2):
                            if abs(other.y-actor.y) <= 5 and box.has_point(Vector2(actor.x+p[0]*actor.facing, actor.y+actor.height+p[1])):
                                start_rat_hold(actor, other, "squeeze", 600)
                                break
                        if actor.held_target != 0: break
                if actor.held_target != 0: continue
            if actor.remaining == 0:
                if actor.kind == "ratman" and actor.rat_tree:
                    release_rat_perch(actor)
                    # LAB_0260 leaves the perch by aiming an ordinary flight.
                    actor.action = "rat_leap"
                    actor.rat_tree = false
                    aim_leap(actor, rules.moves.rat_leap, false)
                    var flight: Dictionary=move_for(actor)
                    actor.remaining = int(flight.active)+int(flight.recovery)
                    actor.hit_targets = []
                    continue
                if actor.kind == "ratman": actor.rest_height = actor.leap_to_height if actor.action == "rat_leap" else actor.rest_height
                if actor.kind=="balok":Balok.finish(actor)
                actor.action = "idle"
                if actor.kind != "war_beast": actor.cooldown_remaining = rules.actor_definitions[actor.kind].attack_cooldown_ticks
        elif not command.is_empty():
            var dx: int = command.dx
            var dy: int = command.dy
            if command.has("facing"):
                actor.facing = command.facing
            elif dx:
                actor.facing = signi(dx)
            var definition: Resource = rules.actor_definitions[actor.kind]
            if actor.kind != "war_beast" and not (actor.kind in ["ratman","balok"] and (actor.x < 22 or actor.x > 298)):
                actor.x = Knockback.walk_x(actor.x,dx * int(definition.movement_per_tick))
            if actor.kind != "war_beast": actor.y = clampi(actor.y + dy * int(definition.movement_per_tick), 139, 177)
            if rules.moves.has(command.action) and actor.cooldown_remaining == 0:
                var move: Dictionary = rules.moves[command.action]
                if actor.kind == "ratman" and not actor.terminal_clip.is_empty():
                    actor.rest_height = 0
                    actor.height = 0
                if actor.kind=="balok" and command.action in Balok.FLIGHTS:
                    if not Balok.begin(rules,actor,nearest_opponent(actor),tick):continue
                actor.action = command.action
                actor.terminal_clip = ""
                actor.last_attack = command.action
                if actor.kind=="balok" and actor.action in Balok.FLIGHTS:move=move_for(actor)
                elif move.has("leap_range"):
                    aim_leap(actor, move)
                    if actor.kind=="ratman":move=move_for(actor)
                if actor.action == "beast_charge": begin_beast_pass(actor)
                if actor.kind == "dragon" and actor.action in ["dragon_bite", "dragon_breath"]: actor.dragon_hit = false
                actor.remaining = int(move.windup) + int(move.active) + int(move.recovery)
                actor.hit_targets = []
                AttackFlow.begin(rules,actor,tick)
                actor.reaction = ""
                actor.reaction_remaining = 0
                events.append({"type": "attack", "actor": id, "move": actor.action})
                if actor.kind=="guardian" and actor.action in ["guardian_strike","guardian_grab"]:
                    Guardian.begin(self,actor,actor.action)
    # Resolve all input/positions/guards before damage. Simultaneous strikes
    # are collected before health changes, avoiding lower-ID attack priority.
    var hits: Array[Dictionary] = []
    for strike in strikes:
        hits.append_array(collect_hits(strike.attacker, strike.move, strike.elapsed))
    hits.append_array(advance_projectiles())
    var execution_survivors: Dictionary={}
    for hit in hits:
        if hit.get("execution",false):execution_survivors[hit.attacker]=Executions.survives_hits(self,actors[hit.attacker],hits)
    for hit in hits:
        var target: Dictionary = actors[hit.actor]
        if target.health<=0:
            if hit.get("execution",false) and execution_survivors.get(hit.attacker,false):Executions.apply(self,actors[hit.attacker],target)
            continue
        if target.health <= 0 or target.hidden_by != 0: continue
        var damage: int = mini(int(target.health), int(hit.amount))
        var hit_move: Dictionary = rules.moves.get(hit.move, {})
        if hit_move.has("grab_ticks") and actors[hit.attacker].kind == "ratman" and target.grab_remaining == 0:
            start_rat_hold(actors[hit.attacker], target, hit_move.get("hold_kind", "ride"), (6+int(target.endurance_stat))*6)
            continue
        if damage == 0:
            if hit.blocked:
                target.reaction = "block"
                target.reaction_remaining = rules.guard_feedback_ticks
                events.append({"type": "parry", "actor": target.id, "attacker": hit.attacker})
            continue
        # drakeLandsOnTarget knocks out the knight on a completed landing.
        if hit.move in ["balok_pounce","balok_hop"] and target.kind == "knight": damage = target.health
        if not target.interaction.is_empty(): Finishers.interrupt(self,target)
        hit.resolved = true
        hit.lethal = damage >= target.health
        target.health -= damage
        target.motion={}
        if bool(hit_move.get("turn_away", false)): target.facing = -actors[hit.attacker].facing
        if hit.move in ["dragon_foot","ground_fire"]:target.facing=-1
        target.height = 0
        target.flash = 7
        events.append({"type": "damage", "actor": target.id, "amount": damage,
            "attacker": hit.attacker, "move": hit.move, "blocked": hit.blocked})
        if target.kind in ["giant_troll","balok"] and hit.has("x") and hit.has("y"):
            # Retail stalker/drake hitSpark is a separate contact-anchored drawing.
            # Keep it out of authoritative actor/projectile state.
            events.append({"type":"hit_effect","actor":target.id,"effect":"blood_burst",
                "x":hit.x,"y":hit.y,"facing":actors[hit.attacker].facing})
        if target.health == 0:
            var definition: Resource = rules.actor_definitions[target.kind]
            knock_down(target, definition.defeat_clips.get(hit.move, "defeat"))
            var source: Dictionary = actors[hit.attacker]
            if target.kind == "knight": select_player_death(target,source,hit.move)
            var mutual: bool = hits.any(func(other: Dictionary) -> bool: return other.attacker == target.id)
            if target.kind == "knight":
                if source.kind == "trogg_spear" and not mutual: Finishers.begin(self,source,target,"spear")
                if source.kind == "balok" and hit.move == "balok_maul" and not mutual: Finishers.begin(self,source,target,"balok")
                if hit.move in ["troll_smash","balok_pounce","balok_hop"]: Finishers.flung(self,target)
                if source.kind == "mudman" and not mutual: Finishers.begin(self,source,target,"mud")
            if actors[hit.attacker].kind == "dragon": dragon_finish(actors[hit.attacker], target, hit.move)
            if actors[hit.attacker].kind == "war_beast" and actors[hit.attacker].health>0 and not hits.any(func(other: Dictionary) -> bool: return other.attacker == target.id):
                beast_finish(actors[hit.attacker], target)
            events.append({"type": "down", "actor": target.id})
        elif hit.blocked:
            target.reaction = "block"
            target.reaction_remaining = rules.guard_feedback_ticks
        else:
            # Hits interrupt preparation/recovery. Strikes already collected in
            # this same tick still land, preserving simultaneous damage.
            if target.kind=="balok":Balok.interrupt(target)
            target.action = "idle"
            target.attack_flow = {}
            target.remaining = 0
            if rules.actor_definitions[target.kind].reset_cooldown_on_hit:
                target.cooldown_remaining = 0
            target.guarding = false
            target.visual_kind = ""
            target.reaction = rules.actor_definitions[target.kind].reaction_clips.get(hit.move,
                "hurt_b" if hit.move == "heavy" else "hurt_a")
            target.reaction_remaining = rules.recovery.duration(target.kind,target.reaction,rules.actor_definitions[target.kind].reaction_ticks)
            target.reaction_duration = target.reaction_remaining
            AttackFlow.reaction(rules,target,hit.move)
            target.stagger_remaining = rules.actor_definitions[target.kind].stagger_ticks
            if target.kind!="knight" and rules.recovery.committed(target.kind,target.reaction):
                target.stagger_remaining=target.reaction_remaining
            if target.kind == "war_beast":
                Beast.interrupt(self,target)
                Beast.hurt(target, hit.move)
            if target.kind == "dragon": target.dragon_hit = true
            if target.kind == "ratman":
                release_rat_perch(target)
                target.rest_height = 0
            if actors[hit.attacker].kind == "war_beast" and target.kind == "knight":
                target.visual_kind = "war_beast"
                target.reaction = "impact_same" if target.facing == actors[hit.attacker].facing else "impact_opposite"
                target.reaction_remaining = 42
                target.stagger_remaining = 42
                target.reaction_duration = 42
            if target.kind == "knight":
                if hit.move == "spear_thrust":
                    target.reaction="hurt_a";target.reaction_remaining=36;target.reaction_duration=36
                if hit.move in ["balok_swipe","troll_sweep","guardian_lunge","dragon_foot","ground_fire"]:
                    start_hop_recovery(target,1 if hit.move in ["dragon_foot","ground_fire"] else actors[hit.attacker].facing)
                if hit.move in ["rat_strike","rat_bite"]:
                    target.visual_kind="ratman"
                    target.reaction="victim_strike" if hit.move=="rat_strike" else "victim_bite"
                    target.reaction_remaining=36;target.reaction_duration=36
                if hit.move == "balok_maul": Finishers.begin(self,actors[hit.attacker],target,"balok")
                if actors[hit.attacker].kind == "mudman": Finishers.begin(self,actors[hit.attacker],target,"mud")
                # Decide commitment after special reactions have been selected.
                # Ratman victim/Beast impact/hop paths retain their own clocks.
                if rules.recovery.committed(target.kind,target.reaction):
                    target.stagger_remaining=target.reaction_remaining
            if hit_move.has("grab_ticks") and target.hidden_by == 0:
                target.grabbed_by = hit.attacker
                target.grab_remaining = int(hit_move.grab_ticks)
    for hit in hits:
        var source: Dictionary = actors[hit.attacker]
        if source.kind == "war_beast" and source.health > 0 and source.beast.is_empty() and int(hit.amount) > 0:
            Beast.impact(source)
    AttackFlow.settle(rules,actors,hits,tick)
    Ratman.contacts(self,hits)
    pending.clear()
    tick += 1
    fill_wave_slots()

func start_hop_recovery(actor: Dictionary, direction: int = 1) -> void:
    actor.attack_flow = {}
    actor.visual_kind="knight_finishes";actor.reaction="hop"
    actor.action="idle";actor.remaining=0;actor.guarding=false
    actor.reaction_duration=rules.recovery.duration("knight_finishes","hop",54)
    actor.reaction_remaining=actor.reaction_duration
    actor.stagger_remaining=actor.reaction_duration
    Knockback.start(actor,direction,rules.knockback,tick)

func knock_down(actor: Dictionary, clip: String) -> void:
    actor.attack_flow = {}
    actor.motion={}
    Finishers.interrupt(self,actor)
    if actor.kind == "war_beast": Beast.interrupt(self,actor)
    if actor.kind == "ratman":
        release_rat_perch(actor)
        actor.rest_height = 0
        actor.height = 0
    for other in actors.values():
        if other.hidden_by != actor.id: continue
        if other.health > 0: other.hidden_by = 0
        elif actor.kind=="ratman" and actor.special_clip in ["rat_throw_finish","rat_squeeze_finish"]:
            settle_rat_victim(actor,other,actor.special_clip)
        elif actor.kind=="dragon":
            other.hidden_by=0;other.visual_kind="death_knight";other.defeat_clip="defeat"
            other.down_duration=rules.death_frames.duration("death_knight","defeat");other.down_remaining=other.down_duration
    if actor.held_target != 0:
        var victim: Dictionary = actors.get(actor.held_target, {})
        if not victim.is_empty():
            victim.grabbed_by = 0
            victim.grab_remaining = 0
            victim.hidden_by = 0
        actor.held_target = 0
    actor.action = "down"
    actor.remaining = 0
    actor.guarding = false
    actor.reaction = ""
    actor.reaction_remaining = 0
    actor.visual_kind = ""
    actor.stagger_remaining = 0
    actor.grabbed_by = 0
    actor.grab_remaining = 0
    actor.defeat_clip = clip
    actor.down_stop = 0
    actor.down_remaining = rules.actor_definitions[actor.kind].defeat_duration(clip)
    actor.down_duration = actor.down_remaining
    if actor.kind == "dragon":
        actor.rest_height=0;actor.height=0
    if actor.kind == "trogg_hammer":
        actor.visual_kind="hammer_finishes"
    if actor.kind == "balok": actor.visual_kind="balok_finishes"
    var family: String = "death_" + ("knight" if actor.kind=="black_knight" else String(actor.kind))
    if rules.death_frames.clocks.has(family):
        actor.visual_kind=family
        actor.down_remaining=rules.death_frames.duration(family,clip)
        actor.down_duration=actor.down_remaining
    if actor.kind == "war_beast": Beast.death(actor,clip)

func select_player_death(victim: Dictionary, source: Dictionary, move: String) -> void:
    var family: String="death_knight"
    var clip: String=victim.defeat_clip
    if source.kind=="ratman" and move in ["rat_strike","rat_bite"]:
        family="death_rat_victim";clip="strike" if move=="rat_strike" else "bite"
    elif move in ["troll_sweep","balok_swipe","guardian_lunge","dragon_foot","ground_fire"]:
        clip="hop"
    elif source.kind=="war_beast":
        family="war_beast";clip="ejected" if victim.facing==source.facing else "fallen_front"
    victim.visual_kind=family;victim.defeat_clip=clip
    victim.down_duration=rules.death_frames.duration(family,clip)
    victim.down_remaining=victim.down_duration
    if clip=="hop":Knockback.start(victim,1 if move in ["dragon_foot","ground_fire"] else source.facing,rules.knockback,tick)

func aim_leap(actor: Dictionary, move: Dictionary, allow_tree: bool = true) -> void:
    # Lock an authoritative opponent position once. Inputs cannot steer in flight.
    var nearest: Dictionary = {}
    var distance: int = 100000
    var ids: Array = actors.keys()
    ids.sort()
    for id in ids:
        var other: Dictionary = actors[id]
        if other.health <= 0 or other.team == actor.team: continue
        var candidate: int = abs(int(other.x) - int(actor.x)) + abs(int(other.y) - int(actor.y))
        if candidate < distance:
            distance = candidate
            nearest = other
    actor.leap_from_x = actor.x
    actor.leap_from_y = actor.y
    actor.leap_from_height = actor.rest_height
    actor.leap_to_height = 0
    actor.leap_to_x = clampi(int(nearest.get("x", actor.x)), actor.x - int(move.leap_range), actor.x + int(move.leap_range))
    actor.leap_to_x = clampi(actor.leap_to_x, 22, 298)
    actor.leap_to_y = int(nearest.get("y", actor.y))
    if actor.kind == "ratman":
        actor.rat_tree = allow_tree and not rat_perch.is_empty() and rat_perch.owner == 0
        if actor.rat_tree:
            rat_perch.owner = actor.id
            actor.leap_to_x = rat_perch.x
            actor.leap_to_y = rat_perch.y + 3
            actor.leap_from_height = -20
            actor.leap_to_height = rat_perch.height
        actor.rest_height = 0
    if actor.kind == "dragon":
        actor.leap_to_x = 100
        actor.leap_from_height = actor.rest_height
        actor.leap_to_height = int(move.transition_height)
        actor.dragon_raised = actor.action == "dragon_flight"

func move_for(actor: Dictionary) -> Dictionary:
    return Ratman.move(rules,actor) if actor.kind=="ratman" else Balok.move(rules,actor)

func advance_leap(actor: Dictionary, move: Dictionary, progress: int) -> void:
    if actor.kind=="balok" and not actor.get("balok",{}).get("flight",{}).is_empty():
        Balok.advance(rules,actor,progress)
        return
    var duration: int = move.active
    if actor.kind == "dragon":
        # The original calls this flight, but it raises/lowers the Dragon's neck
        # at the left edge. Preserve the terminal height between actions.
        actor.x = int(actor.leap_from_x) + int((actor.leap_to_x-actor.leap_from_x)*progress/duration)
        actor.rest_height = int(actor.leap_from_height) + int((actor.leap_to_height-actor.leap_from_height)*progress/duration)
        actor.height = actor.rest_height
        if progress % 6 == 0:
            var destination: int = int(actor.leap_to_y)
            actor.y += clampi(destination-int(actor.y), -5, 5)
        return
    actor.x = int(actor.leap_from_x) + int((actor.leap_to_x - actor.leap_from_x) * progress / duration)
    actor.y = int(actor.leap_from_y) + int((actor.leap_to_y - actor.leap_from_y) * progress / duration)
    var base: int = int(actor.leap_from_height) + int((actor.leap_to_height-actor.leap_from_height)*progress/duration)
    actor.height = base-int(4 * int(move.leap_peak) * progress * (duration - progress) / (duration * duration))
    if progress == duration: actor.rest_height = actor.leap_to_height

func collect_hits(attacker: Dictionary, move: Dictionary, elapsed: int = 0) -> Array[Dictionary]:
    var hits: Array[Dictionary] = []
    if move.get("no_contact", false): return hits
    var ids: Array = actors.keys()
    ids.sort()
    for id in ids:
        var target: Dictionary = actors[id]
        var execution: bool=target.health<=0 and Executions.can_hit(self,attacker,target)
        if AttackFlow.hurt_protected(rules,target):continue
        if target.id == attacker.id or (target.health <= 0 and not execution) or target.team == attacker.team or id in attacker.hit_targets or target.hidden_by != 0:
            continue
        if abs(int(target.y) - int(attacker.y)) > int(move.get("depth_tolerance", rules.depth_tolerance)):
            continue
        var geometry: Resource = rules.geometry.get(attacker.kind)
        var impact: Vector2 = hurt_box_for(target).get_center()
        if move.has("landing_radius"):
            if attacker.kind=="balok":
                if not Balok.can_contact(attacker):continue
            elif elapsed < int(move.active) - int(move.landing_window) or abs(int(attacker.height)) > 20:
                continue
            if abs(int(target.x) - int(attacker.x)) > int(move.landing_radius) or abs(int(target.height)) > 10:
                continue
        elif geometry != null and geometry.attacks.has(attacker.action):
            var box: Rect2 = hurt_box_for(target)
            var touching: bool = false
            for point in geometry.points_for(attacker.action, elapsed, int(move.active)):
                var contact := Vector2(attacker.x + point[0] * attacker.facing, attacker.y + attacker.height + point[1])
                if attacker.action == "dragon_foot": contact = Vector2(5+point[0], attacker.y+10+point[1])
                if box.has_point(contact):
                    touching = true
                    impact = contact
                    break
            if not touching:
                continue
        else:
            # Placeholder creatures retain their separate prototype reach.
            var distance: int = (int(target.x) - int(attacker.x)) * int(attacker.facing) * int(move.get("direction", 1))
            if distance < -5 or distance > int(move.range):
                continue
        var damage: int = int(move.damage) + int(attacker.damage_bonus) * (2 if attacker.action == "heavy" else 1)
        if attacker.kind=="knight" and attacker.action in ["swing","heavy","lunge","reverse","upward"]:damage <<= int(attacker.moon_damage_shift)
        if attacker.kind == "ratman":
            var phase: int = encounter_settings.get("moon_phase",1)
            if attacker.action == "rat_bite": damage = 6 if phase == 0 else (8 if phase == 4 else 3)
            elif attacker.action == "rat_strike": damage = 3 if phase == 0 else (5 if phase == 4 else 1)
        if attacker.kind == "dragon": damage = Math.dragon_damage(damage, target.dragon_damage_shift)
        var direction: int = int(attacker.facing) * int(move.get("direction", 1))
        var blocked: bool = not bool(move.get("unblockable", false)) and target.guarding and int(target.facing) == -direction
        if blocked:
            damage = int(damage * float(move.get("block_scale", 0.0)))
        attacker.hit_targets.append(id)
        hits.append({"actor": id, "amount": damage, "attacker": attacker.id,
            "move": attacker.action, "blocked": blocked,"execution":execution,
            "x":int(impact.x),"y":int(impact.y)})
    return hits

func snapshot() -> Dictionary:
    return {"schema": 25, "knight_ai_versions":Knight.manifest(rules),"knight_random_state":knight_random_state, "ratman_versions":Ratman.manifest(rules),"ratman_wait_steps":ratman_wait_steps, "balok_versions":{rules.balok.profile_id:rules.balok.content_version}, "entry_state":entry_state.duplicate(true), "encounter_scaling_versions":EncounterScaling.manifest(rules), "attack_timing_versions":AttackFlow.manifest(rules), "content": String(rules.content_id), "behavior_versions":HoldBehaviors.manifest(rules), "mode": String(mode), "encounter": String(encounter), "encounter_settings": encounter_settings.duplicate(true), "rat_perch":rat_perch.duplicate(true), "beast_lane_toggle":beast_lane_toggle,"balok_finish_toggle":balok_finish_toggle,
            "tick": tick, "actors": actors.duplicate(true), "spawn_remaining": spawn_remaining,
            "next_creature_id": next_creature_id, "projectiles": projectiles.duplicate(true),
            "next_projectile_id": next_projectile_id}

func outcome() -> String:
    var alive: Dictionary = {1: false, 2: spawn_remaining > 0}
    for actor in actors.values():
        if actor.health > 0:
            alive[actor.team] = true
    if not alive[1] and not alive[2]:
        return "draw"
    if not alive[1]:
        return "defeat"
    if not alive[2]:
        return "victory"
    return "ongoing"

func hurt_box_for(actor: Dictionary) -> Rect2:
    var box: Rect2 = rules.actor_definitions[actor.kind].hurt_box
    if actor.facing < 0: box.position.x = -box.end.x
    box.position += Vector2(actor.x, actor.y + actor.height)
    return box

func fill_wave_slots() -> void:
    if encounter == &"duel" or spawn_remaining == 0:
        return
    var content: Dictionary = encounter_settings
    var active: int = 0
    var ally_alive: bool = false
    for actor in actors.values():
        if actor.team == 2 and actor.health > 0: active += 1
        if actor.team == 1 and actor.health > 0: ally_alive = true
    if not ally_alive: return
    while active < int(content.concurrent) and spawn_remaining > 0:
        var left: bool = next_creature_id % 2 == 0
        var id: int = next_creature_id
        var depth: int=EntryPlacement.next(rules,entry_state)
        actors[id] = make_actor(id, 0, 2, content.creature, Vector2i(28 if left else 292, depth if depth>=0 else 166), 1 if left else -1)
        if content.creature in ["trogg_spear","trogg_axe","trogg_hammer","giant_troll","ratman","war_beast","balok"]:
            actors[id].x = (-60 if content.creature in ["war_beast","balok"] else -50) if left else 360
            actors[id].entering = content.creature in ["trogg_spear","trogg_axe","trogg_hammer","giant_troll"]
            if content.creature == "ratman" and not left: actors[id].x = 340
            if content.creature == "balok":
                actors[id].x = -60
                actors[id].facing = 1
        if content.creature == "dragon":
            actors[id].x = 80
            actors[id].facing = 1
            actors[id].rest_height = -40
            actors[id].height = -40
        if content.creature == "mudman": Finishers.appear(self,actors[id])
        next_creature_id += 1
        spawn_remaining -= 1
        active += 1
        events.append({"type": "spawn", "actor": id})

func release_dagger(actor: Dictionary) -> void:
    if actor.daggers <= 0 or projectiles.size() >= 32:
        return
    actor.daggers -= 1
    projectiles.append({"id": next_projectile_id, "actor": actor.id, "team": actor.team,
        "x": actor.x + rules.dagger_origin.x * actor.facing, "y": actor.y,
        "height": rules.dagger_origin.y, "facing": actor.facing,
        "ttl": rules.dagger_lifetime})
    next_projectile_id += 1
    events.append({"type": "dagger", "actor": actor.id})

func release_fire(actor: Dictionary, move: Dictionary) -> void:
    if projectiles.size() >= 32: return
    projectiles.append({"id": next_projectile_id, "actor": actor.id, "team": actor.team,
        "x": actor.x + 55, "y": actor.y + 5, "height": 0,
        "facing": 1, "ttl": 144, "age": 0, "kind": "dragon_fire", "move": "dragon_breath",
        "damage": int(move.get("ground_fire_damage",move.damage)), "hit_targets": []})
    next_projectile_id += 1
    events.append({"type": "fire", "actor": actor.id})

func start_special(actor: Dictionary, clip: String, duration: int) -> void:
    actor.attack_flow = {}
    actor.action = "idle"
    actor.remaining = 0
    actor.reaction_remaining = 0
    actor.special_clip = clip
    actor.special_duration = duration
    actor.special_remaining = duration

func start_rat_hold(holder: Dictionary, victim: Dictionary, kind: String, duration: int) -> void:
    if holder.held_target != 0 or victim.grab_remaining > 0: return
    victim.motion={}
    holder.action = "idle"
    holder.remaining = 0
    if kind == "squeeze":
        # SlamStart leaves the Ratman's elevated coordinates intact; moving
        # its composite down to the victim would move the treetop as well.
        holder.rest_height = int(rat_perch.get("height",-98))
        holder.x = int(rat_perch.get("x",victim.x))
        holder.y = int(rat_perch.get("y",victim.y-3))+3
    else:
        holder.rest_height = 0
        holder.x = victim.x
        holder.y = victim.y
    holder.height = holder.rest_height
    holder.held_target = victim.id
    holder.hold_kind = kind
    holder.hold_elapsed = 0
    holder.rat_phase_elapsed=0
    holder.special_clip = "rat_hold" if kind == "ride" else "rat_squeeze"
    victim.grabbed_by = holder.id
    victim.grab_remaining = duration
    victim.hidden_by = holder.id
    victim.remaining = 0
    victim.action = "idle"
    victim.guarding = false
    events.append({"type": "hold", "actor": victim.id, "attacker": holder.id, "kind": kind})

func advance_rat_hold(holder: Dictionary, victim: Dictionary, escaped: bool) -> void:
    if RatHold.advance(self,holder,victim,escaped):return
    if HoldBehaviors.advance(self,holder,victim,escaped):return
    # Unsupported/malformed content cannot leave a living victim trapped.
    RatHold.unlink(holder,victim)
    release_rat_perch(holder)
    holder.special_clip=""

func release_rat_perch(actor: Dictionary) -> void:
    if not rat_perch.is_empty() and rat_perch.owner == actor.id: rat_perch.owner = 0
    actor.rat_tree = false

func settle_rat_victim(holder: Dictionary, victim: Dictionary, clip: String) -> void:
    victim.hidden_by=0;victim.grabbed_by=0;victim.grab_remaining=0
    victim.x=holder.x;victim.y=holder.y;victim.facing=holder.facing
    victim.visual_kind="ratman";victim.defeat_clip="remains_throw" if clip=="rat_throw_finish" else "remains_squeeze"
    victim.down_duration=6;victim.down_remaining=0
    if clip=="rat_squeeze_finish":holder.terminal_clip="rat_squeeze_after"

func begin_beast_pass(actor: Dictionary) -> void:
    # LAB_0228/022B: turn beyond the edge, choose a new lane once, then cross.
    # The initial spawn uses an arena entry lane; target-based re-aiming begins
    # on return passes. EntryPlacement supplies the opening depth independently.
    if actor.beast_pass == 0:
        actor.beast_pass = 1
    elif actor.x < 0 or actor.x >= 340:
        actor.x = -50 if actor.x < 0 else 380
        actor.facing = 1 if actor.x < 0 else -1
        var target: Dictionary = nearest_opponent(actor)
        actor.beast_pass += 1
        # The source toggle is shared by all beasts, not one counter per beast.
        beast_lane_toggle ^= 1
        var wobble: int = ((actor.beast_pass*3+actor.id)%8)*4 if beast_lane_toggle == 0 else 0
        actor.y = int(target.get("y",166)) + wobble
    actor.leap_from_x = actor.x
    actor.beast_phase = 0

func nearest_opponent(actor: Dictionary) -> Dictionary:
    var result: Dictionary = {}
    var distance: int = 100000
    var ids: Array = actors.keys(); ids.sort()
    for id in ids:
        var other: Dictionary = actors[id]
        if other.team == actor.team or other.health <= 0: continue
        var d: int = abs(other.x-actor.x)+abs(other.y-actor.y)
        if d < distance: result=other;distance=d
    return result

func advance_beast(actor: Dictionary, elapsed: int) -> void:
    # Native interpolation preserves the source33/27/17/33 displacement cycle
    # without teleporting a whole creature step between collision checks.
    var steps: Array = [27,17,33,33] # source increments phase before reading
    var phase: int = (elapsed/6)%4
    var complete: int = (elapsed/24)*110
    for n in range(phase): complete += steps[n]
    complete += int(steps[phase]*(elapsed%6+1)/6)
    actor.beast_phase = (phase+1)%4
    actor.x = actor.leap_from_x + actor.facing*complete
    if (actor.facing > 0 and actor.x >= 392) or (actor.facing < 0 and actor.x <= -72):
        actor.remaining = 1
        actor.cooldown_remaining = ((tick + actor.id * 7) & 15) | 5

func beast_finish(beast: Dictionary, victim: Dictionary) -> void:
    Beast.finish(beast, victim,self)

func dragon_finish(dragon: Dictionary, victim: Dictionary, move: String) -> void:
    if move == "dragon_bite":
        if dragon.health<=0: return # simultaneous kill has no living composite owner
        victim.hidden_by = dragon.id
        victim.down_remaining = 312
        victim.down_duration = 312
        start_special(dragon, "execution_bite", 312)
    elif move in ["dragon_claw", "dragon_breath"]:
        victim.visual_kind = "dragon_victim"
        victim.defeat_clip = "burn"
        victim.down_duration = rules.death_frames.duration("complete_burn","burn")
        victim.down_remaining = victim.down_duration
        victim.down_stop = 0 if mode==&"cooperative" else rules.death_frames.solo_limit("complete_burn","burn")

func advance_projectiles() -> Array[Dictionary]:
    var hits: Array[Dictionary] = []
    var remaining_projectiles: Array[Dictionary] = []
    var ids: Array = actors.keys()
    ids.sort()
    for projectile in projectiles:
        if projectile.get("kind", "dagger") == "dragon_fire":
            projectile.age += 1
            projectile.ttl -= 1
            var owner: Dictionary = actors.get(projectile.actor, {})
            if owner.is_empty() or owner.health <= 0: continue
            var geometry: Resource = rules.geometry.dragon
            for id in ids:
                var target: Dictionary = actors[id]
                if target.health <= 0 or target.team == projectile.team or id in projectile.hit_targets or target.hidden_by != 0 or AttackFlow.hurt_protected(rules,target): continue
                if abs(target.y-projectile.y) > 5: continue
                var box: Rect2 = hurt_box_for(target)
                for contact in geometry.points_for("ground_fire", projectile.age, 144):
                    if box.has_point(Vector2(projectile.x+contact[0], projectile.y+contact[1])):
                        projectile.hit_targets.append(id)
                        hits.append({"actor": id, "attacker": projectile.actor, "amount": Math.dragon_damage(projectile.damage, target.dragon_damage_shift), "move": "ground_fire", "blocked": false,
                            "x":projectile.x+contact[0],"y":projectile.y+contact[1]})
                        break
            if projectile.ttl > 0: remaining_projectiles.append(projectile)
            continue
        var before: int = projectile.x
        projectile.x += int(projectile.get("speed", rules.dagger_speed)) * int(projectile.facing)
        projectile.ttl -= 1
        var nearest: Dictionary = {}
        var nearest_entry: int = 100000
        for id in ids:
            var target: Dictionary = actors[id]
            if target.health <= 0 or target.team == projectile.team or target.hidden_by != 0 or AttackFlow.hurt_protected(rules,target):
                continue
            if abs(int(target.y) - int(projectile.y)) > int(rules.depth_tolerance):
                continue
            var box: Rect2 = hurt_box_for(target)
            var y: int = projectile.y + projectile.height
            if y < box.position.y or y >= box.end.y:
                continue
            var low: int = mini(before, projectile.x)
            var high: int = maxi(before, projectile.x)
            if high < box.position.x or low >= box.end.x:
                continue
            var edge: int = int(box.position.x) if projectile.facing > 0 else int(box.end.x) - 1
            var entry: int = maxi(0, (edge - before) * int(projectile.facing))
            if entry < nearest_entry:
                nearest = target
                nearest_entry = entry
        if not nearest.is_empty():
            var blocked: bool = not rules.moves.dagger.get("unblockable",false) and nearest.guarding and nearest.facing == -projectile.facing
            var amount: int = int(projectile.get("damage", rules.moves.dagger.damage))
            hits.append({"actor": nearest.id, "amount": 0 if blocked else amount,
                "attacker": projectile.actor, "move": projectile.get("move", "dagger"), "blocked": blocked,
                "x":before+nearest_entry*projectile.facing,"y":projectile.y+projectile.height})
        elif projectile.ttl > 0 and projectile.x > -32 and projectile.x < 352:
            remaining_projectiles.append(projectile)
    projectiles = remaining_projectiles
    return hits
