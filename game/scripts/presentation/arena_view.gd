extends Node2D
const Runtime=preload("res://scripts/session/runtime_mode.gd")
var debug_mode: bool=Runtime.debug_enabled()
var diagnostics: RefCounted
const KnightArt=preload("res://assets/classic/knight_selection/art.tres")
var knight_kind: int=0
var knight_name: String="SIR KNIGHT"
var local_players: Dictionary={}
var actor_colours: Dictionary={}
var actor_equipment: Dictionary={}
var graphics_frame: RefCounted=preload("res://scripts/presentation/graphics/combat_frame.gd").new()
# A backend can be supplied by a future art pack without changing the session.
var renderer: RefCounted
var duel_ready: bool=false
var practice_mode: bool = false
var network_duel: RefCounted
var network_round: int = 0
var network_tick: int = 0
var practice_overlay: Node2D
var restart_overrides: Dictionary = {}

signal return_to_map_requested

const Session = preload("res://scripts/session/local_session.gd")
const Animator = preload("res://scripts/presentation/actor_animator.gd")
var rule_set: Resource = preload("res://content/foundation_rules.tres")
var art: Resource = preload("res://content/generated/classic_layered_art.tres")
var session: RefCounted
var mode: StringName = &"competitive"
var font: Font = ThemeDB.fallback_font
var capture_path: String = ""
var smoke: bool = false
var animator: RefCounted = Animator.new()
var hit_effects: RefCounted = preload("res://scripts/presentation/combat_hit_effects.gd").new()
var demo: bool = false
var sequence_path: String = ""
var capture_stride: int = 1
var demo_ticks: int = 0
var combat_demo: bool = false
var trogg_demo: bool = false
var axe_demo: bool = false
var troll_demo: bool = false
var balok_demo: bool = false
var defence_demo: bool = false
var dodge_destination: int = 166
var encounter: StringName = &"spear_lair"
var mirror_demo: bool = false
var gore_enabled: bool = true
var settings := ConfigFile.new()
var managed_by_world: bool = false
var background_override: Texture2D
var pack_showcase: bool = false
var accuracy_demo: bool = false
var accuracy_fixture: RefCounted
var finish_demo: String = ""
var sound_cues: RefCounted = preload("res://scripts/presentation/combat_sound_cues.gd").new()

func sound_owner(id: int) -> String:
    return "%d:%d" % [get_instance_id(),id]

func advance_sound() -> void:
    var audio: Node = get_node_or_null("/root/MoonstoneAudio")
    if audio == null: return
    var batch: Dictionary = sound_cues.collect(session.simulation,animator.poses,art,audio.Pack)
    for id in batch.changed: audio.stop_owner(sound_owner(id))
    for cue in batch.cues: audio.play_cue(cue.key,sound_owner(cue.actor),session.simulation.tick)

func _exit_tree() -> void:
    var audio: Node = get_node_or_null("/root/MoonstoneAudio")
    if audio != null:
        audio.stop_scope(str(get_instance_id())+":")

func _ready() -> void:
    add_to_group("moonstone_input_surfaces")
    if debug_mode or demo or pack_showcase or accuracy_demo:
        _debug().start()
        return
    if settings.load("user://preferences.cfg") == OK:
        gore_enabled = bool(settings.get_value("visual", "gore", true))
    for argument in ([] if managed_by_world else Runtime.user_arguments(false)):
        if argument == "--no-gore": gore_enabled = false
        elif argument == "--smoke": smoke = true
    Engine.physics_ticks_per_second = rule_set.tick_rate
    if session == null:
        session = Session.new(rule_set)
        restart()
    elif not managed_by_world and not practice_mode:
        restart()
    else:
        animator.reset()
        animator.update(session.simulation.actors, rule_set, art)
    if practice_mode:
        practice_overlay = (preload("res://scripts/presentation/practice_overlay.gd") if network_duel==null else preload("res://scripts/presentation/network_duel_overlay.gd")).new()
        practice_overlay.arena = self
        add_child(practice_overlay)
        if network_duel!=null:
            process_mode=Node.PROCESS_MODE_ALWAYS
            network_round=network_duel.session.round_id
            actor_colours={1:network_duel.colours[0],2:network_duel.colours[1]}
            network_duel.frame_received.connect(network_frame)
            network_duel.changed.connect(practice_overlay.queue_redraw)

