extends RefCounted

# Explicit verification/capture entry. Normal play does not load this module.
var host: Node

func _init(view: Node) -> void:
    host = view

func start(arguments: PackedStringArray) -> void:
    for argument in arguments:
        if argument.begins_with("--network-role="):
            host.set_physics_process(false);host.set_process_input(false);host.set_process_unhandled_key_input(false);host.set_process_unhandled_input(false)
            host.debug_mode_review=preload("res://debug/fixtures/network_duel_review.gd").new()
            host.debug_mode_review.report.call_deferred(host)
            return
    if "--practice-probe" in arguments:
        host.set_physics_process(false);host.set_process_input(false);host.set_process_unhandled_key_input(false);host.set_process_unhandled_input(false)
        host.debug_mode_review=preload("res://debug/fixtures/practice_review.gd").new()
        host.debug_mode_review.report.call_deferred(host)
        return
    if "--layered-graphics-probe" in arguments:
        host.set_physics_process(false);host.set_process_input(false);host.set_process_unhandled_key_input(false);host.set_process_unhandled_input(false)
        host.debug_mode_review=load("res://debug/fixtures/layered_graphics_review.gd").new()
        host.debug_mode_review.report.call_deferred(host)
        return
    if "--local-players-probe" in arguments:
        host.set_physics_process(false);host.set_process_input(false);host.set_process_unhandled_key_input(false);host.set_process_unhandled_input(false)
        host.debug_mode_review=load("res://debug/fixtures/local_players_review.gd").new()
        host.debug_mode_review.report.call_deferred(host)
        return
    if "--controller-probe" in arguments:
        host.set_physics_process(false);host.set_process_input(false);host.set_process_unhandled_key_input(false);host.set_process_unhandled_input(false)
        host.debug_mode_review=load("res://debug/fixtures/controller_review.gd").new()
        host.debug_mode_review.report.call_deferred(host)
        return
    if "--debug-mode-probe" in arguments:
        host.set_physics_process(false);host.set_process_unhandled_key_input(false)
        host.set_process_input(false);host.set_process_unhandled_input(false)
        host.debug_mode_review=preload("res://debug/fixtures/debug_mode_review.gd").new()
        host.debug_mode_review.report.call_deferred(host)
        return
    if "--monster-timing-probe" in arguments:
        host.set_physics_process(false);host.set_process_unhandled_key_input(false)
        host.monster_timing_review=preload("res://debug/fixtures/monster_timing_review.gd").new()
        host.monster_timing_review.report.call_deferred(host)
        return
    if "--trogg-timing-probe" in arguments:
        host.set_physics_process(false);host.set_process_unhandled_key_input(false)
        host.trogg_timing_review=preload("res://debug/fixtures/trogg_timing_review.gd").new()
        host.trogg_timing_review.report.call_deferred(host)
        return
    for arg in arguments:
        if arg.begins_with("--entry-lanes-probe="):
            host.set_physics_process(false);host.set_process_unhandled_key_input(false)
            host.entry_lanes_review=preload("res://debug/fixtures/entry_lanes_review.gd").new()
            host.entry_lanes_review.report.call_deferred(host,arg.trim_prefix("--entry-lanes-probe="))
            return
    for argument in arguments:
        if argument.begins_with("--enemy-scaling-probe="):
            host.set_physics_process(false);host.set_process_unhandled_key_input(false)
            host.enemy_scaling_review=preload("res://debug/fixtures/enemy_scaling_review.gd").new()
            host.enemy_scaling_review.report.call_deferred(host,argument.trim_prefix("--enemy-scaling-probe="))
            return
    if "--knight-rhythm-batch" in arguments:
        host.set_physics_process(false);host.set_process_unhandled_key_input(false)
        preload("res://debug/fixtures/knight_rhythm_fixture.gd").batch.call_deferred(host)
        return
    if "--ratman-ground-batch" in arguments:
        host.set_physics_process(false);host.set_process_unhandled_key_input(false)
        preload("res://debug/fixtures/ratman_ground_fixture.gd").batch.call_deferred(host)
        return
    if "--recovery-roster" in arguments:
        host.set_physics_process(false);host.set_process_unhandled_key_input(false)
        preload("res://debug/fixtures/combat_recovery_review.gd").batch.call_deferred(host)
        return
    if "--pacing-batch" in arguments:
        host.set_physics_process(false);host.set_process_unhandled_key_input(false)
        preload("res://debug/fixtures/combat_pacing_fixture.gd").batch.call_deferred(host)
        return
    Engine.physics_ticks_per_second = host.rules.tick_rate
    host.loot_character_demo="--loot-character-demo" in arguments
    if host.loot_character_demo:
        host.saving_enabled=false
        host.loot_character_fixture=preload("res://debug/fixtures/loot_character_fixture.gd").new()
    for argument in arguments:
        if argument.begins_with("--knight-demo="):host.knight_demo=argument.trim_prefix("--knight-demo=")
        if argument.begins_with("--locations-demo="):host.locations_demo=argument.trim_prefix("--locations-demo=")
        if argument.begins_with("--scrolls-demo="):host.scrolls_demo=argument.trim_prefix("--scrolls-demo=")
        if argument.begins_with("--rivals-demo="):host.rivals_demo=argument.trim_prefix("--rivals-demo=")
        if argument.begins_with("--intro-demo="):host.intro_demo=argument.trim_prefix("--intro-demo=")
        if argument.begins_with("--revisit-demo="):host.revisit_demo=argument.trim_prefix("--revisit-demo=")
        if argument.begins_with("--ending-demo="):host.ending_demo=argument.trim_prefix("--ending-demo=")
        if argument.begins_with("--stonehenge-demo="):host.henge_demo=argument.trim_prefix("--stonehenge-demo=")
        if argument.begins_with("--quest-demo="):host.quest_demo=argument.trim_prefix("--quest-demo=")
    if not host.locations_demo.is_empty():
        if host.locations_demo not in ["wizard-item","wizard-stat","wizard-gold","wizard-frog","highwood","waterdeep","tavern-win","tavern-loss"]:push_error("Unknown location fixture");host.get_tree().quit(1);return
        host.saving_enabled=false
        host.locations_fixture=preload("res://debug/fixtures/town_locations_fixture.gd").new()
    if not host.scrolls_demo.is_empty():
        if host.scrolls_demo not in ["acquire","cancel","wyrm","catch","recover"]:push_error("Unknown targeted scroll fixture");host.get_tree().quit(1);return
        host.saving_enabled=false
        host.scrolls_fixture=preload("res://debug/fixtures/targeted_scrolls_fixture.gd").new()
    if not host.rivals_demo.is_empty():
        if host.rivals_demo not in ["round","duel","protection","defeat","final"]:push_error("Unknown rival fixture");host.get_tree().quit(1);return
        host.saving_enabled=false
        host.rivals_fixture=preload("res://debug/fixtures/rival_knights_fixture.gd").new()
    if not host.quest_demo.is_empty() or not host.ending_demo.is_empty() or not host.knight_demo.is_empty():host.saving_enabled=false
    if not host.knight_demo.is_empty():host.knight_fixture=preload("res://debug/fixtures/knight_selection_fixture.gd").new()
    if not host.intro_demo.is_empty():
        if host.intro_demo not in ["full","skip","menu"]:push_error("Unknown intro fixture");host.get_tree().quit(1);return
        host.saving_enabled=false
    if not host.revisit_demo.is_empty():
        if host.revisit_demo not in ["on","off","resume","loss","retreat"]:push_error("Unknown revisit fixture");host.get_tree().quit(1);return
        host.saving_enabled=false
        host.revisit_fixture=preload("res://debug/fixtures/revisit_fixture.gd").new()
    host.campaign_demo = "--journey-demo" in arguments
    host.dragon_demo = "--dragon-map-demo" in arguments
    host.travel_demo = "--map-turns-demo" in arguments
    host.map_icons_demo = "--map-icons-demo" in arguments
    if host.map_icons_demo:host.saving_enabled=false
    host.continue_smoke = "--continue-smoke" in arguments
    host.equipment_demo = "--equipment-demo" in arguments
    if "--no-save" in arguments: host.saving_enabled = false
    host.balok_map_demo = "--balok-map-demo" in arguments
    host.troll_map_demo = "--troll-map-demo" in arguments
    host.axe_map_demo = "--axe-map-demo" in arguments
    host.map_demo = "--map-demo" in arguments or host.axe_map_demo or host.troll_map_demo or host.balok_map_demo
    if host.map_demo or host.equipment_demo or host.campaign_demo:
        # Keep the released milestone's explicit replay fixture stable. Ordinary
        # journeys use the independently verified original source table resource.
        host.definition = load("res://scripts/content/world_definition.gd").new()
    # Retained single-character milestone replays stay isolated from the new
    # four-slot scheduler. Ordinary journeys and the rival fixture use all slots.
    if "--single-knight-fixture" in arguments or host.loot_character_demo or not host.revisit_demo.is_empty() or host.map_icons_demo or not host.ending_demo.is_empty() or not host.quest_demo.is_empty() or not host.henge_demo.is_empty() or host.dragon_demo or host.travel_demo:
        host.definition=host.definition.duplicate();host.definition.rival_turns=false
    # A fresh journey rolls once; the visual replay uses an explicit repeatable seed.
    host.journey = host.Journey.new(host.definition, host.rules, 0x4d4f4f4e if not host.knight_demo.is_empty() or not host.locations_demo.is_empty() or not host.scrolls_demo.is_empty() or not host.rivals_demo.is_empty() or not host.intro_demo.is_empty() or host.loot_character_demo or not host.revisit_demo.is_empty() or host.map_icons_demo or not host.ending_demo.is_empty() or not host.quest_demo.is_empty() or not host.henge_demo.is_empty() or host.map_demo or host.equipment_demo or host.campaign_demo or host.dragon_demo or host.travel_demo else host.fresh_seed())
    if host.travel_demo: host.saving_enabled=false
    if host.dragon_demo:
        host.saving_enabled = false
        host.journey.day = 9 # Explicit visual fixture: eight completed travel rounds.
    if host.equipment_demo:
        # Explicit UI fixture, not rewards earned through a human playthrough.
        host.journey.inventory.gold = 100
        host.journey.character.experience = 3
        host.journey.character.health = 8
        for id in host.journey.loot_rules.items: host.journey.inventory.items[id] = 1
        host.journey.character.health += int(host.journey.character_rules.protection_health)
        host.journey.world.position = host.journey.town("highwood").position
        host.journey.enter_town("highwood")
        host.show_town()
        host.show_inventory()
    if host.map_demo: host.demo_reward = host.journey.lair_loot[host.definition.lairs[host.demo_site_index()].id].duplicate(true)
    var standalone: bool = false
    for argument in arguments:
        if argument.begins_with("--stonehenge-demo="):
            host.henge_demo=argument.trim_prefix("--stonehenge-demo=")
            host.saving_enabled=false
        if argument == "--cooperative": host.journey.mode = &"cooperative"
        if argument == "--no-gore": host.no_gore = true
        if argument == "--smoke": host.smoke = true
        if argument.begins_with("--town-preview="):
            host.town_preview = argument.trim_prefix("--town-preview=")
            host.saving_enabled = false
        if argument.begins_with("--service-preview="): host.service_preview=argument.trim_prefix("--service-preview=")
        if argument.begins_with("--service-phase="): host.service_phase=argument.trim_prefix("--service-phase=")
        if argument.begins_with("--save-path="): host.save_path = argument.trim_prefix("--save-path=")
        if argument.begins_with("--capture-sequence="): host.sequence_path = argument.trim_prefix("--capture-sequence=")
        if argument.begins_with("--capture="): host.capture_path = argument.trim_prefix("--capture=")
        if argument.begins_with("--capture-stride="):host.capture_stride=clampi(int(argument.trim_prefix("--capture-stride=")),1,50)
        if argument in ["--demo", "--combat-demo", "--trogg-demo", "--defence-demo", "--duel", "--lair", "--axe", "--axe-demo", "--troll", "--troll-demo", "--balok", "--balok-demo"]:
            standalone = true
        if argument.begins_with("--encounter=") or argument.begins_with("--creature-showcase="):
            var choice: String = argument.get_slice("=",1)
            if host.rules.encounters.has(choice):
                host.show_training(StringName(choice))
                host.set_physics_process(false)
                return
    if standalone:
        host.show_training(&"balok_lair" if "--balok" in arguments or "--balok-demo" in arguments else (&"duel" if "--duel" in arguments else (&"troll_lair" if "--troll" in arguments or "--troll-demo" in arguments else (&"axe_lair" if "--axe" in arguments or "--axe-demo" in arguments else &"spear_lair"))))
        host.set_physics_process(false)
        return
    if not host.town_preview.is_empty():
        var place: Dictionary = host.journey.town(host.town_preview)
        if place.is_empty():
            push_error("Unknown town preview")
            host.get_tree().quit(1)
            return
        host.journey.world.position = place.position
        host.journey.enter_town(host.town_preview)
        host.show_town()
        if not host.service_preview.is_empty():
            if host.service_preview not in host.town_view.rows() or host.service_preview=="leave":
                push_error("Unknown service preview for this town")
                host.get_tree().quit(1)
                return
            host.open_town_service(host.service_preview)
            if host.inventory_view!=null and host.inventory_view.service_screen!=null:
                if host.service_phase=="donation" and host.service_preview in ["healer","mystic"]: host.inventory_view.service_screen.phase="donation"
                elif host.service_phase=="dice" and host.service_preview=="tavern": host.inventory_view.service_screen.phase="dice"
    if host.campaign_demo:
        host.save_store = host.Store.new("user://journey-demo.json", host.journey.validate_checkpoint,not host.debug_mode)
        host.journey.store = host.save_store
        host.journey.persist()
    elif host.saving_enabled and not host.map_demo and not host.equipment_demo and not host.smoke:
        host.save_store = host.Store.new(host.save_path, host.journey.validate_checkpoint,not host.debug_mode)
        var previous: Dictionary = host.save_store.load_checkpoint()
        # Opening/menu never creates or replaces a journey save. New/Continue
        # is the explicit point where the selected campaign becomes active.
        host.show_menu(previous,false)
    else: host.saving_enabled = false
    if host.continue_smoke:
        if host.menu_view == null or host.menu_view.saved.is_empty():
            push_error("Continue probe requires a compatible saved journey")
            host.get_tree().quit(1)
            return
        var expected: Dictionary = host.menu_view.saved.duplicate(true)
        host.menu_choice("continue")
        host.continued_correctly = host.journey.checkpoint() == expected
    host.setup_dragon_display()
    if not host.quest_demo.is_empty():host.setup_quest_demo()
    if not host.ending_demo.is_empty():host.setup_ending_demo()
    if not host.knight_demo.is_empty():host.knight_fixture.setup(host,host.knight_demo)
    if not host.henge_demo.is_empty():
        host.journey.character.lives=3
        host.journey.character.health=7
        host.journey.character.life_loss=2
        host.journey.character.experience=3
        host.journey.inventory.items={"ring_of_protection":1,"healing_potion":2,"scroll_of_haste":1}
        host.journey.world.position=Vector2i(88,147)
        for step in range(64):
            host.travel(Vector2i.DOWN)
            if host.definition.confirm_entry and not host.journey.arrivals().filter(func(row: Dictionary) -> bool:return row.id=="stonehenge").is_empty():
                host.enter_location("stonehenge")
            if host.henge_view!=null:break
        if host.henge_view==null:push_error("Stonehenge fixture failed to walk into original node")
    host.get_tree().auto_accept_quit = false
    if host.saving_enabled and not host.continue_smoke and host.menu_view!=null:host.show_intro()
    elif not host.intro_demo.is_empty():
        host.intro_initial=host.journey.checkpoint()
        host.show_menu(host.intro_initial,host.intro_demo=="menu")
        if host.intro_demo!="menu":host.show_intro()
    if not host.sequence_path.is_empty() or not host.capture_path.is_empty():
        RenderingServer.viewport_set_update_mode(host.get_viewport().get_viewport_rid(), RenderingServer.VIEWPORT_UPDATE_ALWAYS)

