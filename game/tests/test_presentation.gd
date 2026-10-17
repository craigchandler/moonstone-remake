extends SceneTree

func _initialize() -> void:
    run_checks.call_deferred()

func run_checks() -> void:
    var scene: PackedScene = load("res://scenes/arena.tscn")
    var arena: Node = scene.instantiate()
    root.add_child(arena)
    arena.set_physics_process(false)
    await process_frame # Allow scene/input registration to finish before dispatch.
    var initial: bool = arena.gore_enabled
    var before: Dictionary = arena.session.simulation.snapshot()
    var event := InputEventKey.new()
    event.keycode = KEY_G
    event.physical_keycode = KEY_G
    event.pressed = true
    Input.parse_input_event(event)
    Input.flush_buffered_events()
    await process_frame
    if arena.gore_enabled == initial or arena.session.simulation.snapshot() != before:
        print("Gore before/after: ", initial, "/", arena.gore_enabled, "; tick before/after: ", before.tick, "/", arena.session.simulation.tick)
        push_error("G must toggle gore without changing combat state")
        quit(1)
        return
    var saved := ConfigFile.new()
    if saved.load("user://preferences.cfg") != OK or bool(saved.get_value("visual", "gore")) != arena.gore_enabled:
        push_error("Gore choice must persist")
        quit(1)
        return
    event.pressed = false
    Input.parse_input_event(event)
    Input.flush_buffered_events()
    await process_frame
    event.pressed = true
    Input.parse_input_event(event)
    Input.flush_buffered_events()
    await process_frame
    if arena.gore_enabled != initial:
        push_error("Second G press should restore the original choice")
        quit(1)
        return
    arena.debug_mode=true # Explicit shortcut fixture; normal gore persistence was checked above.
    for key in [KEY_F1, KEY_F2, KEY_F4, KEY_F5, KEY_F6, KEY_TAB]:
        event.keycode = key
        event.physical_keycode = key
        event.pressed = true
        Input.parse_input_event(event)
        Input.flush_buffered_events()
        await process_frame
        var expected: StringName = &"duel" if key == KEY_F1 else (&"spear_lair" if key == KEY_F2 else (&"axe_lair" if key == KEY_F4 else (&"troll_lair" if key == KEY_F5 else &"balok_lair")))
        if arena.encounter != expected or (key == KEY_TAB and arena.mode != &"cooperative"):
            push_error("Encounter and cooperative keys must reach the correct session")
            quit(1)
            return
        event.pressed = false
        Input.parse_input_event(event)
        Input.flush_buffered_events()
        await process_frame
    arena.queue_free()
    await process_frame
    print("PASS: G key dispatch/persistence, encounter switching and cooperative key dispatch")
    quit()
