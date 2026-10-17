extends RefCounted

# Explicit verification/capture entry. Normal play does not load this module.
var host: Node

func _init(view: Node) -> void:
    host = view

func start() -> void:
    if host.settings.load("user://preferences.cfg") == OK:
        host.gore_enabled = bool(host.settings.get_value("visual", "gore", true))
    for argument in ([] if host.managed_by_world else host.Runtime.user_arguments(host.debug_mode)):
        if argument == "--accuracy-demo": host.accuracy_demo=true
        if argument.begins_with("--finish-demo="):
            host.finish_demo=argument.trim_prefix("--finish-demo=")
            host.accuracy_demo=true
        if argument.begins_with("--creature-showcase="):
            var choice: String=argument.trim_prefix("--creature-showcase=")
            if host.rule_set.encounters.has(choice):
                host.encounter=StringName(choice)
                host.pack_showcase=true
        if argument.begins_with("--encounter="):
            var choice: String=argument.trim_prefix("--encounter=")
            if host.rule_set.encounters.has(choice): host.encounter=StringName(choice)
        if argument.begins_with("--capture="):
            host.capture_path = argument.trim_prefix("--capture=")
        if argument.begins_with("--capture-stride="):host.capture_stride=clampi(int(argument.trim_prefix("--capture-stride=")),1,50)
        if argument == "--smoke":
            host.smoke = true
        if argument == "--cooperative":
            host.mode = &"cooperative"
        if argument == "--demo":
            host.demo = true
        if argument == "--combat-demo":
            host.demo = true
            host.combat_demo = true
        if argument == "--trogg-demo":
            host.demo = true
            host.trogg_demo = true
        if argument == "--balok-demo":
            host.demo = true
            host.balok_demo = true
        if argument == "--balok":
            host.encounter = &"balok_lair"
        if argument == "--troll-demo":
            host.demo = true
            host.troll_demo = true
        if argument == "--troll":
            host.encounter = &"troll_lair"
        if argument == "--axe-demo":
            host.demo = true
            host.axe_demo = true
        if argument == "--axe":
            host.encounter = &"axe_lair"
        if argument == "--defence-demo":
            host.demo = true
            host.defence_demo = true
        if argument == "--duel":
            host.encounter = &"duel"
        if argument == "--mirror-demo":
            host.mirror_demo = true
        if argument == "--no-gore":
            host.gore_enabled = false
        if argument.begins_with("--capture-sequence="):
            host.sequence_path = argument.trim_prefix("--capture-sequence=")
            host.demo = true
    if host.pack_showcase: host.demo=false
    if host.accuracy_demo:
        host.pack_showcase=false
        host.demo=false
        host.accuracy_fixture=preload("res://debug/fixtures/combat_accuracy_fixture.gd").new()
        if not host.finish_demo.is_empty():
            host.accuracy_fixture=preload("res://debug/fixtures/finisher_fixture.gd").new()
            if host.finish_demo.begins_with("beast_"):
                host.accuracy_fixture=preload("res://debug/fixtures/beast_review_fixture.gd").new()
            if host.finish_demo.begins_with("audit_"):
                host.accuracy_fixture=preload("res://debug/fixtures/death_review_fixture.gd").new()
            if host.finish_demo.begins_with("recover_"):
                host.accuracy_fixture=preload("res://debug/fixtures/hit_recovery_fixture.gd").new()
            if host.finish_demo.begins_with("knock_"):
                host.accuracy_fixture=preload("res://debug/fixtures/knockback_fixture.gd").new()
            if host.finish_demo.begins_with("guard_"):
                host.accuracy_fixture=preload("res://debug/fixtures/guardian_fixture.gd").new()
            if host.finish_demo=="rat_tree":host.accuracy_fixture=preload("res://debug/fixtures/ratman_tree_fixture.gd").new()
            if host.finish_demo.begins_with("correct_"):host.accuracy_fixture=preload("res://debug/fixtures/execution_escape_fixture.gd").new()
            if host.finish_demo.begins_with("scaling_"):host.accuracy_fixture=preload("res://debug/fixtures/enemy_scaling_fixture.gd").new()
            if host.finish_demo.begins_with("pacing_"):
                host.accuracy_fixture=preload("res://debug/fixtures/combat_pacing_fixture.gd").new()
                var parts: PackedStringArray=host.finish_demo.split("-")
                if parts.size()>2:host.knight_kind=maxi(0,["blue","yellow","green","red"].find(parts[2]))
            host.accuracy_fixture.choice=host.finish_demo
            host.accuracy_fixture.mirror=host.mirror_demo
    if host.combat_demo:
        host.mode = &"competitive"
    if host.demo and not host.trogg_demo and not host.defence_demo and not host.axe_demo and not host.troll_demo and not host.balok_demo:
        host.encounter = &"duel"
    if host.trogg_demo or host.defence_demo:
        host.mode = &"competitive"
        host.encounter = &"spear_lair"
    if host.axe_demo:
        host.mode = &"competitive"
        host.encounter = &"axe_lair"
    if host.troll_demo:
        host.mode = &"competitive"
        host.encounter = &"troll_lair"
    if host.balok_demo:
        host.mode = &"competitive"
        host.encounter = &"balok_lair"
    Engine.physics_ticks_per_second = host.rule_set.tick_rate
    if not host.sequence_path.is_empty() or not host.capture_path.is_empty():
        RenderingServer.viewport_set_update_mode(host.get_viewport().get_viewport_rid(), RenderingServer.VIEWPORT_UPDATE_ALWAYS)
    if host.session == null:
        host.session = host.Session.new(host.rule_set)
        host.restart()
    elif not host.managed_by_world or host.demo:
        host.restart()
    else:
        host.animator.reset()
        host.animator.update(host.session.simulation.actors, host.rule_set, host.art)

