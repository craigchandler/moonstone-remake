extends Node2D

const Runtime=preload("res://scripts/session/runtime_mode.gd")
var debug_mode: bool=Runtime.debug_enabled()
var diagnostics: RefCounted
var parse_launch_arguments: bool=true
var debug_mode_review: RefCounted

const Store = preload("res://scripts/session/journey_store.gd")
const TownView = preload("res://scripts/presentation/town_view.gd")
const JourneyMenu = preload("res://scripts/presentation/journey_menu.gd")
const Journey = preload("res://scripts/session/journey_session.gd")
const Arena = preload("res://scenes/arena.tscn")
const InventoryView = preload("res://scripts/presentation/inventory_view.gd")
const LootView = preload("res://scripts/presentation/loot_view.gd")
const HengeView = preload("res://scripts/presentation/stonehenge_view.gd")
const QuestView = preload("res://scripts/presentation/quest_view.gd")
const Locations = preload("res://scripts/domain/map_locations.gd")
const IntroView=preload("res://scripts/presentation/intro_view.gd")
const KnightSelection=preload("res://scripts/presentation/knight_selection.gd")
const KnightArt=preload("res://assets/classic/knight_selection/art.tres")
var trogg_timing_review: RefCounted
var monster_timing_review: RefCounted
var entry_lanes_review: RefCounted
var enemy_scaling_review: RefCounted
var selection_view: Node2D
var local_setup: Node2D
var knight_demo: String=""
var knight_fixture: RefCounted
var intro_view: Node2D
var intro_demo: String=""
var locations_demo: String=""
var locations_fixture: RefCounted
var scrolls_demo: String=""
var scrolls_fixture: RefCounted
var rivals_demo: String=""
var rivals_fixture: RefCounted
var intro_initial: Dictionary={}
var intro_seen: Dictionary={}
var intro_finishes: int=0
var arrival_choices: Array[Dictionary]=[]
var arrival_selected: int=0
var map_icons_demo: bool=false
var map_icons_checks: int=0
var revisit_demo: String=""
var revisit_fixture: RefCounted
var loot_character_demo: bool=false
var loot_character_fixture: RefCounted
var quest_view: Node2D
var quest_demo: String=""
var quest_results: Dictionary={}
var ending_demo: String=""
var ending_results: Dictionary={}
var henge_view: Node2D
var henge_demo: String=""
var henge_results: Dictionary={}
var definition: Resource = preload("res://content/first_journey.tres")
var rules: Resource = preload("res://content/foundation_rules.tres")
var art: Resource = preload("res://assets/classic/world/art.tres")
var journey: RefCounted
var arena: Node2D
var town_view: Node2D
var menu_view: Node2D
var saving_enabled: bool = true
var save_path: String = "user://journey.json"
var save_store: RefCounted
var campaign_demo: bool = false
var dragon_demo: bool = false
var dragon_demo_frames: Dictionary = {}
var dragon_demo_max_x: int = 10
var dragon_demo_return: bool = false
var release_movement: bool = false
var travel_demo: bool = false
var travel_demo_checked: int = 0
var town_preview: String = ""
var service_preview: String = ""
var service_phase: String = ""
var continue_smoke: bool = false
var continued_correctly: bool = false
var inventory_view: Node2D
var inventory_attack_context: bool = false
var practice_view: Node2D
var equipment_demo: bool = false
var loot_view: Node2D
var font: Font = ThemeDB.fallback_font
var map_rect := Rect2(0, 44, 512, 320)
var dragon_clip: Control
var dragon_sprite: Sprite2D
var smoke: bool = false
var map_demo: bool = false
var axe_map_demo: bool = false
var troll_map_demo: bool = false
var balok_map_demo: bool = false
var demo_finished: bool = false
var elapsed: int = 0
var sequence_path: String = ""
var capture_path: String = ""
var capture_stride: int=1
var no_gore: bool = false
var loot_demo_ticks: int = 0
var demo_reward: Dictionary = {}
const DEMO_LENGTH: int = 800

func _ready() -> void:
    add_to_group("moonstone_input_surfaces")
    var arguments: PackedStringArray = launch_arguments()
    if debug_mode:
        _debug().start(arguments)
        return
    Engine.physics_ticks_per_second = rules.tick_rate
    for argument in arguments:
        if argument == "--no-save": saving_enabled = false
        elif argument == "--no-gore": no_gore = true
        elif argument == "--smoke": smoke = true
        elif argument == "--continue-smoke": continue_smoke = true
        elif argument.begins_with("--save-path="): save_path = argument.trim_prefix("--save-path=")
    journey = Journey.new(definition, rules, fresh_seed())
    if saving_enabled and not smoke:
        save_store = Store.new(save_path, journey.validate_checkpoint)
        show_menu(save_store.load_checkpoint(), false)
    else:
        saving_enabled = false
    if continue_smoke:
        if menu_view == null or menu_view.saved.is_empty():
            push_error("Continue probe requires a compatible saved journey")
            get_tree().quit(1)
            return
        var expected: Dictionary = menu_view.saved.duplicate(true)
        menu_choice("continue")
        continued_correctly = journey.checkpoint() == expected
    setup_dragon_display()
    get_tree().auto_accept_quit = false
    if saving_enabled and not continue_smoke and menu_view != null:
        show_intro()

func setup_dragon_display() -> void:
    dragon_clip = Control.new()
    dragon_clip.position = map_rect.position
    dragon_clip.size = map_rect.size
    dragon_clip.clip_contents = true
    dragon_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(dragon_clip)
    dragon_sprite = Sprite2D.new()
    dragon_clip.add_child(dragon_sprite)
    update_dragon_sprite()

func _debug() -> RefCounted:
    if diagnostics == null:
        diagnostics = load("res://debug/world_diagnostics.gd").new(self)
    return diagnostics

func launch_arguments() -> PackedStringArray:
    return Runtime.user_arguments(debug_mode) if parse_launch_arguments else PackedStringArray()

