extends SceneTree

var failures: int = 0

func check(condition: bool, message: String) -> void:
    if not condition:
        failures += 1
        push_error(message)

func press(key: Key) -> void:
    var event := InputEventKey.new()
    event.keycode = key
    event.physical_keycode = key
    event.pressed = true
    Input.parse_input_event(event)
    Input.flush_buffered_events()
    var release: InputEventKey = event.duplicate()
    release.pressed = false
    Input.parse_input_event(release)
    Input.flush_buffered_events()

func _initialize() -> void:
    run_checks.call_deferred()

func run_checks() -> void:
    var view: Node = load("res://scenes/main.tscn").instantiate()
    view.definition = load("res://scripts/content/world_definition.gd").new()
    view.debug_mode=true
    view.saving_enabled = false
    root.add_child(view)
    view.set_physics_process(false)
    await process_frame
    check(view.arena == null, "The default screen is the world map")
    press(KEY_TAB)
    check(view.journey.mode == &"cooperative", "Map Tab selects co-op")
    for step in range(80):
        view.travel(Vector2i.RIGHT)
        if view.arena != null: break
    check(view.arena != null and view.arena.managed_by_world, "Map movement creates a managed arena")
    view.arena.set_physics_process(false)
    check(view.arena.session == view.journey.combat and view.arena.mode == &"cooperative", "View and journey share the actual encounter session")
    var position: Vector2i = view.journey.world.position
    press(KEY_ENTER)
    check(view.arena != null, "Enter cannot claim an unfinished battle")
    press(KEY_F1)
    press(KEY_F4)
    press(KEY_F5)
    press(KEY_F6)
    press(KEY_TAB)
    check(view.arena.encounter == &"spear_lair" and view.arena.mode == &"cooperative", "Training/mode shortcuts cannot replace a journey encounter")
    press(KEY_ESCAPE)
    check(view.arena == null and view.journey.world.cleared.is_empty(), "Esc retreats to map without clearing")
    check(view.journey.world.position == position, "Return preserves the knight's map position")
    press(KEY_R)
    view.set_physics_process(false)
    for step in range(80):
        view.travel(Vector2i.RIGHT)
        if view.arena != null: break
    view.arena.set_physics_process(false)
    # Explicit outcome fixture verifies Enter routing; combat damage has separate suites.
    view.arena.session.simulation.spawn_remaining = 0
    for actor in view.arena.session.simulation.actors.values():
        if actor.team == 2: actor.health = 0
    press(KEY_ENTER)
    check(view.loot_view != null and view.arena != null and not view.arena.visible, "Victory opens loot before returning to map")
    check(not view.arena.is_physics_processing(), "Loot freezes the battle")
    press(KEY_ENTER)
    check(view.arena == null and view.loot_view == null and view.journey.world.cleared.size() == 1, "Loot confirmation returns a real victory to the map")
    var entry_health: int = view.journey.character.health
    view.journey.world.position = Vector2i(100, 71) # Route directly to a different entrance.
    for step in range(30):
        view.travel(Vector2i.RIGHT)
        if view.arena != null: break
    view.arena.set_physics_process(false)
    view.arena.session.simulation.actors[1].health = 1
    press(KEY_R)
    check(view.arena.session.simulation.actors[1].health == entry_health and view.journey.world.cleared.size() == 1 and view.journey.world.active_lair == "grassland_east", "Battle R restores the journey entry kit and keeps earlier cleared lairs")
    press(KEY_ESCAPE)
    for key in [KEY_F1, KEY_F5, KEY_F6]:
        press(key)
        check(view.arena != null and not view.arena.managed_by_world and view.arena.encounter == (&"duel" if key == KEY_F1 else (&"troll_lair" if key == KEY_F5 else &"balok_lair")), "Map shortcuts open the correct standalone practice")
        view.arena.set_physics_process(false)
        if key == KEY_F5: check(view.arena.session.simulation.actors[10].health == 40, "F5 practice starts a full-health troll")
        press(KEY_F3)
        check(view.arena == null and view.journey.world.cleared.size() == 1, "F3 leaves practice without losing journey progress")
    press(KEY_R)
    check(view.journey.world.cleared.is_empty(), "Map R starts a new journey")
    view.queue_free()
    await process_frame
    if failures == 0:
        print("PASS: default map, co-op selection, map-to-combat, shared session, guarded shortcuts, frozen victory loot, Enter result, Esc retreat, practice return and journey reset")
    quit(1 if failures else 0)
