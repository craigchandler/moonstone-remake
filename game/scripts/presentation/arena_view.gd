extends Node2D
const Runtime=preload("res://scripts/session/runtime_mode.gd")
var debug_mode: bool=Runtime.debug_enabled()
var diagnostics: RefCounted
const KnightArt=preload("res://assets/classic/knight_selection/art.tres")
var knight_kind: int=0
var knight_name: String="SIR KNIGHT"
var local_players: Dictionary={}
var actor_colours: Dictionary={}
var duel_ready: bool=false

signal return_to_map_requested

const Session = preload("res://scripts/session/local_session.gd")
const Animator = preload("res://scripts/presentation/actor_animator.gd")
var rule_set: Resource = preload("res://content/foundation_rules.tres")
var art: Resource = preload("res://content/classic_art.tres")
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
    elif not managed_by_world:
        restart()
    else:
        animator.reset()
        animator.update(session.simulation.actors, rule_set, art)

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
    session.start(mode, encounter)
    animator.reset()
    demo_ticks = 0
    dodge_destination = 166
    if diagnostics != null or demo or pack_showcase or accuracy_demo:
        _debug().configure_fight()
    else:
        animator.update(session.simulation.actors, rule_set, art)

func _physics_process(_delta: float) -> void:
    if duel_ready:return
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
    draw_texture_rect(background_override if background_override!=null else art.background_for(encounter), Rect2(0, 0, 640, 400), false)
    var perch: Dictionary = session.simulation.rat_perch
    if not perch.is_empty():
        var tree: Resource = art.animation_for("ratman")
        var leaf: Dictionary = tree.sample("tree_anchor",0)
        var variant: String = "purple" if gore_enabled else "purple_clean"
        draw_texture_rect_region(KnightArt.coloured(tree.atlas_for(variant),knight_kind),Rect2((Vector2(perch.x,perch.y+perch.height)+leaf.offset)*2,leaf.region.size*2),leaf.region)
    var ordered: Array = session.simulation.actors.values()
    ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.y < b.y)
    for actor in ordered:
        if actor.kind == "dragon": draw_dragon_feet(actor)
        if actor.kind == "guardian" and actor.health>0:
            var body_art: Resource = art.animation_for("guardian_finishes")
            var body_pose: Dictionary = body_art.sample("body",session.simulation.tick%24,24)
            draw_set_transform(Vector2(actor.x,actor.y+actor.height)*2,0.0,Vector2(actor.facing,1))
            draw_texture_rect_region(KnightArt.coloured(body_art.atlas_for("purple" if gore_enabled else "purple_clean"),knight_kind),Rect2(body_pose.offset*2,body_pose.region.size*2),body_pose.region)
            draw_set_transform(Vector2.ZERO)
    for actor in ordered:
        if actor.get("hidden_by", 0) != 0 or actor.get("vanished",false): continue
        var ground := Vector2(actor.x, actor.y) * 2.0
        var point := ground + Vector2(0, actor.height * 2.0)
        var size: Vector2 = art.size_for(actor.kind) * 2.0
        var texture: Texture2D = art.texture_for(actor.kind)
        draw_ellipse_shadow(ground, 38.0 if actor.kind == "balok" else 21.0)
        var pose: Dictionary = animator.poses.get(actor.id, {})
        if actor.health > 0 or not pose.is_empty():
            draw_set_transform(point, 0.0, Vector2(float(actor.facing), 1.0))
            var tint := Color(1.6, 1.2, 1.2) if actor.flash > 0 else Color.WHITE
            var visual: String = actor.get("visual_kind", "")
            var animations: Resource = art.animation_for(actor.kind if visual.is_empty() else visual)
            if not pose.is_empty():
                var variant: String = "blue" if actor.team == 1 or actor.id in actor_colours else "purple"
                if not gore_enabled: variant += "_clean"
                var atlas: Texture2D = KnightArt.coloured(animations.atlas_for(variant),actor_colours.get(actor.id,4 if actor.team==2 and visual=="death_knight" else knight_kind))
                draw_texture_rect_region(atlas, Rect2(pose.offset * 2, pose.region.size * 2), pose.region, tint)
            else:
                draw_texture_rect(texture, Rect2(-size.x / 2, -size.y, size.x, size.y), false, tint)
            if actor.guarding and pose.is_empty():
                draw_arc(Vector2(15, -48), 28, -PI / 2, PI / 2, 16, Color(0.5, 0.8, 1.0), 2.0)
            draw_set_transform(Vector2.ZERO)
        else:
            draw_line(point + Vector2(-20, 0), point + Vector2(20, 0), Color(0.7, 0.25, 0.2), 3)
        var hold_hint: String=""
        if actor.grab_remaining>0: hold_hint="HELD: guard + down"
        if actor.get("held_target",0)!=0:
            hold_hint="HELD: Space + Down to counter" if actor.kind in ["ratman","mudman"] else "CAUGHT"
        if actor.health>0 and not hold_hint.is_empty():
            var pad: Node=get_node("/root/MoonstoneInput")
            if pad.using_controller and "HELD:" in hold_hint:hold_hint="HELD: "+pad.binding_name("block")+" + Down"
            draw_string(font, point + Vector2(-20, 15), hold_hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.55, 0.78, 0.9) if actor.team == 1 else Color(0.9, 0.46, 0.38))
    draw_hit_effects()
    for projectile in session.simulation.projectiles:
        if projectile.get("kind", "dagger")=="dragon_fire":
            var animations: Resource = art.animation_for("dragon")
            var pose: Dictionary = animations.sample("ground_fire", projectile.age, 144)
            var atlas: Texture2D = KnightArt.coloured(animations.atlas_for("purple" if gore_enabled else "purple_clean"),knight_kind)
            draw_texture_rect_region(atlas, Rect2((Vector2(projectile.x,projectile.y)+pose.offset)*2,pose.region.size*2),pose.region)
            continue
        var texture: Texture2D = art.projectiles.get("dagger")
        if texture == null: continue
        draw_set_transform(Vector2(projectile.x, projectile.y + projectile.height) * 2,
            0.0, Vector2(float(projectile.facing), 1.0))
        draw_texture_rect(texture, Rect2(-texture.get_size(), texture.get_size() * 2), false)
        draw_set_transform(Vector2.ZERO)
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