func _debug() -> RefCounted:
    if diagnostics == null:
        diagnostics = load("res://debug/arena_diagnostics.gd").new(self)
    return diagnostics

func restart() -> void:
    var audio: Node = get_node_or_null("/root/MoonstoneAudio")
    if audio != null:
        audio.stop_scope(str(get_instance_id())+":",false)
    sound_cues.reset()
    hit_effects.reset()
    session.start(mode, encounter, restart_overrides)
    animator.reset()
    demo_ticks = 0
    dodge_destination = 166
    if diagnostics != null or demo or pack_showcase or accuracy_demo:
        _debug().configure_fight()
    else:
        animator.update(session.simulation.actors, rule_set, art)

func network_frame() -> void:
    if network_round!=network_duel.session.round_id:
        network_round=network_duel.session.round_id;network_tick=0
        get_node("/root/MoonstoneInput").block_held()
        animator.reset();hit_effects.reset();sound_cues.reset()
        var audio: Node=get_node_or_null("/root/MoonstoneAudio")
        if audio!=null:audio.stop_scope(str(get_instance_id())+":",false)
    animator.update(session.simulation.actors,rule_set,art,maxi(1,session.simulation.tick-network_tick))
    network_tick=session.simulation.tick
    hit_effects.update(session.simulation,art);advance_sound()
    queue_redraw();practice_overlay.queue_redraw()

func _physics_process(_delta: float) -> void:
    if network_duel!=null:
        var input: Node=get_node("/root/MoonstoneInput")
        var held: bool=practice_overlay.help_visible or get_tree().paused
        network_duel.advance(Vector2i.ZERO if held else input.direction(),"idle" if held else input.combat_action())
        return
    if duel_ready:return
    if practice_mode and (practice_finished() or practice_overlay.help_visible): return
    var controls: Node=get_node("/root/MoonstoneInput")
    var direction: Vector2i=controls.direction()
    var action: String=controls.combat_action()
    if accuracy_demo:
        accuracy_fixture.advance(session)
        demo_ticks=accuracy_fixture.tick
    elif pack_showcase:
        advance_pack_showcase()
    elif demo:
        advance_demo()
    else:
        var additional: Dictionary={}
        for id in local_players:
            if id!=1:additional[id]={"direction":controls.direction_for(local_players[id],true),"action":controls.action_for(local_players[id],true)}
        session.advance(direction, action,additional)
    animator.update(session.simulation.actors, rule_set, art)
    hit_effects.update(session.simulation, art)
    queue_redraw()
    if practice_overlay != null: practice_overlay.queue_redraw()
    advance_sound()
    if accuracy_demo and sequence_path.is_empty() and demo_ticks>=demo_length():
        finish_accuracy_demo()
    if smoke and session.simulation.tick >= 40:
        print("PASS: native encounter boots without disk files; mode=", mode, "; encounter=", encounter)
        get_tree().quit()
    if not capture_path.is_empty() and session.simulation.tick == 30:
        capture_and_quit.call_deferred()
    if not sequence_path.is_empty():
        set_physics_process(false)
        capture_sequence_frame.call_deferred()

func advance_demo() -> void:
    _debug().advance_demo()

func advance_combat_demo() -> void:
    _debug().advance_combat_demo()

func advance_defence_demo() -> void:
    _debug().advance_defence_demo()

func advance_trogg_demo() -> void:
    _debug().advance_trogg_demo()

func advance_axe_demo() -> void:
    _debug().advance_axe_demo()

func advance_troll_demo() -> void:
    _debug().advance_troll_demo()

func advance_balok_demo() -> void:
    _debug().advance_balok_demo()

func demo_length() -> int:
    return _debug().demo_length()

func capture_sequence_frame() -> void:
    _debug().capture_sequence_frame()

func finish_accuracy_demo() -> void:
    _debug().finish_accuracy_demo()

func advance_pack_showcase() -> void:
    _debug().advance_pack_showcase()

func capture_and_quit() -> void:
    _debug().capture_and_quit()

