extends Node

const Images=preload("res://scripts/presentation/graphics/logical_image.gd")

signal changed
signal cursor_moved
const Profile=preload("res://scripts/session/controller_profile.gd")
const Runtime=preload("res://scripts/session/runtime_mode.gd")
const SeatInputs=preload("res://scripts/presentation/local_seat_inputs.gd")
var seats: RefCounted=SeatInputs.new()
const GROUP: String="moonstone_input_surfaces"
const SYNTHETIC_DEVICE: int=-42
var profile: Dictionary=Profile.defaults()
var settings_path: String="user://controller.json"
var allow_write: bool=true
var notice: String=""
var using_controller: bool=false
var active_device: int=-1
var buttons: Dictionary={}
var axes: Dictionary={}
var blocked: Dictionary={}
var capture_action: String=""
var capture_armed: bool=false
var context_id: String=""
var repeat_direction:=Vector2i.ZERO
var repeat_wait: float=0
var focused: bool=true
var pause_view: Node2D
var pointer:=Vector2(320,200)
var pointer_active: bool=false
var cursor: Node2D

func _ready() -> void:
    process_mode=Node.PROCESS_MODE_ALWAYS
    pointer=get_viewport().get_mouse_position()
    load_preferences()
    Input.joy_connection_changed.connect(connection_changed)
    var layer:=CanvasLayer.new();layer.layer=80;add_child(layer)
    cursor=Node2D.new();layer.add_child(cursor)
    cursor.draw.connect(func() -> void:
        var texture: Texture2D=preload("res://assets/classic/loot/art.tres").sword_cursor
        cursor.draw_texture_rect(texture,Rect2(pointer.round(),Images.size(texture)*2),false))

func load_preferences() -> bool:
    if not FileAccess.file_exists(settings_path):return true
    var file:=FileAccess.open(settings_path,FileAccess.READ)
    var loaded: Dictionary={}
    var parser:=JSON.new()
    if file!=null and file.get_length()<=16384 and parser.parse(file.get_as_text())==OK:loaded=Profile.validate(parser.data)
    if loaded.is_empty():profile=Profile.defaults();notice="Could not read controller settings. Using defaults.";return false
    profile=loaded;return true

func save_preferences() -> bool:
    if not allow_write or Runtime.debug_enabled():notice="Debug mode: changes last for this session.";return true
    var file:=FileAccess.open(settings_path+".tmp",FileAccess.WRITE)
    if file==null:notice="Mapping active this session; settings could not be saved.";return false
    file.store_string(JSON.stringify(profile));file.flush()
    var ok: bool=file.get_error()==OK
    file.close()
    if not ok or Profile.validate(JSON.parse_string(FileAccess.get_file_as_string(settings_path+".tmp")))!=profile or DirAccess.rename_absolute(settings_path+".tmp",settings_path)!=OK:
        notice="Mapping active this session; settings could not be saved.";return false
    notice="Controller settings saved.";return true

func bind_action(action: String,binding: Dictionary) -> bool:
    var updated: Dictionary=Profile.remap(profile,action,binding)
    if updated.is_empty():notice="That control cannot be assigned.";changed.emit();return false
    profile=updated;block_held();save_preferences();changed.emit();return true

func set_deadzone(value: float) -> void:
    profile.deadzone=clampf(snappedf(value,0.05),0.1,0.6)
    block_held();save_preferences();changed.emit()

func reset_defaults() -> void:
    profile=Profile.defaults();block_held();save_preferences();changed.emit()

func binding_name(action: String) -> String:return Profile.label(profile.bindings[action])

func active_surface() -> Node:
    var surfaces: Array=get_tree().get_nodes_in_group(GROUP)
    surfaces.reverse()
    for surface in surfaces:
        if surface is CanvasItem and surface.is_visible_in_tree() and surface.is_processing_unhandled_key_input() and not surface.is_queued_for_deletion():return surface
    return null

func kind(surface: Node) -> String:
    if surface!=null and surface.has_method("input_kind"):return surface.input_kind()
    return "" if surface==null else String(surface.get_script().resource_path).get_file().get_basename()