func configure_fight() -> void:
    if host.demo and not host.trogg_demo and not host.defence_demo and not host.axe_demo and not host.troll_demo and not host.balok_demo:
        host.session.simulation.actors[1].x = 100
        host.session.simulation.actors[2].x = 235
    if host.combat_demo:
        var facing: int = -1 if host.mirror_demo else 1
        host.session.simulation.actors[1].x = 160
        host.session.simulation.actors[1].facing = facing
        host.session.simulation.actors[2].x = 160 - facing * 35
        host.session.simulation.actors[2].facing = facing
        host.session.simulation.actors[2].health = 13 # explicit low-health visual fixture
    if host.trogg_demo:
        # Two-enemy capture fixture: explicit positions/health, normal combat rules.
        host.session.simulation.spawn_remaining = 0
        host.session.simulation.actors[1].x = 160
        host.session.simulation.actors[10].x = 45
        host.session.simulation.actors[10].health = 4 if host.axe_demo else 7
        host.session.simulation.actors[11].x = 275
        host.session.simulation.actors[11].y = 156
        host.session.simulation.actors[11].cooldown_remaining = 0
        host.session.simulation.actors[11].health = 8 if host.axe_demo else 4 # explicit dagger/swing or lunge fixture
        if host.mirror_demo:
            for actor in host.session.simulation.actors.values():
                actor.x = 320 - actor.x
                actor.facing = -actor.facing
    if host.axe_demo:
        # Explicit two-enemy visual fixture, separate from the normal four-enemy AI lair.
        host.session.simulation.spawn_remaining = 0
        host.session.simulation.actors[1].x = 160
        host.session.simulation.actors[1].facing = -1
        host.session.simulation.actors[10].x = 70
        host.session.simulation.actors[10].health = 4 if host.axe_demo else 7
        host.session.simulation.actors[10].cooldown_remaining = 0
        host.session.simulation.actors[11].x = 275
        host.session.simulation.actors[11].y = 166
        host.session.simulation.actors[11].cooldown_remaining = 0
        host.session.simulation.actors[11].health = 8 if host.axe_demo else 4 # explicit dagger/swing or lunge fixture
        if host.mirror_demo:
            for actor in host.session.simulation.actors.values():
                actor.x = 320 - actor.x
                actor.facing = -actor.facing
    if host.troll_demo:
        # Explicit 17HP Troll showcase; original sword damage, scripted positions/inputs.
        host.session.simulation.actors[10].health = 17
        host.session.simulation.actors[1].x = 240
        host.session.simulation.actors[1].facing = -1
        host.session.simulation.actors[10].x = 100
        if host.mirror_demo:
            for actor in host.session.simulation.actors.values():
                actor.x = 320 - actor.x
                actor.facing = -actor.facing
    if host.balok_demo:
        # Explicit 18HP Balok showcase; original sword damage, scripted positions/inputs.
        host.session.simulation.actors[10].health = 18
        host.session.simulation.actors[1].x = 230
        host.session.simulation.actors[1].facing = -1
        host.session.simulation.actors[10].x = 80
        if host.mirror_demo:
            for actor in host.session.simulation.actors.values():
                actor.x = 320 - actor.x
                actor.facing = -actor.facing
    host.animator.update(host.session.simulation.actors, host.rule_set, host.art)
    if host.pack_showcase:
        host.session.simulation.spawn_remaining=0
        for id in host.session.simulation.actors.keys():
            if id not in [1,10]:host.session.simulation.actors.erase(id)
        host.session.simulation.actors[1].health=500
        host.session.simulation.actors[1].maximum=500
        host.session.simulation.actors[1].x=265
        host.session.simulation.actors[1].y=139
        host.session.simulation.actors[10].x=75 if host.session.simulation.actors[10].kind=="dragon" else 90