func advance_travel_demo() -> void:
    # Explicit native rendering/export fixture, never a user's saved journey.
    if host.elapsed in [1,81,161,241]:
        host.journey.restart(0x4d4f4f4e)
        host.journey.world.position={1:Vector2i(35,40),81:Vector2i(65,160),161:Vector2i(157,45),241:Vector2i(250,160)}[host.elapsed]
    if host.elapsed<=240:
        host.travel(Vector2i.DOWN if host.elapsed>160 else Vector2i.RIGHT)
        if host.elapsed in [80,160,240]:
            var expected: Vector2i={80:Vector2i(75,40),160:Vector2i(85,160),240:Vector2i(157,55)}[host.elapsed]
            if host.journey.world.position==expected and host.arena==null: host.travel_demo_checked+=1
    elif host.elapsed<=300:
        if host.elapsed==241:
            host.journey.character.health=12
            host.journey.travel_spent=host.journey.travel_allowance()-1
        host.travel(Vector2i.LEFT)
        if host.elapsed==300 and host.journey.turn_pending and host.journey.day==2 and host.journey.character.health==15 and host.journey.world.position==Vector2i(249,160): host.travel_demo_checked+=1
    if host.elapsed==301: host.journey.begin_turn()
    if host.elapsed==321:
        host.journey.world.position=host.journey.town("highwood").position
        host.journey.enter_town("highwood")
        host.show_town()
    if host.elapsed==350:
        host.leave_town()
        if host.journey.turn_pending and host.journey.turn_reason=="town" and host.journey.day==3: host.travel_demo_checked+=1
    if host.elapsed==371: host.journey.begin_turn()
    host.queue_redraw()