func refresh_context() -> void:
    var surface: Node=active_surface()
    var id: String=str(surface.get_instance_id()) if surface!=null else ""
    if surface!=null and kind(surface)=="world_view":id+=str(not surface.arrival_choices.is_empty())+str(surface.journey!=null and surface.journey.turn_pending)
    var local: RefCounted=local_journey()
    if local!=null:id+="party"+str(local.party.get_instance_id())+str(local.party.active)+str(local.party.awaiting)
    if id!=context_id:context_id=id;block_held()

func control_down(binding: Dictionary) -> bool:
    var key: String=binding.kind+str(binding.code)
    if blocked.has(key):return false
    return bool(buttons.get(int(binding.code),false)) if binding.kind=="button" else float(axes.get(int(binding.code),0))>0.5

func down(action: String) -> bool:return control_down(profile.bindings[action])

func block_held() -> void:
    seats.block_held(float(profile.deadzone))
    for code in buttons:
        if buttons[code]:blocked["button"+str(code)]=true
    for code in axes:
        if absf(float(axes[code]))>float(profile.deadzone):blocked["trigger"+str(code)]=true
    repeat_direction=Vector2i.ZERO;repeat_wait=0

func clear_input() -> void:
    block_held();buttons.clear();axes.clear();seats.clear();repeat_direction=Vector2i.ZERO

func pad_direction() -> Vector2i:
    var result:=Vector2i.ZERO
    if not blocked.has("trigger"+str(JOY_AXIS_LEFT_X)):
        var x: float=float(axes.get(JOY_AXIS_LEFT_X,0));result.x=int(x>profile.deadzone)-int(x< -profile.deadzone)
    if not blocked.has("trigger"+str(JOY_AXIS_LEFT_Y)):
        var y: float=float(axes.get(JOY_AXIS_LEFT_Y,0));result.y=int(y>profile.deadzone)-int(y< -profile.deadzone)
    result.x=clampi(result.x+int(control_down(Profile.button(JOY_BUTTON_DPAD_RIGHT)))-int(control_down(Profile.button(JOY_BUTTON_DPAD_LEFT))),-1,1)
    result.y=clampi(result.y+int(control_down(Profile.button(JOY_BUTTON_DPAD_DOWN)))-int(control_down(Profile.button(JOY_BUTTON_DPAD_UP))),-1,1)
    return result

func direction() -> Vector2i:
    refresh_context()
    if not focused or get_tree().paused or not capture_action.is_empty():return Vector2i.ZERO
    var local: RefCounted=local_journey()
    if local!=null:return direction_for(local.party.active)
    var keys:=Vector2i(int(Input.is_physical_key_pressed(KEY_RIGHT))-int(Input.is_physical_key_pressed(KEY_LEFT)),int(Input.is_physical_key_pressed(KEY_DOWN))-int(Input.is_physical_key_pressed(KEY_UP)))
    return (keys+pad_direction()).clamp(Vector2i(-1,-1),Vector2i.ONE)

func combat_action() -> String:
    refresh_context()
    if not focused or get_tree().paused or not capture_action.is_empty():return "idle"
    var local: RefCounted=local_journey()
    if local!=null:return action_for(local.party.active)
    var result: String="idle"
    var keys: Dictionary={"swing":KEY_Z,"heavy":KEY_X,"lunge":KEY_C,"reverse":KEY_V,"upward":KEY_A,"dagger":KEY_D,"block":KEY_SPACE}
    for action in keys:
        if Input.is_physical_key_pressed(keys[action]) or down(action):result=action
    return result

func send_key(code: int,shift: bool=false) -> void:
    var event:=InputEventKey.new();event.keycode=code;event.device=SYNTHETIC_DEVICE;event.pressed=true;event.shift_pressed=shift
    get_tree().root.push_input(event,true)
    event=event.duplicate();event.pressed=false;get_tree().root.push_input(event,true)

func begin_capture(action: String) -> void:
    capture_action=action;capture_armed=neutral();notice="Release controls, then press a button or trigger.";changed.emit()