func _unhandled_key_input(event: InputEvent) -> void:
    if accuracy_demo or pack_showcase:
        # Recorded fixtures consume only their scripted commands. A desktop
        # key arriving while capture has focus must not reset the live session.
        get_viewport().set_input_as_handled()
        return
    if not event is InputEventKey or not event.pressed or event.echo:
        return
    if network_duel!=null:
        get_viewport().set_input_as_handled()
        if event.keycode==KEY_F1:practice_overlay.help_visible=not practice_overlay.help_visible
        elif practice_overlay.help_visible:practice_overlay.help_visible=false
        elif event.keycode==KEY_ESCAPE or (network_duel.state=="closed" and event.keycode in [KEY_ENTER,KEY_KP_ENTER,KEY_SPACE]):return_to_map_requested.emit();return
        elif event.keycode in [KEY_ENTER,KEY_KP_ENTER,KEY_SPACE,KEY_R,KEY_Z] and network_duel.session.settled:network_duel.ready()
        practice_overlay.queue_redraw()
        if event.keycode!=KEY_G:return
    if practice_mode and network_duel==null:
        get_viewport().set_input_as_handled()
        if event.keycode == KEY_F1: practice_overlay.help_visible = not practice_overlay.help_visible
        elif practice_overlay.help_visible: practice_overlay.help_visible = false
        elif event.keycode == KEY_ESCAPE: return_to_map_requested.emit(); return
        elif event.keycode == KEY_R or (event.keycode in [KEY_ENTER,KEY_KP_ENTER,KEY_SPACE,KEY_Z] and practice_finished()): restart()
        practice_overlay.queue_redraw()
        if event.keycode != KEY_G: return
    if managed_by_world:
        get_viewport().set_input_as_handled()
    if not debug_mode and event.keycode in Runtime.ARENA_SHORTCUTS:return
    if duel_ready and event.keycode in [KEY_ENTER,KEY_KP_ENTER,KEY_SPACE]:
        duel_ready=false;get_node("/root/MoonstoneInput").block_held();queue_redraw();return
    if event.keycode == KEY_ESCAPE or (not local_players.is_empty() and event.keycode==KEY_KP_SUBTRACT):
        if managed_by_world: return_to_map_requested.emit()
        else: get_tree().quit()
    elif managed_by_world and event.keycode == KEY_ENTER:
        if session.simulation.outcome() != "ongoing": return_to_map_requested.emit()
    elif event.keycode == KEY_R:
        restart()
    elif event.keycode == KEY_G:
        gore_enabled = not gore_enabled
        settings.load("user://preferences.cfg")
        settings.set_value("visual", "gore", gore_enabled)
        if not debug_mode and not Runtime.debug_enabled() and settings.save("user://preferences.cfg") != OK:
            push_warning("Gore preference could not be saved")
        queue_redraw()
    elif event.keycode == KEY_TAB:
        if managed_by_world: return
        mode = &"cooperative" if mode == &"competitive" else &"competitive"
        restart()
    elif event.keycode in [KEY_F1, KEY_F2, KEY_F4, KEY_F5, KEY_F6]:
        if managed_by_world: return
        encounter = {KEY_F1: &"duel", KEY_F2: &"spear_lair", KEY_F4: &"axe_lair", KEY_F5: &"troll_lair", KEY_F6: &"balok_lair"}[event.keycode]
        restart()