func advance_map_demo() -> void:
    if host.loot_view != null:
        host.loot_demo_ticks += 1
        if host.loot_demo_ticks in [50, 100]: host.loot_view.take_selected()
        if host.loot_demo_ticks >= 200:
            host.return_to_map()
            host.demo_finished = true
    elif host.arena != null:
        host.arena.advance_demo()
        host.arena.animator.update(host.arena.session.simulation.actors, host.rules, host.arena.art)
        host.arena.queue_redraw()
        if host.arena.demo_ticks >= host.arena.demo_length():
            if host.arena.session.simulation.outcome() != "victory":
                push_error("Map visual fixture did not win its encounter")
                host.get_tree().quit(1)
                return
            host.return_to_map()
    elif not host.demo_finished:
        var direction := Vector2i.ZERO
        if host.elapsed > 25:
            if host.balok_map_demo:
                # Travel around the west entrance, then approach East from below.
                var target: Vector2i = host.definition.lairs[1].position
                if host.journey.world.position.x < target.x:
                    direction = Vector2i(1, 1 if host.journey.world.position.y < 90 else 0)
                else: direction = Vector2i(0, signi(target.y - host.journey.world.position.y))
            elif host.axe_map_demo or host.troll_map_demo:
                var target: Vector2i = host.definition.lairs[host.demo_site_index()].position
                direction = Vector2i(signi(target.x - host.journey.world.position.x), signi(target.y - host.journey.world.position.y))
            else: direction = Vector2i.RIGHT
        host.travel(direction)