func travel(direction: Vector2i) -> void:
    if intro_view!=null or not arrival_choices.is_empty() or quest_view!=null or henge_view != null or arena != null or inventory_view != null or town_view != null or menu_view != null or practice_view != null: return
    if journey.travel(direction):
        if not journey.pending_attack.is_empty():
            journey.persist()
            queue_redraw()
            return
        if journey.combat==null:
            queue_redraw()
            return
        show_lair()
        if journey.loot_open: show_loot()
    elif not journey.quest.ending.is_empty():show_quest()
    elif not journey.henge.is_empty(): show_henge()
    elif not journey.town_id.is_empty(): show_town()
    queue_redraw()

func request_entry() -> void:
    if not definition.confirm_entry:return
    var rows: Array[Dictionary]=journey.arrivals()
    if rows.size()==1:enter_location(rows[0].id)
    elif rows.size()>1:arrival_choices=rows;arrival_selected=0
    queue_redraw()

func enter_location(id: String) -> void:
    arrival_choices=[]
    if not journey.confirm_location(id):return
    release_movement=true
    if journey.combat!=null:
        show_lair()
        if journey.loot_open:show_loot()
    elif not journey.quest.ending.is_empty():show_quest()
    elif not journey.henge.is_empty():show_henge()
    elif not journey.town_id.is_empty():show_town()
    queue_redraw()

func show_lair() -> void:
    arena = Arena.instantiate()
    arena.managed_by_world = true
    arena.debug_mode=debug_mode
    arena.mode = journey.mode
    arena.encounter = journey.world.lair(journey.world.active_lair).encounter
    arena.session = journey.combat
    if journey.party!=null:
        for id in journey.combat.human_actors:arena.local_players[id]=int(journey.combat.human_actors[id])-1
        arena.duel_ready=arena.local_players.size()>1
        for id in journey.combat.simulation.actors:
            var actor: Dictionary=journey.combat.simulation.actors[id]
            var seat: int=journey.party.active if actor.team==1 else journey.party.seat_for(journey.world.active_lair)
            if seat>=0:arena.actor_colours[id]=journey.party.players[seat].identity.kind
    arena.knight_kind=journey.identity.kind
    arena.knight_name=journey.identity.name
    var rival: Dictionary=journey.rivals.find(journey.world.active_lair)
    if not rival.is_empty():
        for actor in journey.combat.simulation.actors.values():
            if actor.team==2:actor["display_label"]=journey.world.lair(rival.id).name
    var backdrop: String="res://assets/classic/lairs/"+journey.world.active_lair+".png"
    if ResourceLoader.exists(backdrop): arena.background_override=load(backdrop)
    if map_demo:
        # Scripted visual fixture; no physical keyboard/normal-AI playthrough is implied.
        arena.demo = true
        arena.trogg_demo = not axe_map_demo and not troll_map_demo and not balok_map_demo
        arena.axe_demo = axe_map_demo
        arena.troll_demo = troll_map_demo
        arena.balok_demo = balok_map_demo
    arena.return_to_map_requested.connect(return_to_map)
    add_child(arena)
    if no_gore: arena.gore_enabled = false
    if map_demo: arena.set_physics_process(false)
    queue_redraw()

func show_training(encounter: StringName) -> void:
    if not debug_mode:return
    journey.persist()
    arena = Arena.instantiate()
    arena.knight_kind=journey.identity.kind
    arena.knight_name=journey.identity.name
    arena.mode = journey.mode
    arena.encounter = encounter
    arena.debug_mode=debug_mode
    for site in definition.lairs:
        if site.encounter==encounter:
            var path: String="res://assets/classic/lairs/"+site.id+".png"
            if ResourceLoader.exists(path): arena.background_override=load(path)
            break
    add_child(arena)
    queue_redraw()

func return_to_map(collect_remaining: bool = true) -> void:
    if arena == null: return
    if arena.managed_by_world and journey.combat!=null and journey.combat.simulation.outcome() != "ongoing" and not battle_animations_finished(): return
    var valley_acknowledged: bool=arena.managed_by_world and journey.world.active_lair=="valley_guardian" and journey.quest.valley_stone!=0 and not journey.quest.notice
    if arena.managed_by_world and arena.session.simulation.outcome() == "victory" and loot_view == null and not valley_acknowledged:
        show_loot()
        return
    if loot_view != null:
        remove_child(loot_view)
        loot_view.queue_free()
        loot_view = null
    if arena.managed_by_world: journey.return_to_map(collect_remaining)
    remove_child(arena)
    arena.queue_free()
    arena = null
    set_physics_process(true)
    queue_redraw()

func fresh_seed() -> int:
    if not knight_demo.is_empty():return 0x4d4f4f4e # Explicit fixture seed; ordinary New still randomises.
    var generator := RandomNumberGenerator.new()
    generator.randomize()
    return generator.randi_range(2, 0x7fffffff)

func show_loot() -> void:
    if quest_view!=null:return
    if loot_view != null or arena == null or not arena.managed_by_world: return
    if not journey.prepare_loot(): return
    if journey.quest.notice:
        if arena!=null:arena.set_physics_process(false)
        show_quest()
        return
    arena.set_physics_process(false)
    arena.set_process_unhandled_key_input(false)
    arena.hide()
    loot_view = LootView.new()
    loot_view.journey = journey
    var player: Dictionary = journey.combat.simulation.actors[1]
    loot_view.health = player.health
    loot_view.maximum = player.maximum
    loot_view.daggers = player.daggers
    loot_view.finished.connect(func(): return_to_map(false))
    add_child(loot_view)
    queue_redraw()

func battle_animations_finished() -> bool:
    for actor in journey.combat.simulation.actors.values():
        if actor.health <= 0 and actor.down_remaining > 0: return false
    return true