func result_hint(outcome: String) -> String:
    return ("Enter: collect loot" if outcome=="victory" else "Enter: return to map")+("    R: retry this fight" if debug_mode else "")

func navigation_hint() -> String:
    var controls: Node=get_node_or_null("/root/MoonstoneInput")
    if controls!=null and controls.using_controller:
        return ("DEBUG / NOT SAVED  " if debug_mode else "")+"Start pause / controller setup  "+controls.binding_name("retreat")+" retreat  G gore: "
    if not debug_mode:return "Enter: result / loot  Esc retreat  G gore: " if managed_by_world else "Esc exit  G gore: "
    return "DEBUG / NOT SAVED  R retry  F3 map  Esc retreat  G gore: " if managed_by_world else "DEBUG  F1 duel  F2 spear  F4 axe  F5 troll  F6 Balok  F3 map  Tab co-op  R restart  G gore: "

func draw_hit_effects() -> void:
    if not gore_enabled: return
    for effect in hit_effects.active:
        var animation: Resource = art.effects.get(effect.kind)
        if animation == null: continue
        var pose: Dictionary = animation.sample("burst",session.simulation.tick-effect.born,effect.duration)
        draw_set_transform(Vector2(effect.x,effect.y)*2,0.0,Vector2(effect.facing,1))
        draw_texture_rect_region(animation.atlas_for("gore"),Rect2(pose.offset*2,pose.region.size*2),pose.region)
        draw_set_transform(Vector2.ZERO)

func draw_dragon_feet(actor: Dictionary) -> void:
    var animations: Resource = art.animation_for("dragon")
    var clip: String = "feet_down" if actor.health <= 0 else "feet_idle"
    var pose: Dictionary = animations.sample(clip, 0)
    if actor.action == "dragon_foot" and actor.remaining > 0:
        var move: Dictionary = rule_set.moves.dragon_foot
        var duration: int = move.windup+move.active+move.recovery
        pose = animations.sample("dragon_foot", duration-actor.remaining, duration)
    var atlas: Texture2D = KnightArt.coloured(animations.atlas_for("purple" if gore_enabled else "purple_clean"),knight_kind)
    for depth in [-20,10]:
        draw_texture_rect_region(atlas, Rect2((Vector2(5,actor.y+depth)+pose.offset)*2,pose.region.size*2),pose.region)

func draw_ellipse_shadow(point: Vector2, radius: float = 21.0) -> void:
    draw_set_transform(point, 0.0, Vector2(1.0, 0.28))
    draw_circle(Vector2.ZERO, radius, Color(0.0, 0.0, 0.0, 0.35))
    draw_set_transform(Vector2.ZERO)