func demo_site_index() -> int:
    if host.balok_map_demo: return 1
    return 3 if host.troll_map_demo else (2 if host.axe_map_demo else 0)

func demo_length() -> int:
    if not host.knight_demo.is_empty():return 500 if host.knight_demo.ends_with("-ritual") else 340
    if not host.locations_demo.is_empty():return 500 if host.locations_demo.begins_with("wizard-") else 300 if host.locations_demo.begins_with("tavern-") else 700
    if not host.scrolls_demo.is_empty():return 420 if host.scrolls_demo=="catch" else 240
    if not host.rivals_demo.is_empty():return 2600 if host.rivals_demo=="round" else 420
    if not host.intro_demo.is_empty():return host.IntroView.ART.total_ticks+180 if host.intro_demo=="full" else 240
    if host.loot_character_demo:return 240
    if not host.revisit_demo.is_empty():return 240
    if host.map_icons_demo:return 360
    if not host.ending_demo.is_empty():return preload("res://scripts/domain/moonstone_quest.gd").ENDING_TICKS+80
    if not host.quest_demo.is_empty():return 600
    if not host.henge_demo.is_empty():return 900
    if host.travel_demo: return 400
    if host.dragon_demo: return 600
    if host.campaign_demo: return 1000
    if host.equipment_demo: return 420
    if host.balok_map_demo: return 1350
    return 1000 if host.axe_map_demo or host.troll_map_demo else host.DEMO_LENGTH