func cancel_capture() -> void:
    capture_action="";notice="Mapping cancelled.";block_held();changed.emit()

func neutral() -> bool:
    for value in buttons.values():
        if value:return false
    for code in [JOY_AXIS_TRIGGER_LEFT,JOY_AXIS_TRIGGER_RIGHT]:
        if float(axes.get(code,0))>0.5:return false
    return true

func select_device(id: int) -> void:
    clear_input();active_device=id;changed.emit()

func device_name() -> String:
    if active_device<0:return "Press a controller button to connect"
    var name: String=Input.get_joy_name(active_device)
    return name if not name.is_empty() else "Gamepad"

func connection_changed(device: int,connected: bool) -> void:
    if not connected:
        seats.disconnected(device)
        if local_journey()!=null:open_pause("Controller disconnected - keyboard fallback available")
    if not connected and device==active_device:
        if not capture_action.is_empty():cancel_capture()
        clear_input();active_device=-1
        var surface: Node=active_surface()
        if kind(surface)=="arena_view":open_pause("Controller disconnected")
    changed.emit()

func open_pause(reason: String="Paused") -> void:
    if pause_view!=null:return
    var surface: Node=active_surface()
    if kind(surface)!="arena_view" or surface.demo or surface.accuracy_demo or surface.pack_showcase:return
    block_held()
    pause_view=load("res://scripts/presentation/controller_pause.gd").new()
    pause_view.reason="DUEL CONTINUES" if surface.network_duel!=null else reason
    get_tree().paused=true;get_tree().root.add_child(pause_view)

func close_pause() -> void:
    if pause_view==null:return
    pause_view.set_process_unhandled_key_input(false);pause_view.set_process_unhandled_input(false);pause_view.hide()
    pause_view.queue_free();pause_view=null;get_tree().paused=false;block_held()

func _notification(what: int) -> void:
    if what==NOTIFICATION_APPLICATION_FOCUS_OUT:
        focused=false
        if not capture_action.is_empty():cancel_capture()
        clear_input()
        if using_controller or local_journey()!=null:open_pause("Game lost focus")
    elif what==NOTIFICATION_APPLICATION_FOCUS_IN:focused=true;block_held()