func _draw() -> void:
    if session == null:
        return
    graphics_frame.capture(session.simulation,animator,hit_effects,rule_set,encounter,gore_enabled,knight_kind,actor_colours,actor_equipment)
    if renderer==null:renderer=preload("res://scripts/presentation/graphics/classic_combat_renderer.gd").new(art)
    var input: Node=get_node("/root/MoonstoneInput")
    renderer.render(self,graphics_frame,background_override,input.binding_name("block") if input.using_controller else "")
    if practice_mode: return
    var perch: Dictionary=graphics_frame.perch
    var ordered: Array=session.simulation.actors.values()
    if perch.is_empty(): draw_rect(Rect2(0, 0, 640, 32), Color(0.035, 0.047, 0.067, 0.92))
    else:
        # Leave the source treetop visible at the top of the playfield.
        draw_rect(Rect2(0,0,260,32),Color(0.035,0.047,0.067,0.92))
        draw_rect(Rect2(410,0,230,32),Color(0.035,0.047,0.067,0.92))
    draw_string(font, Vector2(12, 15), "MOONSTONE", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.9, 0.83, 0.59))
    draw_string(font, Vector2(170 if perch.is_empty() else 420, 15), str(rule_set.encounters.get(String(encounter), {}).get("display_name", "Knight duel")) + "  /  " + ("Co-op" if mode == &"cooperative" else "Solo"), HORIZONTAL_ALIGNMENT_LEFT, -1, 16 if perch.is_empty() else 12, Color(0.82, 0.85, 0.87))
    var outcome: String = session.simulation.outcome()
    var enemies: int = session.simulation.spawn_remaining
    for actor in ordered:
        if actor.team == 2 and actor.health > 0: enemies += 1
    var player: Dictionary = session.simulation.actors[1]
    var progress: String = "Health: %d/%d   Daggers: %d   Enemies: %d" % [player.health, player.maximum, player.daggers, enemies]
    var objective: String = "Clear the lair" if encounter != &"duel" else "Defeat the rival" if mode == &"competitive" else "Defeat the enemies"
    objective = str(rule_set.encounters.get(String(encounter), {}).get("objective", objective))
    draw_string(font, Vector2(12, 28), progress + (("   · " + objective if outcome == "ongoing" else "   · " + outcome.capitalize() + (" · Enter: loot" if managed_by_world and outcome == "victory" else (" · Enter: map" if managed_by_world else (" · R to restart" if debug_mode else "")))) if perch.is_empty() else ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.57, 0.66, 0.71))
    if managed_by_world and outcome != "ongoing":
        draw_rect(Rect2(158, 68, 324, 51), Color(0.035, 0.047, 0.067, 0.92))
        draw_string(font, Vector2(180, 90), "LAIR CLEARED" if outcome == "victory" else "THE LAIR REMAINS", HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(0.9, 0.83, 0.59))
        draw_string(font, Vector2(180, 109), result_hint(outcome), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.82, 0.85, 0.87))
    if duel_ready:
        draw_rect(Rect2(50,100,540,164),Color("101820"))
        draw_string(font,Vector2(80,132),"KNIGHT VERSUS KNIGHT",HORIZONTAL_ALIGNMENT_LEFT,-1,23,Color("ddc68c"))
        draw_string(font,Vector2(80,168),"Attacker: normal keys / assigned controller",HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color.WHITE)
        draw_string(font,Vector2(80,196),"Defender: number pad / assigned controller",HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color.WHITE)
        draw_string(font,Vector2(80,236),"Enter / confirm: begin    Esc: retreat",HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("ddc68c"))
    draw_rect(Rect2(0, 361, 640, 39), Color(0.035, 0.047, 0.067, 0.94))
    var controls: Node=get_node("/root/MoonstoneInput")
    var move_hint: String="Arrows move/evade  Z swing  X chop  C lunge  V reverse  A upward  D dagger  Space block"
    if controls.using_controller:
        move_hint="Stick/D-pad move  "+controls.binding_name("swing")+" swing  "+controls.binding_name("heavy")+" chop  "+controls.binding_name("lunge")+" lunge  "+controls.binding_name("reverse")+" reverse  "+controls.binding_name("upward")+" up  "+controls.binding_name("dagger")+" dagger  "+controls.binding_name("block")+" guard"
    draw_string(font, Vector2(12, 377), move_hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.86, 0.86, 0.8))
    var navigation: String = navigation_hint()
    draw_string(font, Vector2(12, 394), navigation + ("ON" if gore_enabled else "OFF"), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.57, 0.66, 0.71))

func practice_finished() -> bool:
    if network_duel!=null:return network_duel.session.settled or network_duel.state=="closed"
    if session == null or session.simulation.outcome() == "ongoing": return false
    for actor in session.simulation.actors.values():
        if actor.health <= 0 and actor.down_remaining > 0: return false
    return true

func result_hint(outcome: String) -> String:
    return ("Enter: collect loot" if outcome=="victory" else "Enter: return to map")+("    R: retry this fight" if debug_mode else "")

func navigation_hint() -> String:
    var controls: Node=get_node_or_null("/root/MoonstoneInput")
    if controls!=null and controls.using_controller:
        return ("DEBUG / NOT SAVED  " if debug_mode else "")+"Start pause / controller setup  "+controls.binding_name("retreat")+" retreat  G gore: "
    if not debug_mode:return "Enter: result / loot  Esc retreat  G gore: " if managed_by_world else "Esc exit  G gore: "
    return "DEBUG / NOT SAVED  R retry  F3 map  Esc retreat  G gore: " if managed_by_world else "DEBUG  F1 duel  F2 spear  F4 axe  F5 troll  F6 Balok  F3 map  Tab co-op  R restart  G gore: "