func _physics_process(_delta: float) -> void:
    elapsed += 1
    if journey!=null and journey.party!=null and not journey.party.game_over and journey.character.lives<=0 and journey.combat==null and journey.rivals.active==0 and menu_view==null and arena==null:journey.party.end_turn(journey)
    if selection_view!=null:selection_view.advance()
    if inventory_view!=null and menu_view==null and intro_view==null and inventory_view.has_method("advance_visit"):
        inventory_view.advance_visit()
    if intro_view!=null:
        intro_seen[intro_view.ART.pose_at(intro_view.tick).scene]=true
        if intro_demo=="skip" and elapsed==40:
            var key:=InputEventKey.new();key.keycode=KEY_SPACE;key.pressed=true
            get_viewport().push_input(key,true)
        else:intro_view.advance()
        queue_redraw()
        if not sequence_path.is_empty() and elapsed%capture_stride==0:set_physics_process(false);capture_frame.call_deferred()
        return
    if journey.rivals.active!=0 and arena==null and inventory_view==null and town_view==null and menu_view==null and practice_view==null and quest_view==null and henge_view==null:
        journey.advance_rival_turn()
        if journey.combat!=null:show_lair()
        if not journey.pending_attack.is_empty():release_movement=true
    if not intro_demo.is_empty():advance_intro_demo()
    if not knight_demo.is_empty():knight_fixture.advance(self)
    elif not locations_demo.is_empty():locations_fixture.advance(self)
    elif not scrolls_demo.is_empty():scrolls_fixture.advance(self)
    elif not rivals_demo.is_empty():rivals_fixture.advance(self)
    elif loot_character_demo:loot_character_fixture.advance(self)
    if not revisit_demo.is_empty():revisit_fixture.advance(self)
    elif map_icons_demo:advance_map_icons_demo()
    elif not ending_demo.is_empty():advance_ending_demo()
    elif not quest_demo.is_empty():advance_quest_demo()
    elif quest_view!=null:quest_view.advance()
    elif not henge_demo.is_empty():
        advance_henge_demo()
    elif henge_view!=null:
        henge_view.advance()
    elif travel_demo:
        advance_travel_demo()
    elif dragon_demo:
        travel(Vector2i.ZERO)
        var flight: RefCounted = journey.world.dragon
        dragon_demo_frames[flight.frame()] = true
        dragon_demo_max_x = maxi(dragon_demo_max_x, flight.position.x)
        if flight.speed_x < 0: dragon_demo_return = true
    elif campaign_demo:
        advance_campaign_demo()
    elif equipment_demo:
        advance_equipment_demo()
    elif map_demo:
        advance_map_demo()
    elif arena == null and inventory_view == null and town_view == null and menu_view == null and practice_view == null:
        var direction: Vector2i=get_node("/root/MoonstoneInput").direction()
        if release_movement:
            if direction==Vector2i.ZERO: release_movement=false
            direction=Vector2i.ZERO
        travel(direction)
    elif arena != null and arena.managed_by_world and loot_view == null and journey.combat.simulation.outcome() == "victory" and battle_animations_finished():
        show_loot()
    update_dragon_sprite()
    if arena != null and arena.managed_by_world and not journey.battle_settled and journey.combat.simulation.outcome() != "ongoing": journey.persist()
    if continue_smoke and elapsed >= 40:
        if continued_correctly:
            print("PASS: separate exported process continues exact saved character, 24 chest rolls, cleared map, day and town state")
            get_tree().quit()
        else:
            push_error("Continued state differs from saved checkpoint")
            get_tree().quit(1)
    if smoke and elapsed >= 40:
        print("LAUNCH_MODE_STATE=",JSON.stringify({"debug":debug_mode,"equipment_demo":equipment_demo,"map_demo":map_demo,"campaign_demo":campaign_demo,"arena":arena!=null,"practice":practice_view!=null,"hints":map_hints(),"mode":journey.mode,"gold":journey.inventory.gold,"xp":journey.character.experience}))
        print("PASS: native overworld boots without disk images; mode=", journey.mode)
        get_tree().quit()
    if not capture_path.is_empty() and elapsed == 30: capture_map.call_deferred()
    if not sequence_path.is_empty() and (elapsed%capture_stride==0 or elapsed>=demo_length()):
        set_physics_process(false)
        capture_frame.call_deferred()
    elif (not locations_demo.is_empty() or not scrolls_demo.is_empty() or not rivals_demo.is_empty() or not intro_demo.is_empty() or loot_character_demo or not revisit_demo.is_empty()) and elapsed>=demo_length():finish_demo()
    elif map_icons_demo and elapsed>=360:
        if map_icons_checks!=7:push_error("Map icon fixture incomplete: "+str(map_icons_checks));get_tree().quit(1)
        else:print("PASS: original map icons, fire entry, towns/home/tower/lair and four markers; MAP_STATE=",journey.checkpoint());get_tree().quit()
    elif (not knight_demo.is_empty() or not ending_demo.is_empty() or not quest_demo.is_empty() or not henge_demo.is_empty() or map_demo or equipment_demo or campaign_demo or dragon_demo or travel_demo) and elapsed >= demo_length():
        finish_demo()

func advance_travel_demo() -> void:
    _debug().advance_travel_demo()

func advance_map_demo() -> void:
    _debug().advance_map_demo()

func demo_site_index() -> int:
    return _debug().demo_site_index()

func demo_length() -> int:
    return _debug().demo_length()

func capture_map() -> void:
    _debug().capture_map()

func capture_frame() -> void:
    _debug().capture_frame()

func finish_demo() -> void:
    _debug().finish_demo()

func _input(event: InputEvent) -> void:
    if debug_mode and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3 and quest_view == null and henge_view == null and inventory_view == null and loot_view == null and town_view == null and menu_view == null:
        return_to_map()
        get_viewport().set_input_as_handled()