func advance_demo() -> void:
    # Reproducible visual exercise; no gameplay rules or attack clocks are changed.
    if host.combat_demo:
        host.advance_combat_demo()
        return
    if host.balok_demo:
        host.advance_balok_demo()
        return
    if host.troll_demo:
        host.advance_troll_demo()
        return
    if host.axe_demo:
        host.advance_axe_demo()
        return
    if host.trogg_demo:
        host.advance_trogg_demo()
        return
    if host.defence_demo:
        host.advance_defence_demo()
        return
    var current: int = host.demo_ticks % 300
    var direction := Vector2i.ZERO
    var action := "idle"
    if current < 15: direction.x = 1
    elif current < 30: direction.x = -1
    elif current < 40: direction.y = -1
    elif current < 50: direction.y = 1
    elif current == 50: direction.x = 1
    elif current == 60: action = "swing"
    elif current == 115: action = "heavy"
    elif current == 195: action = "lunge"
    elif current >= 260: action = "block"
    host.session.command(1, 1, direction, action)
    host.session.command(2, 0, Vector2i.ZERO, "block")
    host.session.simulation.advance()
    host.demo_ticks += 1

func advance_combat_demo() -> void:
    var current: int = host.demo_ticks % 320
    var direction := Vector2i.ZERO
    var action := "idle"
    var facing: int = -1 if host.mirror_demo else 1
    if current in [20, 80]: action = "reverse"
    elif current >= 135 and current < 155: direction.x = facing
    elif current == 156: direction.x = -facing
    elif current == 170: action = "heavy"
    host.session.command(1, 1, direction, action)
    host.session.command(2, 0, Vector2i.ZERO, "block" if current >= 80 and current < 125 else "idle")
    host.session.simulation.advance()
    host.demo_ticks += 1

func advance_defence_demo() -> void:
    # Live two-Trogg AI, normal health; scripted anticipated sidesteps.
    var live_thrust: bool = false
    for actor in host.session.simulation.actors.values():
        if actor.action != "spear_thrust" or actor.remaining <= 0: continue
        live_thrust = true
        if actor.get("attack_flow",{}).get("started",-1) == host.session.simulation.tick-1:
            var side: int = signi(int(host.session.simulation.actors[1].y)-int(actor.y))
            if side == 0: side=1 if actor.y<=158 else -1
            host.dodge_destination = clampi(actor.y+12*side,139,177)
    if not live_thrust: host.dodge_destination=158
    var dy: int = signi(host.dodge_destination - int(host.session.simulation.actors[1].y))
    if abs(host.dodge_destination - int(host.session.simulation.actors[1].y)) < 2: dy = 0
    host.session.advance(Vector2i(0, dy), "idle")
    host.demo_ticks += 1

