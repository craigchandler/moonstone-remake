extends SceneTree

const Store = preload("res://scripts/session/journey_store.gd")
const Journey = preload("res://scripts/session/journey_session.gd")
var failures: int = 0
var save_path: String = "user://unit-campaign-view.json"

func check(condition: bool, label: String) -> void:
    if not condition:
        failures += 1
        push_error(label)

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

func view() -> Node:
    var result: Node = load("res://scenes/main.tscn").instantiate()
    result.definition = load("res://scripts/content/world_definition.gd").new()
    result.save_path = save_path
    root.add_child(result)
    result.set_physics_process(false)
    return result

func _initialize() -> void:
    run_checks.call_deferred()

func run_checks() -> void:
    for suffix in ["", ".bak", ".tmp"]:
        if FileAccess.file_exists(save_path + suffix): DirAccess.remove_absolute(save_path + suffix)
    var current: Node = view()
    await process_frame
    check(current.intro_view!=null and current.menu_view!=null and not FileAccess.file_exists(save_path),"first launch shows intro/menu without creating a journey save")
    press(KEY_SPACE)
    check(current.intro_view==null and current.menu_view!=null,"skip opens menu without starting play")
    press(KEY_N)
    check(current.selection_view!=null,"New opens a draft knight selection")
    press(KEY_ENTER);press(KEY_ENTER)
    check(current.menu_view == null and current.journey.world.definition.lairs.size() == 24, "New begins expanded journey")
    current.journey.world.position = Vector2i(74,28)
    for step in range(20):
        current.travel(Vector2i.RIGHT)
        if current.town_view != null: break
    check(current.town_view != null and current.arena == null, "walking into town opens recovered town backdrop")
    current.journey.inventory.gold = 100 # Explicit affordable-purchase fixture.
    click(current.town_view.button_rect(0).get_center())
    check(current.inventory_view.tab == 1 and not current.town_view.visible, "town smith button opens classic equipment panel")
    click(current.inventory_view.row_rect(0).get_center())
    check(current.journey.character.weapon == "broad_sword" and current.journey.inventory.gold == 90, "original sword icon pays once")
    press(KEY_ENTER)
    press(KEY_DOWN) # Tavern occupies the second original menu entry.
    press(KEY_DOWN)
    press(KEY_SPACE)
    check(current.inventory_view.tab == 3 and current.journey.service == "healer", "healer menu opens priced health/life choices")
    current.journey.character.health = 4
    press(KEY_SPACE) # Original greeting -> donation controls.
    press(KEY_1) # Offer the ten-gold treatment price.
    press(KEY_SPACE)
    check(current.journey.character.health == 20 and current.journey.inventory.gold == 80, "healer UI pays real ten-gold cost")
    press(KEY_ESCAPE)
    press(KEY_DOWN)
    press(KEY_SPACE)
    current.journey.character.experience = 3 # Explicit upgrade fixture.
    press(KEY_SPACE)
    check(current.inventory_view.tab == 2 and current.journey.character.stats.strength == 2 and current.journey.character.experience == 0, "High Temple UI spends XP")
    current.queue_free()
    await process_frame
    current = view()
    await process_frame
    check(current.menu_view != null and current.menu_view.saved.character.stats.strength == 2, "new scene offers Continue from real saved data")
    var saved_bytes: PackedByteArray=FileAccess.get_file_as_bytes(save_path)
    press(KEY_SPACE)
    check(FileAccess.get_file_as_bytes(save_path)==saved_bytes,"intro skip preserves existing save bytes")
    press(KEY_C)
    check(current.menu_view == null and current.town_view != null and current.inventory_view.tab == 2 and current.journey.character.stats.strength == 2 and current.journey.character.experience == 0, "Continue restores town/service and upgrade without recharging")
    press(KEY_ENTER)
    press(KEY_ESCAPE)
    check(current.town_view == null and current.journey.day == 2 and current.journey.turn_pending, "town departure returns to map and ends turn")
    press(KEY_ENTER)
    current.journey.inventory.items.gem_of_seeing = 1
    press(KEY_I)
    press(KEY_SPACE)
    for step in range(7): press(KEY_DOWN)
    var inspected: String = current.inventory_view.rows()[current.inventory_view.selected]
    check(current.inventory_view.visible_indices().size() == 24 and current.inventory_view.target_rect.has_point(current.inventory_view.row_rect(7).get_center()), "gem targets show all twenty-four lairs on the map")
    click(current.inventory_view.row_rect(7).get_center())
    check(current.journey.revealed_lairs.has(inspected) and not current.journey.inventory.items.has("gem_of_seeing"), "map icon target consumes only the chosen gem")
    press(KEY_ENTER)
    current.journey.world.position = Vector2i(57,63)
    for step in range(20):
        current.travel(Vector2i.RIGHT)
        if current.arena != null: break
    current.arena.set_physics_process(false)
    current.journey.combat.simulation.spawn_remaining = 0
    for actor in current.journey.combat.simulation.actors.values():
        if actor.team == 2: actor.health = 0
    press(KEY_ENTER)
    click(current.loot_view.row_rect(0).get_center())
    var gold: int = current.journey.inventory.gold
    check(current.journey.character.experience == 1 and current.journey.available_loot().gold == 0, "partial loot and one XP recorded")
    current.queue_free()
    await process_frame
    current = view()
    await process_frame
    press(KEY_SPACE) # Skip the launch intro before choosing Continue.
    press(KEY_C)
    check(current.loot_view != null and current.arena != null and not current.arena.visible and current.journey.combat.simulation.outcome() == "victory", "Continue restores partial loot instead of restarting encounter")
    check(current.journey.inventory.gold == gold and not current.journey.take_loot("gold") and current.journey.character.experience == 1, "continued chest cannot duplicate gold/XP")
    press(KEY_ENTER)
    check(current.arena == null and current.journey.world.cleared.size() == 1, "continued loot finishes normally")
    current.set_physics_process(false)
    press(KEY_R)
    check(current.menu_view != null and current.journey.world.cleared.size() == 1, "R opens journey menu before a new run")
    press(KEY_N)
    check(current.selection_view!=null,"New opens a draft knight selection")
    press(KEY_ENTER);press(KEY_ENTER)
    check(current.menu_view == null and current.journey.world.cleared.is_empty() and current.journey.character.experience == 0 and current.journey.character.weapon == "long_sword", "New Journey explicitly resets character/map and writes new save")
    current.queue_free()
    await process_frame
    # Pure result fixtures exercise every unique site's XP, purchases and save reload.
    var definition: Resource = load("res://scripts/content/world_definition.gd").new()
    var rules: Resource = load("res://content/foundation_rules.tres")
    var journey: RefCounted = Journey.new(definition, rules, 0x4d4f4f4e)
    var upgrades: int = 0
    for index in range(24):
        var site: Dictionary = definition.lairs[index]
        journey.world.position = site.position - Vector2i(8,0)
        for step in range(20):
            if journey.travel(Vector2i.RIGHT): break
        check(journey.world.active_lair == site.id, "each of 24 sites routes to its own encounter")
        journey.combat.simulation.spawn_remaining = 0
        for actor in journey.combat.simulation.actors.values():
            if actor.team == 2: actor.health = 0
        journey.return_to_map()
        if (index + 1) % 3 == 0:
            journey.world.position = journey.town("highwood").position
            journey.enter_town("highwood")
            journey.open_service("temple")
            check(journey.upgrade_stat(["strength", "constitution", "endurance"][upgrades % 3]), "each three earned points pays for a chosen upgrade")
            upgrades += 1
            journey.leave_town()
            journey.begin_turn()
        if index == 11:
            var copied: RefCounted = Journey.new(definition,rules,13)
            check(copied.restore_checkpoint(journey.checkpoint()) and copied.checkpoint() == journey.checkpoint(), "halfway continuation preserves full progression/chests")
            journey = copied
    check(journey.world.complete() and upgrades == 8 and journey.character.experience == 0 and journey.character.stats == {"strength":4,"constitution":4,"endurance":3}, "full 24-lair run funds eight genuine upgrades with no duplicate XP")
    if failures == 0: print("PASS: town keyboard/mouse services, real disk/menu Continue, restored partial loot, New Journey, and all 24 outcome fixtures funding eight paid stat upgrades across a reload")
    quit(1 if failures else 0)