func _unhandled_key_input(event: InputEvent) -> void:
    if intro_view!=null or quest_view!=null or henge_view!=null or arena != null or inventory_view != null or town_view != null or menu_view != null or practice_view != null or not event is InputEventKey or not event.pressed or event.echo: return
    if not debug_mode and event.keycode in Runtime.MAP_SHORTCUTS:return
    if journey.party!=null and journey.party.awaiting and event.keycode not in [KEY_ESCAPE,KEY_R]:
        get_viewport().set_input_as_handled()
        if event.keycode in [KEY_ENTER,KEY_SPACE,KEY_E,KEY_Z]:journey.begin_turn();release_movement=true
        queue_redraw();return
    if journey.rivals.active!=0 and journey.pending_attack.is_empty() and event.keycode not in [KEY_ESCAPE,KEY_R]:
        get_viewport().set_input_as_handled();return
    if journey.turn_pending and event.keycode not in [KEY_ESCAPE,KEY_R]:
        get_viewport().set_input_as_handled()
        if event.keycode in [KEY_ENTER,KEY_SPACE,KEY_E]:
            journey.begin_turn()
            release_movement=true
        queue_redraw()
        return
    if not arrival_choices.is_empty():
        get_viewport().set_input_as_handled()
        if event.keycode==KEY_ESCAPE:arrival_choices=[]
        elif event.keycode in [KEY_UP,KEY_DOWN]:arrival_selected=posmod(arrival_selected+(1 if event.keycode==KEY_DOWN else -1),arrival_choices.size())
        elif event.keycode in [KEY_SPACE,KEY_ENTER,KEY_Z]:enter_location(arrival_choices[arrival_selected].id)
        elif event.keycode>=KEY_1 and event.keycode<KEY_1+arrival_choices.size():enter_location(arrival_choices[event.keycode-KEY_1].id)
        queue_redraw()
        return
    if not journey.pending_attack.is_empty():
        get_viewport().set_input_as_handled()
        journey.dismiss_attack_notice()
        show_inventory()
        return
    if event.keycode == KEY_ESCAPE: quit_game()
    elif event.keycode in [KEY_SPACE, KEY_I]:
        get_viewport().set_input_as_handled()
        show_inventory()
    elif event.keycode in [KEY_ENTER,KEY_Z]:
        get_viewport().set_input_as_handled()
        request_entry()
    elif event.keycode == KEY_E: journey.rest()
    elif event.keycode == KEY_P: show_practice()
    elif event.keycode == KEY_R:
        if save_store != null:
            journey.persist()
            show_menu(save_store.load_checkpoint())
        elif debug_mode: journey.restart(fresh_seed())
        else:show_menu(journey.checkpoint())
    elif event.keycode == KEY_TAB:
        if journey.party!=null:return
        journey.mode = &"cooperative" if journey.mode == &"competitive" else &"competitive"
        journey.persist()
    elif event.keycode in [KEY_F1, KEY_F2, KEY_F4, KEY_F5, KEY_F6]:
        show_training({KEY_F1: &"duel", KEY_F2: &"spear_lair", KEY_F4: &"axe_lair", KEY_F5: &"troll_lair", KEY_F6: &"balok_lair"}[event.keycode])
    queue_redraw()

func map_point(position: Vector2i) -> Vector2:
    return map_rect.position + Vector2(position) * (map_rect.size / Vector2(320, 200))

func icon_rect(position: Vector2i,texture: Texture2D) -> Rect2:
    return Rect2(map_point(position),texture.get_size()*map_rect.size/Vector2(320,200))

func outline_visible(id: String) -> bool:
    return elapsed%40<20 and journey.arrivals().any(func(row: Dictionary) -> bool:return row.id==id)

func rival_markers() -> Array[Vector2i]:
    if not journey.rivals.records.is_empty():
        var points: Array[Vector2i]=[]
        for row in journey.rivals.records:points.append(row.position)
        return points
    # Historical single-knight replay fixtures retain their original markers.
    var result: Array[Vector2i]=[Vector2i(0,187),Vector2i(303,192)]
    if not journey.world.cleared.has("roaming_black_knight"):result.push_front(journey.world.lair("roaming_black_knight").position)
    return result

func draw_classic_map() -> void:
    for site in definition.lairs:
        if journey.world.cleared.has(site.id) and not journey.has_treasure(site.id):continue
        draw_texture_rect(art.lair,icon_rect(site.position,art.lair),false)
        if outline_visible(site.id):draw_texture_rect(art.map_icons["31"],icon_rect(site.position,art.map_icons["31"]),false)
    for index in range(Locations.PLACES.size()):
        if index<4 and index!=journey.identity.kind:continue
        var node: Dictionary=Locations.home(journey.identity.kind) if index<4 else Locations.PLACES[index]
        if outline_visible(node.id):
            var texture: Texture2D=art.map_icons[str(node.sprite)]
            draw_texture_rect(texture,icon_rect(node.position,texture),false)
    var points: Array[Vector2i]=rival_markers()
    for index in range(points.size()):
        var cel: String="4"
        if not journey.rivals.records.is_empty():
            if journey.rivals.records[index].character.lives<=0:cel="33"
            elif journey.rivals.active==index+1:cel="9"
        var texture: Texture2D=art.map_icons[cel]
        if journey.party!=null:
            var seat: int=journey.party.others()[index]
            var colour: int=journey.party.players[seat].identity.kind
            if journey.rivals.records[index].character.lives>0:
                texture=KnightArt.active_tokens[colour] if journey.rivals.active==index+1 else KnightArt.tokens[colour]
                if journey.party.personal[seat].frog_days>0:texture=KnightArt.frogs[colour]
        var rect: Rect2=icon_rect(points[index],texture)
        var visible_rect: Rect2=rect.intersection(map_rect)
        var scale_factor: Vector2=map_rect.size/Vector2(320,200)
        draw_texture_rect_region(texture,visible_rect,Rect2((visible_rect.position-rect.position)/scale_factor,visible_rect.size/scale_factor))
    var hero_icon: Texture2D=KnightArt.frogs[journey.identity.kind] if journey.places.frog_days>0 else KnightArt.tokens[journey.identity.kind]
    draw_texture_rect(hero_icon,icon_rect(journey.world.position,hero_icon),false)
    if journey.places.frog_days==0 and journey.rivals.active==0 and not journey.turn_pending and elapsed%40<20:draw_texture_rect(KnightArt.active_tokens[journey.identity.kind],icon_rect(journey.world.position,KnightArt.active_tokens[journey.identity.kind]),false)
    var dragon_site: Dictionary=journey.world.lair("roaming_dragon")
    if journey.world.cleared.has(dragon_site.id) and journey.has_treasure(dragon_site.id):draw_texture_rect(art.lair,icon_rect(dragon_site.position,art.lair),false)

func advance_map_icons_demo() -> void:
    _debug().advance_map_icons_demo()