func advance_trogg_demo() -> void:
    var direction := Vector2i.ZERO
    var action: String = "idle"
    if host.demo_ticks >= 5 and host.demo_ticks < 35: action = "block"
    elif host.demo_ticks == 40: action = "dagger"
    elif host.demo_ticks >= 80 and host.demo_ticks < 110: direction.x = 1
    elif host.demo_ticks == 115: action = "upward"
    elif host.demo_ticks >= 165 and host.demo_ticks < 209: direction.x = -1
    elif host.demo_ticks == 210: action = "lunge"
    if host.mirror_demo: direction.x = -direction.x
    host.session.command(1, 1, direction, action)
    host.session.command(10, 0, Vector2i.ZERO, "idle")
    host.session.command(11, 0, Vector2i.ZERO, "spear_thrust" if host.demo_ticks == 5 else "idle")
    host.session.simulation.advance()
    host.demo_ticks += 1

func advance_axe_demo() -> void:
    var direction := Vector2i.ZERO
    var action: String = "idle"
    if host.demo_ticks >= 5 and host.demo_ticks < 50: action = "block"
    elif host.demo_ticks >= 65 and host.demo_ticks < 75: direction.y = -1
    elif host.demo_ticks >= 120 and host.demo_ticks < 130: direction.y = 1
    elif host.demo_ticks == 140: direction.x = 1
    elif host.demo_ticks == 150: action = "dagger"
    elif host.demo_ticks >= 175 and host.demo_ticks < 205: direction.x = 1
    elif host.demo_ticks == 210: action = "swing"
    elif host.demo_ticks >= 270 and host.demo_ticks < 320: direction.x = -1
    elif host.demo_ticks == 325: action = "lunge"
    if host.mirror_demo: direction.x = -direction.x
    host.session.command(1, 1, direction, action)
    host.session.command(10, 0, Vector2i.ZERO, "axe_swing" if host.demo_ticks == 5 else "idle")
    host.session.command(11, 0, Vector2i.ZERO, "axe_chop" if host.demo_ticks == 65 else "idle")
    host.session.simulation.advance()
    host.demo_ticks += 1

func advance_troll_demo() -> void:
    var direction := Vector2i.ZERO
    var action: String = "idle"
    if host.demo_ticks >= 55 and host.demo_ticks < 65: direction.y = -1
    elif host.demo_ticks >= 105 and host.demo_ticks < 115: direction.y = 1
    elif host.demo_ticks >= 120 and host.demo_ticks < 130: direction.x = -1
    elif host.demo_ticks >= 205 and host.demo_ticks < 215: direction.y = -1
    elif host.demo_ticks >= 250 and host.demo_ticks < 260: direction.y = 1
    elif host.demo_ticks == 275: action = "dagger"
    elif host.demo_ticks == 345: action = "heavy"
    elif host.demo_ticks == 415: action = "lunge"
    if host.mirror_demo: direction.x = -direction.x
    host.session.command(1, 1, direction, action)
    var enemy_direction := Vector2i((-1 if host.mirror_demo else 1) if host.demo_ticks < 20 else 0, 0)
    host.session.command(10, 0, enemy_direction, "troll_smash" if host.demo_ticks == 55 else ("troll_sweep" if host.demo_ticks == 205 else "idle"))
    host.session.simulation.advance()
    host.demo_ticks += 1