func _input(event: InputEvent) -> void:
    if event is InputEventMouse:
        pointer=event.position
        if event.device!=SYNTHETIC_DEVICE:using_controller=false;pointer_active=false
        cursor_moved.emit()
    if event is InputEventKey and event.device!=SYNTHETIC_DEVICE and event.pressed:
        using_controller=false
        if not capture_action.is_empty():
            get_viewport().set_input_as_handled()
            if event.keycode==KEY_ESCAPE:cancel_capture()
        return
    if not event is InputEventJoypadButton and not event is InputEventJoypadMotion:return
    get_viewport().set_input_as_handled()
    if not focused:return
    refresh_context()
    var seat_before: Dictionary={}
    for action in ["retreat","accept"]:seat_before[action]=seats.down(event.device,profile.bindings[action])
    seats.ingest(event,float(profile.deadzone))
    var local: RefCounted=local_journey()
    if local!=null:
        var expected: int=seats.device_for(int(local.party.players[local.party.active].input))
        if kind(active_surface()) in ["controller_pause","controller_options"]:
            for row in local.party.players:
                if row.human and seats.device_for(int(row.input))==event.device:expected=event.device
        if event.device!=expected:
            var other: bool=false
            var arena: Node=active_surface()
            if kind(arena)=="arena_view":
                for slot in arena.local_players.values():
                    if seats.device_for(int(local.party.players[slot].input))==event.device:other=true
            if other:
                using_controller=true
                if event is InputEventJoypadButton and event.pressed and event.button_index==JOY_BUTTON_START:open_pause()
                elif seats.down(event.device,profile.bindings.retreat) and not seat_before.retreat:send_key(KEY_ESCAPE)
                elif kind(arena)=="arena_view" and arena.duel_ready and seats.down(event.device,profile.bindings.accept) and not seat_before.accept:send_key(KEY_ENTER)
            return
        if active_device!=expected:
            buttons.clear();axes.clear();blocked.clear();active_device=expected
    var meaningful: bool=event.pressed if event is InputEventJoypadButton else absf(event.axis_value)>0.65
    if active_device<0 and meaningful:select_device(event.device)
    if event.device!=active_device:return
    using_controller=true
    var before: Dictionary={}
    for action in profile.bindings:before[action]=down(action)
    var start_before: bool=control_down(Profile.button(JOY_BUTTON_START))
    if event is InputEventJoypadButton:
        buttons[event.button_index]=event.pressed
        if not event.pressed:blocked.erase("button"+str(event.button_index))
    else:
        axes[event.axis]=event.axis_value
        if absf(event.axis_value)<minf(0.2,float(profile.deadzone)):blocked.erase("trigger"+str(event.axis))
    if not capture_action.is_empty():
        if event is InputEventJoypadButton and event.pressed and event.button_index==JOY_BUTTON_START:cancel_capture();return
        if not capture_armed:
            capture_armed=neutral();return
        var binding: Dictionary={}
        if event is InputEventJoypadButton and event.pressed:binding=Profile.button(event.button_index)
        elif event is InputEventJoypadMotion and event.axis_value>0.65:binding=Profile.trigger(event.axis)
        if Profile.valid_binding(binding):
            var action: String=capture_action;capture_action="";bind_action(action,binding)
        return
    var surface: Node=active_surface()
    var context: String=kind(surface)
    if context=="arena_view" and (surface.demo or surface.accuracy_demo or surface.pack_showcase):return
    if control_down(Profile.button(JOY_BUTTON_START)) and not start_before:
        if context=="arena_view":open_pause()
        elif context=="world_view":send_key(KEY_R)
        elif context=="controller_pause":close_pause()
        elif context=="journey_menu" and not surface.options_open:send_key(KEY_SPACE)
        else:send_key(KEY_ESCAPE)
        return
    if context=="arena_view":
        if ((local!=null and surface.duel_ready) or (surface.practice_mode and surface.practice_finished())) and down("accept") and not before.accept:send_key(KEY_ENTER)
        elif down("retreat") and not before.retreat:send_key(KEY_ESCAPE)
    else:
        for action in Profile.MENUS:
            if not down(action) or before[action]:continue
            if action=="click" and context!="world_view":click_pointer();break
            var key: int=ui_key(context,action)
            if key!=0:send_key(key,down("alternate") and action in ["previous_page","next_page"]);break
    repeat_navigation(0)
    get_viewport().set_input_as_handled()

func ui_key(context: String,action: String) -> int:
    if context=="world_view":return {"accept":KEY_ENTER,"cancel":KEY_R,"inventory":KEY_I,"end_turn":KEY_E}.get(action,0)
    if context in ["knight_selection","local_game_setup"] and action=="accept":return KEY_ENTER
    return {"accept":KEY_SPACE,"cancel":KEY_ESCAPE,"inventory":KEY_I,"help":KEY_F1,"previous_page":KEY_PAGEUP,"next_page":KEY_PAGEDOWN,"previous_tab":KEY_LEFT,"next_tab":KEY_RIGHT}.get(action,0)

func local_journey() -> RefCounted:
    if not is_inside_tree():return null
    for surface in get_tree().get_nodes_in_group(GROUP):
        if kind(surface)=="world_view" and not surface.has_method("is_network_campaign") and surface.journey!=null and surface.journey.party!=null and surface.menu_view==null and surface.selection_view==null and surface.local_setup==null:return surface.journey
    return null

func direction_for(slot: int,secondary: bool=false) -> Vector2i:
    if not focused or get_tree().paused or not capture_action.is_empty():return Vector2i.ZERO
    var keys: Array=[KEY_KP_6,KEY_KP_4,KEY_KP_2,KEY_KP_8] if secondary else [KEY_RIGHT,KEY_LEFT,KEY_DOWN,KEY_UP]
    var result:=Vector2i(int(Input.is_physical_key_pressed(keys[0]))-int(Input.is_physical_key_pressed(keys[1])),int(Input.is_physical_key_pressed(keys[2]))-int(Input.is_physical_key_pressed(keys[3])))
    var local: RefCounted=local_journey()
    if local!=null:result+=seats.direction(seats.device_for(int(local.party.players[slot].input)),float(profile.deadzone))
    return result.clamp(Vector2i(-1,-1),Vector2i.ONE)

