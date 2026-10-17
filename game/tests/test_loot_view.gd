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

func click(point: Vector2) -> void:
    var event := InputEventMouseButton.new()
    event.position = point
    event.button_index = MOUSE_BUTTON_LEFT
    event.button_mask = MOUSE_BUTTON_MASK_LEFT
    event.pressed = true
    # Mouse positions are logical viewport coordinates, independent of window stretch.
    root.push_input(event, true)
    var release: InputEventMouseButton = event.duplicate()
    release.pressed = false
    release.button_mask = 0
    root.push_input(release, true)

func win_fixture(view: Node) -> void:
    view.arena.set_physics_process(false)
    view.journey.combat.simulation.spawn_remaining = 0
    for actor in view.journey.combat.simulation.actors.values():
        if actor.team == 2:
            actor.health = 0
            actor.down_remaining = 2

func enter_first(view: Node) -> void:
    for step in range(100):
        view.travel(Vector2i.RIGHT)
        if view.arena != null: return
    check(false, "Test travel must enter the first lair")

func _initialize() -> void:
    run_checks.call_deferred()

func run_checks() -> void:
    var view: Node = load("res://scenes/main.tscn").instantiate()
    view.definition = load("res://scripts/content/world_definition.gd").new()
    view.debug_mode=true
    view.saving_enabled = false
    root.add_child(view)
    view.set_physics_process(false)
    view.journey.restart(0x4d4f4f4e)
    await process_frame
    var expected: Dictionary = view.journey.lair_loot.grassland_west.duplicate(true)
    enter_first(view)
    win_fixture(view)
    view._physics_process(0.02)
    check(view.loot_view == null, "Automatic loot waits for completed death animations")
    view.journey.combat.simulation.advance()
    view.journey.combat.simulation.advance()
    view._physics_process(0.02)
    check(view.loot_view != null and not view.arena.visible, "Completed victory automatically opens the classic loot screen")
    var frozen: Dictionary = view.journey.combat.simulation.snapshot()
    var initial_world: Dictionary = view.journey.world.snapshot()
    await process_frame
    check(view.journey.combat.simulation.snapshot() == frozen, "Combat remains frozen throughout loot interaction")
    for key in [KEY_R, KEY_F1, KEY_F2, KEY_F3]: press(key)
    check(view.loot_view != null and view.journey.world.snapshot() == initial_world, "Battle/restart/mode/practice keys cannot mutate an open loot result")
    if view.loot_view.help_visible: press(KEY_F1)
    press(KEY_DOWN)
    var chosen: String = view.loot_view.rows()[view.loot_view.selected]
    press(KEY_SPACE)
    check(view.journey.inventory.items.get(chosen, 0) == 1, "Arrow and Space dispatch transfers the selected item")
    click(view.loot_view.row_rect(0).get_center())
    check(view.journey.inventory.gold == expected.gold + 10 and view.journey.available_loot().gold == 0, "Mouse dispatch transfers gold once")
    check(view.journey.combat.simulation.snapshot() == frozen, "Taking loot does not alter combat health, timing or state")
    click(view.loot_view.continue_rect.get_center())
    check(view.loot_view == null and view.arena == null and view.journey.world.cleared.size() == 1, "Mouse continue closes loot and returns to the cleared map")
    view.set_physics_process(false)
    var remainder: Dictionary = expected.items.duplicate(true)
    remainder[chosen] -= 1
    if remainder[chosen] == 0: remainder.erase(chosen)
    check(view.journey.inventory.gold == expected.gold + 10 and view.journey.inventory.items == {chosen: 1} and view.journey.lair_loot.grassland_west.items == remainder, "Column exit keeps unselected loot in the chest")
    var settled: Dictionary = view.journey.snapshot()
    press(KEY_F3)
    check(view.journey.snapshot() == settled, "Map return shortcuts cannot duplicate loot")
    press(KEY_R)
    view.set_physics_process(false)
    check(view.journey.inventory == {"gold":10,"items":{}}, "A new journey empties the collected pack")
    # Explicit empty-chest fixture verifies the no-reward result and Escape path.
    view.journey.lair_loot.grassland_west = {"gold":0,"items":{},"kind":4}
    enter_first(view)
    win_fixture(view)
    press(KEY_ENTER)
    check(view.loot_view == null, "Enter cannot skip a pending death animation")
    view.journey.combat.simulation.advance()
    view.journey.combat.simulation.advance()
    press(KEY_ENTER)
    check(view.loot_view != null and view.loot_view.rows().is_empty(), "An empty chest still presents a valid victory screen")
    press(KEY_SPACE)
    press(KEY_ESCAPE)
    check(view.loot_view == null and view.arena == null and view.journey.world.cleared.size() == 1 and view.journey.inventory == {"gold":10,"items":{}}, "Esc completes an empty chest without awarding phantom loot or quitting")
    view.set_physics_process(false)
    view.queue_free()
    await process_frame
    if failures == 0:
        print("PASS: death-animation wait, automatic loot, frozen combat, keyboard/mouse takes, guarded shortcuts, column exit leaves unselected loot, empty chest and reset")
    quit(1 if failures else 0)