func capture_map() -> void:
    RenderingServer.force_draw(false)
    host.get_tree().quit(host.get_viewport().get_texture().get_image().save_png(host.capture_path))

func capture_frame() -> void:
    RenderingServer.force_draw(false)
    var result: int = host.get_viewport().get_texture().get_image().save_png(host.sequence_path.path_join("%03d.png" % (host.elapsed - 1)))
    if result != OK:
        host.get_tree().quit(result)
    elif host.elapsed >= host.demo_length():
        host.finish_demo()
    else:
        host.set_physics_process(true)

func finish_demo() -> void:
    if not host.knight_demo.is_empty():host.knight_fixture.finish(host);return
    if not host.locations_demo.is_empty():host.locations_fixture.finish(host);return
    if not host.scrolls_demo.is_empty():host.scrolls_fixture.finish(host);return
    if not host.rivals_demo.is_empty():host.rivals_fixture.finish(host);return
    if not host.intro_demo.is_empty():
        var valid: bool=host.journey.checkpoint()==host.intro_initial and host.menu_view!=null and host.intro_view==null
        valid=valid and host.intro_finishes==(0 if host.intro_demo=="menu" else 1)
        if host.intro_demo=="full":valid=valid and host.intro_seen.size()==host.IntroView.ART.sections.size()
        if not valid:push_error("Intro fixture failed");host.get_tree().quit(1);return
        print("INTRO_STATE=",JSON.stringify({"case":host.intro_demo,"initial":host.intro_initial,"final":host.journey.checkpoint(),"sections":host.intro_seen.keys(),"finishes":host.intro_finishes,"rows":host.menu_view.rows()}))
        print("PASS: native opening/menu, credits, skip and unchanged campaign")
        host.get_tree().quit();return
    if host.loot_character_demo:host.loot_character_fixture.finish(host);return
    if not host.revisit_demo.is_empty():host.revisit_fixture.finish(host);return
    if host.map_icons_demo:
        if host.map_icons_checks!=7:push_error("Map icon fixture incomplete: "+str(host.map_icons_checks));host.get_tree().quit(1)
        else:print("PASS: original map icons, fire entry, towns/home/tower/lair and four markers; MAP_STATE=",host.journey.checkpoint());host.get_tree().quit()
        return
    if not host.ending_demo.is_empty():
        host.ending_results.final=host.journey.checkpoint()
        if host.journey.quest.ending.stage!="complete" or host.journey.quest.ending.tick!=preload("res://scripts/domain/moonstone_quest.gd").ENDING_TICKS or host.journey.character.experience!=3 or host.menu_view==null:
            push_error("Ending fixture failed its finite saved playback");host.get_tree().quit(1);return
        print("ENDING_STATE=",JSON.stringify(host.ending_results))
        print("PASS: native full ending, saved clock, continuous music and automatic menu return")
        host.get_tree().quit();return
    if not host.quest_demo.is_empty():
        host.quest_results.final=host.journey.checkpoint()
        if host.journey.quest.ending.get("stage","")!="ready" or host.journey.quest.stones==0 or host.journey.owned_keys!=0:
            push_error("Quest fixture failed its earned stone/phase/ending handoff")
            host.get_tree().quit(1);return
        print("QUEST_STATE=",JSON.stringify(host.quest_results))
        print("PASS: Guardian reward, carried stone, wrong-phase offering and saved matched-phase ending handoff")
        host.get_tree().quit();return
    if not host.henge_demo.is_empty():
        host.henge_results.final=host.journey.checkpoint()
        if not host.journey.turn_pending or host.journey.day!=2 or not host.journey.henge.is_empty():
            push_error("Stonehenge demo failed its single spent-turn return")
            host.get_tree().quit(1);return
        print("STONEHENGE_STATE=",JSON.stringify(host.henge_results))
        print("PASS: Stonehenge offering/ritual/temple returned with one spent turn")
        host.get_tree().quit();return
    if host.travel_demo:
        if host.travel_demo_checked!=5 or host.journey.day!=3 or host.journey.turn_pending or host.journey.character.health!=16 or host.journey.character.experience!=0 or host.arena!=null or host.town_view!=null:
            push_error("Terrain/turn fixture failed: "+str(host.journey.checkpoint()))
            host.get_tree().quit(1)
        else:
            print("PASS: original terrain80tick displacements40/20/10, exhaustion/repeat-input pause, begin once, town end once; state=",host.journey.checkpoint())
            host.get_tree().quit()
        return
    if host.dragon_demo:
        if host.journey.combat!=null or not host.journey.world.dragon.active or host.dragon_demo_frames.size()!=8 or host.dragon_demo_max_x<=350 or not host.dragon_demo_return:
            push_error("Dragon map fixture failed to animate, leave the map and return")
            host.get_tree().quit(1)
        else:
            print("PASS: original map Dragon eight poses/glide, edge entry/offscreen return; state=", host.journey.checkpoint())
            host.get_tree().quit()
        return
    if host.campaign_demo:
        var valid: bool = host.journey.world.cleared.size() == 3 and host.journey.character.stats.strength == 2 and host.journey.character.experience == 0 and host.journey.character.armour == "chainmail" and host.journey.day == 2 and host.journey.character.health == 30 and host.journey.inventory.gold == 54 and host.menu_view == null and host.journey.town_id == ""
        if not valid:
            push_error("Journey visual fixture did not preserve its rewards/town/upgrades/save: " + str(host.journey.snapshot()))
            host.get_tree().quit(1)
        else:
            print("PASS: 24-lair map -> three outcome fixtures -> town smith/healer/temple -> autosave/menu/continue; state=", host.journey.checkpoint())
            host.get_tree().quit()
        return
    if host.equipment_demo:
        if host.journey.character.stats.strength != 2 or host.journey.character.experience != 0 or host.journey.character.armour != "chainmail" or not host.journey.haste or host.journey.inventory.items.has("healing_potion") or not host.journey.revealed_lairs.has("grassland_east"):
            push_error("Equipment UI fixture did not complete its item/purchase/upgrade actions")
            host.get_tree().quit(1)
        else:
            print("PASS: inventory UI fixture: equip armour, heal, haste, inspect real loot, buy strength; state=", host.journey.snapshot())
            host.get_tree().quit()
        return
    if not host.demo_finished or host.arena != null or host.loot_view != null or host.journey.world.cleared.size() != 1 or host.journey.inventory.gold != host.demo_reward.gold + host.journey.character_rules.starting_gold or host.journey.inventory.items != host.demo_reward.items:
        push_error("Map demo did not return with exactly one cleared lair")
        host.get_tree().quit(1)
        return
    print("PASS: map -> scripted creature fight -> victory loot -> individual takes -> inventory and cleared map")
    host.get_tree().quit()

