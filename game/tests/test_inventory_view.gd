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
    event = event.duplicate()
    event.pressed = false
    Input.parse_input_event(event)
    Input.flush_buffered_events()

func click(point: Vector2) -> void:
    var event := InputEventMouseButton.new()
    event.position = point
    event.button_index = MOUSE_BUTTON_LEFT
    event.button_mask = MOUSE_BUTTON_MASK_LEFT
    event.pressed = true
    root.push_input(event, true)
    event = event.duplicate()
    event.pressed = false
    event.button_mask = 0
    root.push_input(event, true)

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
    view.journey.world.position = view.journey.town("highwood").position
    view.journey.enter_town("highwood")
    view.show_town()
    press(KEY_I)
    check(view.inventory_view != null, "Space opens inventory without triggering an action")
    var start: Dictionary = view.journey.snapshot()
    for key in [KEY_R, KEY_F3, KEY_F1]: press(key)
    view.travel(Vector2i.RIGHT)
    check(view.inventory_view != null and view.arena == null and view.journey.snapshot() == start, "inventory freezes travel and blocks journey/practice shortcuts")
    if view.inventory_view.help_visible: press(KEY_F1)
    press(KEY_2)
    press(KEY_SPACE)
    check(view.journey.character.weapon == "broad_sword" and view.journey.inventory.gold == 0, "keyboard selects supplies and pays the actual weapon price")
    press(KEY_SPACE)
    check(view.journey.inventory.gold == 0, "repeated purchase refuses duplicates")
    view.journey.character.experience = 3
    click(view.inventory_view.tab_rect(2).get_center())
    click(view.inventory_view.row_rect(0).get_center())
    check(view.journey.character.stats.strength == 2 and view.journey.character.experience == 0, "mouse tab and row spend actual experience")
    press(KEY_1)
    view.journey.inventory.items = {"healing_potion": 2, "gem_of_seeing": 1, "scroll_of_the_hawk": 1, "scroll_of_haste": 1, "scroll_of_acquisition": 1}
    view.journey.character.health = 4
    press(KEY_SPACE)
    check(view.journey.character.health == 20 and view.journey.inventory.items.healing_potion == 1, "pack activation heals from the real inventory")
    press(KEY_DOWN)
    press(KEY_SPACE)
    check(view.inventory_view.target_item == "gem_of_seeing", "gem opens target selection without consuming")
    press(KEY_ESCAPE)
    check(view.inventory_view != null and view.inventory_view.target_item.is_empty() and view.journey.inventory.items.gem_of_seeing == 1, "Esc cancels targeting and keeps the gem")
    view.inventory_view.selected = view.inventory_view.rows().find("gem_of_seeing")
    press(KEY_SPACE)
    press(KEY_DOWN)
    press(KEY_SPACE)
    check(view.inventory_view.inspection == "grassland_east" and not view.journey.inventory.items.has("gem_of_seeing") and view.journey.world.cleared.is_empty(), "gem inspects chosen lair without clearing it")
    view.inventory_view.selected = view.inventory_view.rows().find("scroll_of_the_hawk")
    press(KEY_SPACE)
    check(view.inventory_view.target_item == "scroll_of_the_hawk", "hawk opens map targeting")
    click(view.inventory_view.target_rect.position + Vector2(300, 200))
    var destination: Vector2i = view.inventory_view.cursor
    press(KEY_SPACE)
    check(view.journey.world.position == destination and not view.journey.inventory.items.has("scroll_of_the_hawk"), "map click chooses and Space confirms teleport")
    view.inventory_view.selected = view.inventory_view.rows().find("scroll_of_acquisition")
    press(KEY_SPACE)
    check(view.journey.inventory.items.scroll_of_acquisition == 1, "unsupported rival context explains and keeps its scroll")
    press(KEY_ENTER)
    check(view.inventory_view == null, "Enter closes inventory")
    view.set_physics_process(false)
    if view.journey.turn_pending:
        check(view.journey.day==2,"Hawk departure spends the town visit exactly once")
        press(KEY_ENTER)
    var day: int = view.journey.day
    press(KEY_E)
    check(view.journey.day == day + 1 and view.journey.turn_pending, "map E ends the turn and shows the next-round pause")
    press(KEY_ENTER)
    # A managed arena must receive and retain its entry profile across ready/retry.
    view.journey.world.position = Vector2i(57, 63)
    for step in range(30):
        view.travel(Vector2i.RIGHT)
        if view.arena != null: break
    check(view.arena != null, "map still opens normal combat")
    view.arena.set_physics_process(false)
    check(view.arena.session.simulation.actors[1].maximum == 20 and view.arena.session.simulation.actors[1].damage_bonus == 3, "arena ready keeps current sword and upgraded strength")
    view.arena.session.simulation.actors[1].health = 1
    press(KEY_R)
    check(view.arena.session.simulation.actors[1].health == 20 and view.arena.session.simulation.actors[1].damage_bonus == 3, "retry restores entry kit with upgrades intact")
    press(KEY_ESCAPE)
    press(KEY_F2)
    view.arena.set_physics_process(false)
    check(view.arena.session.simulation.actors[1].maximum == 20 and view.arena.session.simulation.actors[1].damage_bonus == 0, "standalone practice cannot inherit journey equipment")
    press(KEY_F3)
    press(KEY_I)
    check(view.inventory_view != null, "I also opens the pack")
    press(KEY_I)
    check(view.inventory_view == null, "I closes the pack")
    view.queue_free()
    await process_frame
    if failures == 0: print("PASS: inventory keyboard/mouse, guarded map, purchases/upgrades, healing, targeting/cancel/teleport, unsupported contexts, rest and managed/profile/practice isolation")
    quit(1 if failures else 0)