func action_for(slot: int,secondary: bool=false) -> String:
    if not focused or get_tree().paused or not capture_action.is_empty():return "idle"
    var keys: Array=[KEY_KP_7,KEY_KP_9,KEY_KP_1,KEY_KP_3,KEY_KP_0,KEY_KP_PERIOD,KEY_KP_5] if secondary else [KEY_Z,KEY_X,KEY_C,KEY_V,KEY_A,KEY_D,KEY_SPACE]
    var actions: Array=["swing","heavy","lunge","reverse","upward","dagger","block"]
    var result: String="idle"
    var local: RefCounted=local_journey()
    var device: int=seats.device_for(int(local.party.players[slot].input)) if local!=null else -1
    for index in range(actions.size()):
        if Input.is_physical_key_pressed(keys[index]) or seats.down(device,profile.bindings[actions[index]]):result=actions[index]
    return result

func _process(delta: float) -> void:
    refresh_context();repeat_navigation(delta);move_pointer(delta)

func cursor_position() -> Vector2:
    # InputEventMouse positions are already in logical viewport coordinates,
    # including events forwarded by the virtual cursor and while a child is open.
    return pointer

func move_pointer(delta: float) -> void:
    var context: String=kind(active_surface())
    var enabled: bool=using_controller and focused and capture_action.is_empty() and context not in ["","world_view","arena_view","intro_view"]
    if enabled:
        var movement:=Vector2(float(axes.get(JOY_AXIS_RIGHT_X,0)) if not blocked.has("trigger"+str(JOY_AXIS_RIGHT_X)) else 0.0,float(axes.get(JOY_AXIS_RIGHT_Y,0)) if not blocked.has("trigger"+str(JOY_AXIS_RIGHT_Y)) else 0.0)
        if movement.length()>profile.deadzone:
            pointer=cursor_position()
            pointer_active=true
            var next: Vector2=(pointer+movement.normalized()*320*clampf((movement.length()-profile.deadzone)/(1-profile.deadzone),0,1)*minf(delta,0.1)).clamp(Vector2.ZERO,get_viewport().get_visible_rect().size-Vector2.ONE)
            var event:=InputEventMouseMotion.new();event.device=SYNTHETIC_DEVICE;event.position=next;event.global_position=next;event.relative=next-pointer
            pointer=next;get_tree().root.push_input(event,true)
    cursor.visible=enabled and pointer_active;cursor.queue_redraw()

func click_pointer() -> void:
    pointer=cursor_position()
    pointer_active=true
    var event:=InputEventMouseButton.new();event.device=SYNTHETIC_DEVICE;event.position=pointer;event.global_position=pointer;event.button_index=MOUSE_BUTTON_LEFT;event.button_mask=MOUSE_BUTTON_MASK_LEFT;event.pressed=true
    get_tree().root.push_input(event,true)
    event=event.duplicate();event.pressed=false;event.button_mask=0;get_tree().root.push_input(event,true)

func repeat_navigation(delta: float) -> void:
    if not focused or not capture_action.is_empty():return
    var surface: Node=active_surface()
    var context: String=kind(surface)
    if context=="arena_view" or (context=="world_view" and surface.arrival_choices.is_empty()):return
    var direction: Vector2i=pad_direction()
    if direction==Vector2i.ZERO:repeat_direction=direction;repeat_wait=0;return
    if direction!=repeat_direction:repeat_direction=direction;repeat_wait=0
    else:repeat_wait-=delta
    if repeat_wait>0:return
    repeat_wait=0.35 if repeat_wait==0 else 0.11
    send_key(KEY_DOWN if direction.y>0 else (KEY_UP if direction.y<0 else (KEY_RIGHT if direction.x>0 else KEY_LEFT)))