func advance_map_icons_demo() -> void:
    # Deliberately staged locations; no movement/quest rewards are invented.
    if host.elapsed==1:host.journey.world.position=Vector2i(187,100)
    if host.elapsed==40:host.journey.world.position=Vector2i(98,50)
    if host.elapsed==79 and host.town_view==null and host.outline_visible("highwood")==false:host.map_icons_checks+=1
    if host.elapsed==80:
        host.request_entry()
        if host.town_view!=null and host.journey.town_id=="highwood":host.map_icons_checks+=1
    if host.elapsed==110:host.leave_town();host.journey.begin_turn()
    if host.elapsed==120:host.journey.world.position=Vector2i(292,158)
    if host.elapsed==140:
        host.request_entry()
        if host.town_view!=null and host.journey.town_id=="waterdeep":host.map_icons_checks+=1
    if host.elapsed==165:host.leave_town();host.journey.begin_turn()
    if host.elapsed==170:host.journey.world.position=Vector2i(98,160)
    if host.elapsed==190:
        host.request_entry()
        if host.henge_view!=null:host.map_icons_checks+=1
    if host.elapsed==215:
        host.journey.advance_henge();host.journey.leave_henge_offering();host.journey.leave_henge();host.close_henge();host.journey.begin_turn()
    if host.elapsed==220:
        host.journey.world.position=Vector2i(25,17);host.journey.character.lives=2
        # Home and the nearby first lair can overlap: select home explicitly.
        host.enter_location("home")
        if host.inventory_view!=null and host.journey.character.lives==3:host.map_icons_checks+=1
    if host.elapsed==245:host.close_inventory();host.journey.begin_turn()
    if host.elapsed==250:host.journey.world.position=Vector2i(219,19)
    if host.elapsed==260:
        host.request_entry()
        if host.inventory_view!=null and host.journey.town_id=="wizard":host.map_icons_checks+=1
    if host.elapsed==275:host.close_inventory();host.journey.begin_turn()
    if host.elapsed==280:host.journey.world.position=Vector2i(25,112)
    if host.elapsed==320:
        host.request_entry()
        if host.arena!=null and host.journey.world.active_lair=="lair_05":host.map_icons_checks+=1;host.arena.set_physics_process(false)
    if host.elapsed==345:host.return_to_map(false)
    host.queue_redraw()