func advance_balok_demo() -> void:
    var pause: int=host.rule_set.actor_definitions.balok.attack_cooldown_ticks
    var swipe: Dictionary=host.rule_set.moves.balok_swipe
    var maul: Dictionary=host.rule_set.moves.balok_maul
    var maul_at: int=255+int(swipe.windup+swipe.active+swipe.recovery)+pause+1
    var hop_at: int=maul_at+int(maul.windup+maul.active+maul.recovery)+pause+4
    var direction := Vector2i.ZERO
    var action: String = "idle"
    if host.demo_ticks >= 55 and host.demo_ticks < 65: direction.y = -1
    elif host.demo_ticks >= 185 and host.demo_ticks < 220: direction.x = -1
    elif host.demo_ticks >= 225 and host.demo_ticks < 235: direction.y = 1
    elif host.demo_ticks == 240: direction.x = 1
    elif host.demo_ticks >= 255 and host.demo_ticks < 265: direction.y = -1
    elif host.demo_ticks >= 310 and host.demo_ticks < 320: direction.y = 1
    elif host.demo_ticks >= maul_at and host.demo_ticks < maul_at+10: direction.y = -1
    elif host.demo_ticks >= 400 and host.demo_ticks < 410: direction.y = 1
    elif host.demo_ticks >= hop_at and host.demo_ticks < hop_at+10: direction.y = -1
    elif host.demo_ticks >= 505 and host.demo_ticks < 540: direction.x = -1
    elif host.demo_ticks == 545: direction.x = 1
    elif host.demo_ticks >= 550 and host.demo_ticks < 560: direction.y = 1
    elif host.demo_ticks == 575: action = "dagger"
    elif host.demo_ticks == 625: action = "heavy"
    elif host.demo_ticks == 695: action = "swing"
    if host.mirror_demo: direction.x = -direction.x
    host.session.command(1, 1, direction, action)
    var enemy_action: String = "idle"
    if host.demo_ticks == 55: enemy_action = "balok_pounce"
    elif host.demo_ticks == 255: enemy_action = "balok_swipe"
    elif host.demo_ticks == maul_at: enemy_action = "balok_maul"
    elif host.demo_ticks == hop_at: enemy_action = "balok_hop"
    var facing: int = (1 if host.demo_ticks < 180 else -1) * (-1 if host.mirror_demo else 1)
    host.session.command(10, 0, Vector2i.ZERO, enemy_action, facing)
    host.session.simulation.advance()
    host.demo_ticks += 1

func demo_length() -> int:
    if not host.finish_demo.is_empty(): return host.accuracy_fixture.length()
    if host.accuracy_demo: return 720
    if host.pack_showcase:
        var total: int=400
        for move in host.rule_set.actor_definitions[host.session.simulation.actors[10].kind].allowed_moves:
            var content: Dictionary=host.rule_set.moves[move]
            total+=int(content.windup)+int(content.active)+int(content.recovery)+20
        return total
    if host.balok_demo: return 900
    return 600 if host.troll_demo else (560 if host.axe_demo else (400 if host.defence_demo else (420 if host.trogg_demo else (320 if host.combat_demo else 300))))

func capture_sequence_frame() -> void:
    # Capture the game's viewport even if the desktop hides/minimises its window.
    # This deferred call follows the queued CanvasItem redraw; regular play is unaffected.
    RenderingServer.force_draw(false)
    var path: String = host.sequence_path.path_join("%03d.png" % (host.demo_ticks - 1))
    var result: int = OK
    if (host.demo_ticks-1)%host.capture_stride==0 or host.demo_ticks>=host.demo_length():
        result = host.get_viewport().get_texture().get_image().save_png(path)
    if result != OK:
        host.get_tree().quit(result)
    elif host.demo_ticks >= host.demo_length():
        if host.accuracy_demo:
            host.finish_accuracy_demo()
            return
        if host.pack_showcase and host.session.simulation.outcome()!="victory":
            push_error("Creature presentation fixture did not finish with its scripted counter")
            host.get_tree().quit(1)
            return
        if (host.combat_demo or host.trogg_demo or host.axe_demo or host.troll_demo or host.balok_demo) and host.session.simulation.outcome() != "victory":
            push_error("Combat visual fixture did not reach defeat")
            host.get_tree().quit(1)
            return
        if (host.defence_demo or host.axe_demo or host.troll_demo or host.balok_demo) and host.session.simulation.actors[1].health != 20:
            push_error("Live evasion fixture took damage")
            host.get_tree().quit(1)
            return
        if host.pack_showcase: print("PASS: rendered creature poses/attacks and ordinary lunge defeating an explicit one-HP fixture; ",host.encounter)
        elif host.balok_demo: print("PASS: captured Balok pounce/hop/swipe/maul evasion, counters and defeat")
        elif host.troll_demo: print("PASS: captured troll walk, smash/sweep sidesteps, dagger, heavy/lunge and collapse")
        else: print("PASS: captured axe swing/parry, chop/sidestep, dagger and axe Trogg deaths" if host.axe_demo else ("PASS: captured live dual-Trogg evasion" if host.defence_demo else ("PASS: captured spear guard, dagger, upward thrust and Trogg deaths" if host.trogg_demo else ("PASS: captured combat reactions/defeat" if host.combat_demo else "PASS: captured walking and sword poses"))))
        print("Visual fixture state hash: ", hash(JSON.stringify(host.session.simulation.snapshot())))
        if host.defence_demo: print("PASS: live dual-Trogg evasion retained 20/20 health")
        host.get_tree().quit()
    else:
        host.set_physics_process(true)