func _unhandled_input(event: InputEvent) -> void:
    if intro_view!=null:return
    if journey!=null and journey.party!=null and journey.party.awaiting and arena==null and inventory_view==null and town_view==null and menu_view==null and practice_view==null:
        if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
            get_viewport().set_input_as_handled();journey.begin_turn();release_movement=true;queue_redraw()
        return
    if journey!=null and journey.rivals.active!=0 and journey.pending_attack.is_empty() and event is InputEventMouseButton and menu_view==null:
        get_viewport().set_input_as_handled();return
    if journey!=null and journey.turn_pending and arena==null and inventory_view==null and town_view==null and menu_view==null and practice_view==null:
        if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
            get_viewport().set_input_as_handled()
            journey.begin_turn()
            release_movement=true
            queue_redraw()
        return
    if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT and quest_view==null and henge_view==null and arena==null and inventory_view==null and town_view==null and menu_view==null and practice_view==null and not journey.attack_notice:
        get_viewport().set_input_as_handled()
        if not arrival_choices.is_empty():
            for i in range(arrival_choices.size()):
                if Rect2(120,145+i*28,400,28).has_point(event.position):
                    enter_location(arrival_choices[i].id)
                    break
        else:request_entry()
        return
    if journey==null or not journey.attack_notice or inventory_view!=null or menu_view!=null: return
    if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
        get_viewport().set_input_as_handled()
        journey.dismiss_attack_notice()
        show_inventory()

func update_dragon_sprite() -> void:
    if dragon_clip == null: return
    dragon_clip.visible = quest_view==null and henge_view==null and arena==null and town_view==null and inventory_view==null and menu_view==null and practice_view==null and not journey.turn_pending and journey.world.dragon.active
    if not dragon_clip.visible: return
    var flight: RefCounted = journey.world.dragon
    var frame: int = flight.frame()
    var texture: Texture2D = art.dragon_frames[frame]
    var offset := Vector2(art.dragon_offsets[frame]) + texture.get_size()/2
    dragon_sprite.flip_h = flight.facing == 3
    if dragon_sprite.flip_h: offset.x = -offset.x
    var scale_factor := map_rect.size/Vector2(320,200)
    dragon_sprite.texture = texture
    dragon_sprite.scale = scale_factor
    dragon_sprite.position = (Vector2(flight.position)+offset)*scale_factor