func advance_equipment_demo() -> void:
    if host.inventory_view == null: return
    if host.elapsed == 70: host.journey.use_item("healing_potion")
    if host.elapsed == 110: host.inventory_view.set_tab(1)
    if host.elapsed == 145:
        host.inventory_view.selected = 2
        host.inventory_view.activate()
    if host.elapsed == 185: host.inventory_view.set_tab(2)
    if host.elapsed == 220: host.inventory_view.activate()
    if host.elapsed == 260:
        host.inventory_view.set_tab(0)
        host.journey.use_item("scroll_of_haste")
    if host.elapsed == 300:
        host.inventory_view.selected = host.inventory_view.rows().find("gem_of_seeing")
        host.inventory_view.activate()
    if host.elapsed == 335:
        host.inventory_view.selected = host.inventory_view.rows().find("grassland_east")
        host.inventory_view.activate()
    if host.elapsed == 380:
        host.inventory_view.inspection = ""
        host.inventory_view.selected = host.inventory_view.rows().find("scroll_of_the_hawk")
        host.inventory_view.activate()
        host.inventory_view.cursor = Vector2i(120, 70)
    host.inventory_view.queue_redraw()

func advance_intro_demo() -> void:
    var base: int=host.IntroView.ART.total_ticks if host.intro_demo=="full" else (40 if host.intro_demo=="skip" else 0)
    if host.elapsed==base+25:host.menu_view.activate("options")
    if host.elapsed==base+100:host.menu_view.activate("back")

func setup_quest_demo() -> void:
    # Staged result, not an AI campaign playthrough. Actual entry and settlement
    # still own keys, XP, RNG, carried object and victory prerequisites.
    var bit: int={"full":0,"new":1,"half_a":2,"half_b":3,"resume":0}.get(host.quest_demo,0)
    var roller_script=preload("res://scripts/domain/loot_roller.gd")
    for seed_value in range(2,65536):
        var roller: RefCounted=roller_script.new(host.journey.loot_rules,seed_value)
        if (roller.next_value()&3)==bit:host.journey.quest.seed=seed_value;break
    host.journey.owned_keys=15
    host.journey.world.position=Vector2i(152,89)
    for step in range(64):
        host.travel(Vector2i.DOWN)
        if host.definition.confirm_entry:host.enter_location("valley_guardian")
        if host.arena!=null:break
    if host.arena==null:push_error("Quest demo failed actual Valley entry");return
    host.arena.set_physics_process(false)
    host.journey.combat.simulation.spawn_remaining=0
    for actor in host.journey.combat.simulation.actors.values():
        if actor.team==2:actor.health=0
    host.journey.prepare_loot()
    host.show_loot()

func setup_ending_demo() -> void:
    # A staged Guardian result uses the real settlement, phase gate and handoff.
    host.quest_demo={"new":"new","half":"half_a"}.get(host.ending_demo,"full")
    host.setup_quest_demo();host.quest_demo=""
    host.quest_view.activate()
    while not host.journey.quest_rules.matches(host.journey.quest.stones,host.journey.calendar().moon_phase):
        host.journey.rest();host.journey.begin_turn()
    host.demo_walk_henge()
    for tick in range(20):host.quest_view.advance()
    host.quest_view.activate()
    host.ending_results.initial=host.journey.checkpoint()

func advance_ending_demo() -> void:
    if host.quest_view!=null:host.quest_view.advance()
    if host.elapsed==290 and host.ending_demo=="resume":
        # Same presentation owner: no invented music restart on an in-memory
        # roundtrip. A new process seeks its saved PCM time once on Continue.
        var restored: RefCounted=host.Journey.new(host.definition,host.rules,2)
        if not restored.restore_checkpoint(JSON.parse_string(JSON.stringify(host.journey.checkpoint()))):
            push_error("Ending resume fixture rejected its own checkpoint");return
        host.journey=restored;host.quest_view.journey=host.journey
    if host.elapsed==290 and host.ending_demo=="skip":host.quest_view.activate()
    if host.elapsed==2300 and host.ending_demo=="resume_late":
        var restored: RefCounted=host.Journey.new(host.definition,host.rules,2)
        if not restored.restore_checkpoint(JSON.parse_string(JSON.stringify(host.journey.checkpoint()))):
            push_error("Late ending Continue rejected its own save");return
        host.journey=restored;host.quest_view.journey=host.journey
    if host.elapsed==3000 and host.ending_demo=="skip_late":host.quest_view.activate()
    if host.elapsed in [35,36,131,290,424,460,700,940,1666,2170,2406,2526,2638,3000,3211,3343,3843,4062]:host.ending_results[str(host.elapsed)]=host.journey.checkpoint()

func demo_walk_henge() -> void:
    host.journey.world.position=Vector2i(88,147)
    for step in range(64):
        host.travel(Vector2i.DOWN)
        if host.definition.confirm_entry:host.enter_location("stonehenge")
        if host.henge_view!=null or host.quest_view!=null:break