func finish_accuracy_demo() -> void:
    var verified: bool=host.accuracy_fixture.verify() if host.finish_demo.is_empty() else host.accuracy_fixture.verify(host.session)
    if not verified:
        print("FAILED_ACCURACY_STATE=",JSON.stringify(host.session.simulation.snapshot()))
        host.get_tree().quit(1)
        return
    print("PASS: corrected combat/execution fixture; encounter=",host.encounter,"; checks=",host.accuracy_fixture.checked)
    print("ACCURACY_STATE=",JSON.stringify(host.session.simulation.snapshot()))
    if host.finish_demo.begins_with("pacing_"):print("PACING_STATE=",JSON.stringify(host.accuracy_fixture.report()))
    if host.finish_demo.begins_with("scaling_"):print("SCALING_FIGHT_STATE=",JSON.stringify(host.accuracy_fixture.report()))
    host.get_tree().quit()

func advance_pack_showcase() -> void:
    # Presentation fixture only: explicit positions, a durable observer and a
    # one-HP enemy for the final real sword counter. Not an AI playthrough.
    var model: RefCounted=host.session.simulation
    var foe: Dictionary=model.actors[10]
    var facing: int=-1 if host.mirror_demo else 1
    var moves: PackedStringArray=host.rule_set.actor_definitions[foe.kind].allowed_moves
    if host.demo_ticks<40:
        host.session.command(10,0,Vector2i(facing if host.demo_ticks<20 else -facing,0),"idle",facing)
    var cursor: int=40
    for move_name in moves:
        var move: Dictionary=host.rule_set.moves[move_name]
        var duration: int=int(move.windup)+int(move.active)+int(move.recovery)+20
        if host.demo_ticks==cursor:
            foe.cooldown_remaining=0
            foe.facing=facing
            foe.x=230 if host.mirror_demo else (75 if foe.kind=="dragon" else 90)
            foe.y=166
            host.session.command(10,0,Vector2i.ZERO,move_name,facing)
        cursor+=duration
    if host.demo_ticks==cursor:
        foe.x=115 if host.mirror_demo else 205
        foe.y=166
        foe.health=1
        foe.height=0
        foe.action="idle"
        foe.remaining=0
        model.actors[1].x=190 if host.mirror_demo else 130
        model.actors[1].y=166
        model.actors[1].grab_remaining=0
        model.actors[1].grabbed_by=0
        model.actors[1].stagger_remaining=0
        host.session.command(1,1,Vector2i.ZERO,"lunge",-1 if host.mirror_demo else 1)
    model.advance()
    host.demo_ticks+=1

func capture_and_quit() -> void:
    RenderingServer.force_draw(false)
    var result: int = host.get_viewport().get_texture().get_image().save_png(host.capture_path)
    print("CAPTURE result=", result)
    host.get_tree().quit(result)