func _draw() -> void:
    if journey == null or arena != null: return
    var gold := Color("ddc68c")
    var muted := Color("9ba69a")
    var green := Color("8bc693")
    var cyan := Color("9acbd3")
    var ink := Color("121a19")
    draw_rect(Rect2(0, 0, 640, 400), ink)
    draw_texture_rect(art.background, map_rect, false)
    draw_string(font, Vector2(14, 28), "MOONSTONE", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, gold)
    var turn_label: String=("Black Knight %s: taking turn" % ["I","II","III"][journey.rivals.active-1]) if journey.rivals.active!=0 else "The journey / " + ("Co-op · AI ally" if journey.mode == &"cooperative" else "Solo")
    if journey.party!=null:turn_label=journey.party.players[journey.party.turn].identity.name+" / Local multiplayer"
    draw_string(font, Vector2(235, 27),turn_label,HORIZONTAL_ALIGNMENT_LEFT,-1,14 if journey.party!=null else 16,muted)
    if definition.confirm_entry:draw_classic_map()
    for index in range(0 if definition.confirm_entry else definition.lairs.size()):
        var site: Dictionary = definition.lairs[index]
        var point: Vector2 = map_point(site.position)
        var cleared: bool = journey.world.cleared.has(site.id)
        var colour: Color = green if cleared else gold
        draw_circle(point, 7, Color(0.02, 0.03, 0.02, 0.8))
        draw_arc(point, 7, 0, TAU, 20, colour, 1)
        draw_texture_rect(art.lair, Rect2(point - Vector2(7, 3), Vector2(14, 6)), false, green if cleared else Color.WHITE)
        draw_string(font, point + Vector2(8, 3), ("*" if journey.has_treasure(site.id) else "+") if cleared else str(index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, colour)
    for place in definition.towns:
        if definition.confirm_entry:continue
        var point: Vector2 = map_point(place.position)
        draw_circle(point, 6, ink)
        draw_arc(point, 6, 0, TAU, 20, cyan, 2)
        draw_string(font, point + Vector2(-11, -8), "H" if place.id == "highwood" else "W", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, cyan)
    if not definition.confirm_entry:
        var henge_point: Vector2=map_point(journey.Henge.POSITION)
        draw_arc(henge_point,6,0,TAU,20,cyan,2)
        draw_string(font,henge_point+Vector2(-4,-8),"S",HORIZONTAL_ALIGNMENT_LEFT,-1,12,cyan)
    for source in definition.special_encounters:
        if definition.confirm_entry:continue
        var site: Dictionary = journey.world.lair(source.id)
        if source.id == "roaming_dragon":
            if journey.world.cleared.has(site.id) and journey.has_treasure(site.id):
                draw_texture_rect(art.lair, Rect2(map_point(site.position)-Vector2(7,3),Vector2(14,6)),false)
            continue
        if journey.world.cleared.has(site.id): continue
        var point: Vector2 = map_point(site.position)
        draw_circle(point,8,Color("441a25"))
        draw_string(font,point+Vector2(-4,4),site.marker,HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("f2a387"))
    if not definition.confirm_entry:
        var player: Vector2 = map_point(journey.world.position)
        draw_circle(player + Vector2(0, 1), 9, Color(0.01, 0.02, 0.03, 0.8))
        draw_texture_rect(art.knight if journey.turn_pending else art.knight_active, Rect2(player - Vector2(8, 16), Vector2(16, 20)), false)
    draw_rect(Rect2(512, 44, 128, 320), ink)
    draw_line(Vector2(512, 44), Vector2(512, 364), Color("655f45"))
    var nearby: Array = definition.lairs.duplicate()
    nearby.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return journey.world.position.distance_squared_to(a.position) < journey.world.position.distance_squared_to(b.position))
    draw_string(font, Vector2(523, 65), nearby[0].region.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, gold)
    var cleared_lairs: int = 0
    for site in definition.lairs:
        if journey.world.cleared.has(site.id): cleared_lairs += 1
    draw_string(font, Vector2(523, 84), "%d / %d cleared" % [cleared_lairs, definition.lairs.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, green)
    draw_string(font, Vector2(523, 105), "NEARBY LAIRS", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, muted)
    for index in range(mini(3, nearby.size())):
        var site: Dictionary = nearby[index]
        var cleared: bool = journey.world.cleared.has(site.id)
        var y: int = 124 + index * 34
        draw_string(font, Vector2(523, y), "%d %s" % [definition.lairs.find(site) + 1, site.name], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, gold)
        draw_string(font, Vector2(523, y + 16), "Cleared" if cleared else str(rules.encounters[String(site.encounter)].enemy_label), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, green if cleared else muted)
    draw_string(font, Vector2(523, 236), "TOWNS", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, cyan)
    draw_string(font, Vector2(523, 253), "H  Highwood", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, cyan)
    draw_string(font, Vector2(523, 270), "W Waterdeep / S Henge", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, cyan)
    draw_string(font, Vector2(523, 294), "Round %d XP %d" % [journey.day, journey.character.experience], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, gold)
    draw_texture_rect(art.moon_frames[journey.calendar().moon_phase],Rect2(610,281,23,18),false)
    draw_string(font, Vector2(523, 312), "HP %d/%d  Lives %d" % [journey.character.health, journey.character.maximum(journey.inventory.items), journey.character.lives], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, muted)
    draw_string(font, Vector2(523, 330), "%d gp  Daggers %d" % [journey.inventory.gold, journey.character.daggers], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, gold)
    draw_string(font, Vector2(523, 348), "Travel %d/%d" % [journey.travel_remaining(), journey.travel_allowance()], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, muted)
    draw_string(font, Vector2(12, 379), map_hints()[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, gold)
    var status: String = "All 24 lairs cleared!" if journey.world.complete() else ("Quest ended; R opens new journey." if journey.character.lives <= 0 else (journey.message if not journey.message.is_empty() else ("Slow ground" if journey.world.terrain_mask()!=0 else journey.save_message)))
    draw_string(font,Vector2(523,358),"Keys: %d / 4" % String.num_int64(journey.key_mask(),2).count("1"),HORIZONTAL_ALIGNMENT_LEFT,-1,12,gold)
    var arrivals: Array=journey.arrivals() if definition.confirm_entry else []
    if not arrivals.is_empty():status="Enter: "+", ".join(arrivals.map(func(row: Dictionary) -> String:return row.name))
    draw_string(font, Vector2(12, 396), (status + " / " if not status.is_empty() else "") + map_hints()[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, muted)
    if not arrival_choices.is_empty():
        draw_rect(Rect2(100,108,440,82+arrival_choices.size()*28),ink)
        draw_rect(Rect2(100,108,440,82+arrival_choices.size()*28),gold,false,2)
        draw_string(font,Vector2(120,135),"ENTER LOCATION",HORIZONTAL_ALIGNMENT_LEFT,-1,18,gold)
        for i in range(arrival_choices.size()):draw_string(font,Vector2(120,165+i*28),"%s%d  %s" % ["> " if i==arrival_selected else "",i+1,arrival_choices[i].name],HORIZONTAL_ALIGNMENT_LEFT,-1,15,gold if i==arrival_selected else Color.WHITE)
        draw_string(font,Vector2(120,177+arrival_choices.size()*28),"Number or click / Esc cancels",HORIZONTAL_ALIGNMENT_LEFT,-1,13,muted)
    if journey.attack_notice:
        draw_rect(Rect2(55,108,530,162),Color("111a19"))
        draw_rect(Rect2(55,108,530,162),gold,false,2)
        draw_string(font,Vector2(78,140),"A BLACK KNIGHT ATTACKS!",HORIZONTAL_ALIGNMENT_LEFT,-1,22,gold)
        draw_string(font,Vector2(78,176),"You can use a Scroll of Protection to avoid battle.",HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color.WHITE)
        draw_string(font,Vector2(78,210),"Choose it in your inventory, or leave the pack to fight.",HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color.WHITE)
        draw_string(font,Vector2(78,246),"Press a key or click to open your inventory.",HORIZONTAL_ALIGNMENT_LEFT,-1,14,gold)
    if journey.party!=null and journey.party.awaiting:
        draw_rect(Rect2(70,110,500,168),Color("101820"))
        draw_rect(Rect2(70,110,500,168),gold,false,2)
        draw_string(font,Vector2(100,145),journey.identity.name+"'S TURN",HORIZONTAL_ALIGNMENT_LEFT,-1,25,gold)
        var port: int=journey.party.players[journey.party.active].input
        var label: String="Shared keyboard" if port==0 else "Controller "+str(port)+" / keyboard fallback"
        draw_string(font,Vector2(100,184),label,HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color.WHITE)
        draw_string(font,Vector2(100,216),"Round %d - each knight keeps their own kit"%journey.day,HORIZONTAL_ALIGNMENT_LEFT,-1,15,muted)
        draw_string(font,Vector2(100,251),"Enter / confirm / click: begin    R: menu",HORIZONTAL_ALIGNMENT_LEFT,-1,15,gold)
    if journey.turn_pending:
        draw_rect(Rect2(100,116,440,168),Color("111a19"))
        draw_rect(Rect2(100,116,440,168),gold,false,2)
        var reason: String={"rest":"You ended your turn.","travel":"Your travel allowance is used up.","town":"Your visit ends the turn.","stonehenge":"Your Stonehenge visit ends the turn."}[journey.turn_reason]
        draw_string(font,Vector2(122,146),reason,HORIZONTAL_ALIGNMENT_LEFT,-1,18,gold)
        draw_string(font,Vector2(122,177),"Round %d / Moon phase %d of 8" % [journey.day,journey.calendar().moon_phase+1],HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color.WHITE)
        draw_string(font,Vector2(122,205),"Travel renewed. Health recovered where needed.",HORIZONTAL_ALIGNMENT_LEFT,-1,14,muted)
        draw_string(font,Vector2(122,254),"Enter, Space or click to continue.",HORIZONTAL_ALIGNMENT_LEFT,-1,16,gold)

func map_hints() -> PackedStringArray:
    var controls: String="Arrows travel / Enter, Z or click: enter / I pack / E end turn" if definition.confirm_entry else "Arrows travel / Walk into lairs or towns / I inventory / E end turn"
    var pad: Node=get_node_or_null("/root/MoonstoneInput")
    var menu: String="R menu / Esc exit"
    if pad!=null and pad.using_controller:
        controls="Stick / D-pad travel / "+pad.binding_name("accept")+" enter / "+pad.binding_name("inventory")+" pack / "+pad.binding_name("end_turn")+" end turn"
        menu="Start menu / Options: controller setup"
    return PackedStringArray([controls+(" / Tab solo/co-op" if debug_mode else ""),menu+(" / DEBUG: P practice / F1,F2,F4-F6 fights / F3 map / not saved" if debug_mode else "")])

func show_inventory(page: int = 0) -> void:
    if quest_view!=null or henge_view!=null or arena != null or inventory_view != null or menu_view != null or journey.turn_pending: return
    inventory_view = InventoryView.new()
    inventory_view.journey = journey
    inventory_attack_context = not journey.pending_attack.is_empty()
    inventory_view.set_tab(page)
    if inventory_attack_context:
        var protection_index: int=inventory_view.rows().find("scroll_of_protection")
        if protection_index>=0: inventory_view.selected=protection_index
    inventory_view.finished.connect(close_inventory)
    add_child(inventory_view)
    queue_redraw()

func close_inventory() -> void:
    if inventory_view == null: return
    remove_child(inventory_view)
    inventory_view.queue_free()
    inventory_view = null
    if inventory_attack_context:
        inventory_attack_context = false
        if not journey.pending_attack.is_empty():
            journey.resolve_pending_attack(false)
            show_lair()
        journey.persist()
        queue_redraw()
        return
    if journey.town_id in ["home","wizard"]:
        journey.leave_town()
        release_movement=true
    journey.service = ""
    journey.places.visit={}
    var town_audio: Node=get_node_or_null("/root/MoonstoneAudio")
    if town_audio!=null:town_audio.stop_scope("town:",false)
    journey.persist()
    if town_view != null:
        if journey.town_id.is_empty():
            remove_child(town_view)
            town_view.queue_free()
            town_view = null
        else:
            town_view.set_process_unhandled_key_input(true)
            town_view.set_process_unhandled_input(true)
            town_view.show()
            town_view.queue_redraw()
    queue_redraw()

func show_practice() -> void:
    if not debug_mode:return
    if quest_view!=null or henge_view!=null or arena!=null or inventory_view!=null or town_view!=null or menu_view!=null or not journey.pending_attack.is_empty(): return
    practice_view=preload("res://scripts/presentation/practice_menu.gd").new()
    practice_view.chosen.connect(func(choice: StringName) -> void:
        remove_child(practice_view)
        practice_view.queue_free()
        practice_view=null
        if choice!=&"": show_training(choice)
    )
    add_child(practice_view)

func advance_equipment_demo() -> void:
    _debug().advance_equipment_demo()

func show_town() -> void:
    if town_view != null or journey.town_id.is_empty(): return
    if journey.town_id=="wizard" and journey.places.visit.get("phase")!="sheet":
        inventory_view=preload("res://scripts/presentation/wizard_view.gd").new()
        inventory_view.journey=journey
        inventory_view.finished.connect(func() -> void:
            remove_child(inventory_view);inventory_view.queue_free();inventory_view=null
            show_inventory(2)
        )
        add_child(inventory_view);return
    if journey.town_id in ["home","wizard"]:
        show_inventory(0 if journey.service.is_empty() else 2)
        return
    town_view = TownView.new()
    town_view.journey = journey
    town_view.service_requested.connect(open_town_service)
    town_view.finished.connect(leave_town)
    add_child(town_view)
    if not journey.service.is_empty():open_town_service(journey.service)
    queue_redraw()

func open_town_service(id: String) -> void:
    if inventory_view != null or town_view==null or journey.town_id.is_empty(): return
    if id!="pack" and id not in town_view.rows(): return
    if id!="pack" and not journey.open_service(id):return
    town_view.set_process_unhandled_key_input(false)
    town_view.set_process_unhandled_input(false)
    town_view.hide()
    if id=="temple" and journey.town_id=="highwood":
        inventory_view=preload("res://scripts/presentation/town_market_view.gd").new()
        inventory_view.journey=journey;inventory_view.finished.connect(close_inventory)
        add_child(inventory_view)
    else:show_inventory({"pack": 0, "smith": 1, "temple": 2, "healer": 3, "tavern": 4, "mystic": 5}[id])

func leave_town() -> void:
    if inventory_view != null or town_view == null: return
    if not journey.leave_town(): return
    remove_child(town_view)
    town_view.queue_free()
    town_view = null
    queue_redraw()

func show_menu(saved: Dictionary, start_music: bool=true) -> void:
    if menu_view != null: return
    menu_view = JourneyMenu.new()
    menu_view.debug_mode=debug_mode
    menu_view.start_music=start_music
    menu_view.saved = saved
    var campaign: Dictionary=saved.get("campaign",saved)
    menu_view.revisit_battles=bool(campaign.get("options",{}).get("revisit_battles",false)) if not saved.is_empty() else journey.revisit_battles
    menu_view.notice = save_store.message if save_store != null else ""
    if menu_view.notice=="Journey ready to continue.":menu_view.notice=""
    menu_view.chosen.connect(menu_choice)
    menu_view.options_changed.connect(journey_options_changed)
    add_child(menu_view)
    queue_redraw()

func show_intro() -> void:
    if intro_view!=null or menu_view==null:return
    var audio: Node=get_node_or_null("/root/MoonstoneAudio")
    if audio!=null:audio.stop_music()
    menu_view.hide()
    menu_view.set_process_unhandled_input(false);menu_view.set_process_unhandled_key_input(false)
    intro_view=IntroView.new()
    intro_view.finished.connect(close_intro)
    add_child(intro_view)
    update_dragon_sprite()

func show_selection() -> void:
    if selection_view!=null or menu_view==null or intro_view!=null:return
    menu_view.hide()
    menu_view.set_process_unhandled_input(false);menu_view.set_process_unhandled_key_input(false)
    selection_view=KnightSelection.new()
    selection_view.confirmed.connect(start_selected)
    selection_view.cancelled.connect(cancel_selection)
    selection_view.local_requested.connect(show_local_setup)
    add_child(selection_view)

func show_local_setup() -> void:
    if selection_view==null or local_setup!=null:return
    selection_view.hide();selection_view.set_process_unhandled_key_input(false);selection_view.set_process_unhandled_input(false)
    local_setup=preload("res://scripts/presentation/local_game_setup.gd").new()
    local_setup.cancelled.connect(close_local_setup)
    local_setup.confirmed.connect(start_local_players)
    add_child(local_setup)

func close_local_setup() -> void:
    if local_setup==null:return
    local_setup.set_process_unhandled_key_input(false);local_setup.set_process_unhandled_input(false)
    remove_child(local_setup);local_setup.queue_free();local_setup=null
    selection_view.show();selection_view.set_process_unhandled_key_input(true);selection_view.set_process_unhandled_input(true)
    get_node("/root/MoonstoneInput").block_held();queue_redraw()

func start_local_players(players: Array) -> void:
    if local_setup==null:return
    journey.store=save_store
    if not journey.start_local_party(players,fresh_seed(),menu_view.revisit_battles):local_setup.notice="Could not start this game.";local_setup.queue_redraw();return
    close_local_setup();cancel_selection()
    remove_child(menu_view);menu_view.queue_free();menu_view=null
    var audio: Node=get_node_or_null("/root/MoonstoneAudio")
    if audio!=null:audio.stop_music()
    release_movement=true;get_node("/root/MoonstoneInput").block_held();queue_redraw()

func cancel_selection() -> void:
    if selection_view==null:return
    remove_child(selection_view);selection_view.queue_free();selection_view=null
    menu_view.show()
    menu_view.set_process_unhandled_input(true);menu_view.set_process_unhandled_key_input(true)
    release_movement=true
    queue_redraw()

func start_selected(identity: Dictionary) -> void:
    if selection_view==null or not Journey.Identity.valid(identity):return
    var revisit: bool=menu_view.revisit_battles
    journey.store=save_store
    if not journey.restart(fresh_seed(),revisit,identity):return
    KnightArt.colour_cache.clear()
    cancel_selection()
    remove_child(menu_view);menu_view.queue_free();menu_view=null
    var audio: Node=get_node_or_null("/root/MoonstoneAudio")
    if audio!=null:audio.stop_music()
    release_movement=true
    queue_redraw()

func close_intro() -> void:
    if intro_view==null:return
    remove_child(intro_view);intro_view.queue_free();intro_view=null
    intro_finishes+=1
    menu_view.show()
    menu_view.set_process_unhandled_input(true);menu_view.set_process_unhandled_key_input(true)
    var audio: Node=get_node_or_null("/root/MoonstoneAudio")
    if audio!=null:audio.menu_music()
    release_movement=true
    queue_redraw()

func advance_intro_demo() -> void:
    _debug().advance_intro_demo()

func journey_options_changed(value: bool) -> void:
    if menu_view==null or menu_view.saved.is_empty():return
    var previous: bool=bool(menu_view.saved.get("campaign",menu_view.saved).get("options",{}).get("revisit_battles",false))
    var updated: Dictionary=journey.validate_checkpoint(menu_view.saved)
    if updated.is_empty():
        menu_view.revisit_battles=previous
        menu_view.notice="Could not read this journey's options."
        menu_view.queue_redraw()
        return
    if updated.get("schema")==17:updated.campaign.options.revisit_battles=value
    else:updated.options.revisit_battles=value
    var valid: Dictionary=journey.validate_checkpoint(updated)
    if valid.is_empty() or (save_store!=null and not save_store.save_checkpoint(valid)):
        menu_view.revisit_battles=previous
        menu_view.notice="Could not save this option. Your journey is unchanged."
    else:
        menu_view.saved=valid
        menu_view.notice=""
    menu_view.queue_redraw()

func menu_choice(action: String) -> void:
    if selection_view!=null:return
    if action=="intro":show_intro();return
    if action=="new":show_selection();return
    if action == "exit":
        get_tree().quit()
        return
    var restored: bool = false
    if action == "continue":
        restored = journey.restore_checkpoint(menu_view.saved)
        if not restored:
            menu_view.notice = "Save is not compatible with this journey."
            menu_view.queue_redraw()
            return
    else: return
    var audio: Node=get_node_or_null("/root/MoonstoneAudio")
    if audio!=null:audio.stop_music()
    journey.store = save_store
    remove_child(menu_view)
    menu_view.queue_free()
    menu_view = null
    if not journey.pending_attack.is_empty() and not journey.attack_notice:
        show_inventory()
    if restored and journey.loot_open:
        show_lair()
        show_loot()
    elif journey.quest.notice or not journey.quest.ending.is_empty():show_quest()
    elif not journey.henge.is_empty():show_henge()
    elif not journey.town_id.is_empty():
        show_town()
        if not journey.service.is_empty(): open_town_service(journey.service)
    journey.persist()
    queue_redraw()

func quit_game() -> void:
    if menu_view == null and journey != null: journey.persist()
    get_tree().quit()

func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_CLOSE_REQUEST: quit_game()

func show_henge() -> void:
    if henge_view!=null or journey.henge.is_empty():return
    henge_view=HengeView.new()
    henge_view.journey=journey
    henge_view.finished.connect(close_henge)
    add_child(henge_view)
    update_dragon_sprite()

func close_henge() -> void:
    if henge_view==null:return
    remove_child(henge_view)
    henge_view.queue_free()
    henge_view=null
    release_movement=true
    queue_redraw()

func show_quest() -> void:
    if quest_view!=null or (not journey.quest.notice and journey.quest.ending.is_empty()):return
    quest_view=QuestView.new()
    quest_view.journey=journey
    quest_view.chosen.connect(close_quest)
    add_child(quest_view)
    update_dragon_sprite()

func close_quest(action: String) -> void:
    if quest_view==null:return
    remove_child(quest_view);quest_view.queue_free();quest_view=null
    if action=="reward" and journey.combat!=null:return_to_map(false)
    elif action=="menu":
        journey.persist()
        show_menu(journey.checkpoint())
    release_movement=true
    queue_redraw()

func setup_quest_demo() -> void:
    _debug().setup_quest_demo()

func setup_ending_demo() -> void:
    _debug().setup_ending_demo()

func advance_ending_demo() -> void:
    _debug().advance_ending_demo()

func demo_walk_henge() -> void:
    _debug().demo_walk_henge()

func advance_quest_demo() -> void:
    _debug().advance_quest_demo()

func advance_henge_demo() -> void:
    _debug().advance_henge_demo()

func demo_enter(index: int) -> void:
    _debug().demo_enter(index)

func demo_win() -> void:
    _debug().demo_win()

func advance_campaign_demo() -> void:
    _debug().advance_campaign_demo()