func advance_quest_demo() -> void:
    if host.elapsed==60:host.quest_view.activate()
    if host.elapsed==90:host.show_inventory()
    if host.elapsed==180:
        host.close_inventory()
        var wrong_phase: int=2 if host.journey.quest.stones==2 else 0
        while host.journey.calendar().moon_phase!=wrong_phase:
            host.journey.rest();host.journey.begin_turn()
        host.demo_walk_henge()
    if host.elapsed==210:host.henge_view.activate()
    if host.elapsed==260:host.henge_view.back()
    if host.elapsed==300:host.henge_view.back()
    if host.elapsed==320:host.journey.begin_turn()
    if host.elapsed==360:
        while not host.journey.quest_rules.matches(host.journey.quest.stones,host.journey.calendar().moon_phase):
            host.journey.rest();host.journey.begin_turn()
        host.demo_walk_henge()
    if host.quest_view!=null:host.quest_view.advance()
    if host.elapsed==380 and host.quest_demo=="resume":
        var saved: Dictionary=host.journey.checkpoint()
        var copy: RefCounted=host.Journey.new(host.definition,host.rules,2)
        if not copy.restore_checkpoint(JSON.parse_string(JSON.stringify(saved))) or copy.checkpoint()!=saved:push_error("Quest Continue changed state")
        host.journey=copy;host.quest_view.journey=host.journey
    if host.elapsed==410:host.quest_view.activate()
    if host.elapsed in [59,110,211,301,379,411]:host.quest_results[str(host.elapsed)]=host.journey.checkpoint()

func advance_henge_demo() -> void:
    if host.elapsed==60:host.henge_view.activate()
    if host.elapsed==120:
        if host.henge_demo=="decline":host.henge_view.back()
        else:
            host.henge_view.selected=host.henge_view.rows().find("ring_of_protection" if host.henge_demo=="ring" else "healing_potion")
            host.henge_view.activate()
    if host.elapsed==250 and host.henge_demo=="skip":host.henge_view.back()
    if host.elapsed==350 and host.henge_demo=="resume":
        var saved: Dictionary=host.journey.checkpoint()
        var resumed: RefCounted=host.Journey.new(host.definition,host.rules,2)
        if not resumed.restore_checkpoint(JSON.parse_string(JSON.stringify(saved))) or resumed.checkpoint()!=saved:push_error("Ritual checkpoint changed on Continue")
        host.journey=resumed;host.henge_view.journey=host.journey
    if host.henge_view!=null:host.henge_view.advance()
    if host.elapsed in [59,119,121,249,351,710]:host.henge_results[str(host.elapsed)]=host.journey.checkpoint()
    if host.elapsed==740 and host.henge_demo=="upgrade":host.henge_view.activate()
    if host.elapsed==800:host.henge_view.back()

func demo_enter(index: int) -> void:
    var site: Dictionary = host.definition.lairs[index]
    host.journey.world.position = site.position - Vector2i(8, 0)
    for step in range(20):
        host.travel(Vector2i.RIGHT)
        if host.arena != null:
            host.arena.set_physics_process(false)
            return

func demo_win() -> void:
    host.journey.combat.simulation.spawn_remaining = 0
    for actor in host.journey.combat.simulation.actors.values():
        if actor.team == 2: actor.health = 0
    host.show_loot()

func advance_campaign_demo() -> void:
    if host.elapsed == 40:
        host.demo_enter(0)
        host.journey.combat.simulation.actors[1].health = 11
    if host.elapsed in [100, 280, 440]: host.demo_win()
    if host.elapsed == 160: host.journey.take_loot("gold")
    if host.elapsed in [190,350,500]: host.return_to_map()
    if host.elapsed == 240: host.demo_enter(1)
    if host.elapsed == 400: host.demo_enter(2)
    if host.elapsed == 550:
        host.journey.world.position = Vector2i(74, 28)
        for step in range(20):
            host.travel(Vector2i.RIGHT)
            if host.town_view != null: break
    if host.elapsed == 600:
        host.open_town_service("smith")
        host.inventory_view.selected = 2
        host.inventory_view.activate()
    if host.elapsed == 650:
        host.close_inventory()
        host.open_town_service("healer")
    if host.elapsed == 700:
        host.inventory_view.service_screen.phase="donation"
        host.inventory_view.service_screen.donation=10
        host.inventory_view.activate()
    if host.elapsed == 750:
        host.close_inventory()
        host.open_town_service("temple")
    if host.elapsed == 800: host.inventory_view.activate()
    if host.elapsed == 850:
        host.close_inventory()
        host.leave_town()
    if host.elapsed == 875: host.journey.begin_turn()
    if host.elapsed == 900: host.show_menu(host.save_store.load_checkpoint())
    if host.elapsed == 950: host.menu_choice("continue")
    if host.inventory_view != null: host.inventory_view.queue_redraw()
    if host.town_view != null: host.town_view.queue_redraw()
    host.queue_redraw()
