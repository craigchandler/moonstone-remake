extends "res://scripts/presentation/original_panel_view.gd"

signal finished
const Profile=preload("res://scripts/session/controller_profile.gd")
var controls: Node
var section: int=0
var selected: int=0

func _ready() -> void:
    super._ready()
    process_mode=Node.PROCESS_MODE_ALWAYS
    controls=get_node("/root/MoonstoneInput")
    controls.changed.connect(queue_redraw)

func rows() -> Array:
    if section==0:return Profile.COMBAT+["back"]
    if section==1:return Profile.MENUS.slice(0,7)+["back"]
    if section==2:return Profile.MENUS.slice(7)+["back"]
    return ["device","deadzone","defaults","back"]

func row_rect(index: int) -> Rect2:return Rect2(35,88+index*23,570,22)

func change_section(amount: int) -> void:
    section=posmod(section+amount,4);selected=0;queue_redraw()

func adjust(amount: int) -> void:
    var action: String=rows()[selected]
    if section==3 and action=="deadzone":controls.set_deadzone(float(controls.profile.deadzone)+amount*0.05)
    elif section==3 and action=="device":
        var devices: PackedInt32Array=Input.get_connected_joypads()
        if not devices.is_empty():controls.select_device(devices[posmod(devices.find(controls.active_device)+amount,devices.size())])
    else:change_section(amount)
    queue_redraw()

func activate() -> void:
    var action: String=rows()[selected]
    if action=="back":finished.emit()
    elif action=="defaults":controls.reset_defaults()
    elif action=="deadzone":controls.set_deadzone(0.1 if controls.profile.deadzone>=0.6 else float(controls.profile.deadzone)+0.05)
    elif action=="device":adjust(1)
    else:controls.begin_capture(action)
    queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
    if not event is InputEventKey or not event.pressed or event.echo:return
    get_viewport().set_input_as_handled()
    if not controls.capture_action.is_empty():return
    if event.keycode==KEY_ESCAPE:finished.emit()
    elif event.keycode in [KEY_SPACE,KEY_ENTER,KEY_KP_ENTER,KEY_Z]:activate()
    elif event.keycode in [KEY_UP,KEY_DOWN]:selected=posmod(selected+(1 if event.keycode==KEY_DOWN else -1),rows().size())
    elif event.keycode in [KEY_LEFT,KEY_RIGHT]:adjust(1 if event.keycode==KEY_RIGHT else -1)
    elif event.keycode in [KEY_PAGEUP,KEY_PAGEDOWN]:change_section(1 if event.keycode==KEY_PAGEDOWN else -1)
    queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion:
        for index in range(rows().size()):
            if row_rect(index).has_point(event.position):selected=index;queue_redraw();break
    if not event is InputEventMouseButton or not event.pressed or event.button_index!=MOUSE_BUTTON_LEFT:return
    get_viewport().set_input_as_handled()
    if not controls.capture_action.is_empty():
        if Rect2(30,340,580,40).has_point(event.position):controls.cancel_capture()
        return
    if event.position.y>=48 and event.position.y<80:change_section(1 if event.position.x>=320 else -1);return
    for index in range(rows().size()):
        if row_rect(index).has_point(event.position):selected=index;activate();break

func _exit_tree() -> void:
    if is_instance_valid(controls) and not controls.capture_action.is_empty():controls.cancel_capture()
    super._exit_tree()

func _draw() -> void:
    draw_texture_rect(preload("res://assets/classic/intro_menu/art.tres").background,Rect2(0,0,640,400),false)
    draw_rect(Rect2(20,12,600,376),Color(0.02,0.025,0.035,0.96))
    pixel_text("CONTROLLER",Vector2(320,22),true,Color("ddc68c"))
    pixel_text(["< COMBAT  1/4 >","< MAP AND MENUS  2/4 >","< PACKS AND SHEETS  3/4 >","< SETTINGS  4/4 >"][section],Vector2(320,56),true)
    if controls==null:return
    for index in range(rows().size()):
        var action: String=rows()[index]
        var label: String=Profile.TITLES.get(action,{"click":"Cursor click","alternate":"Own pack page modifier","device":"Controller","deadzone":"Stick deadzone","defaults":"Restore default buttons","back":"Back"}.get(action,action))
        var value: String=controls.binding_name(action) if controls.profile.bindings.has(action) else (str(roundi(float(controls.profile.deadzone)*100))+"%" if action=="deadzone" else "")
        if index==selected:draw_rect(row_rect(index),Color(0.22,0.19,0.09,0.9))
        pixel_text(label.to_upper(),row_rect(index).position+Vector2(8,2),false,Color("ddc68c") if index==selected else Color.WHITE)
        pixel_text(value.to_upper(),Vector2(525,row_rect(index).position.y+2),true)
    var device: String=controls.device_name()
    pixel_text(device.left(56).to_upper(),Vector2(320,321),true,Color("aaaeb8"))
    if not controls.capture_action.is_empty():
        pixel_text(("PRESS CONTROL FOR "+Profile.TITLES[controls.capture_action]).left(56).to_upper(),Vector2(320,343),true,Color("ddc68c"))
        pixel_text("RELEASE FIRST / START, ESC OR CLICK HERE CANCELS",Vector2(320,365),true)
    else:
        var info: String=controls.notice if not controls.notice.is_empty() else "Stick / D-pad move; Start always pauses or goes back."
        pixel_text(info.left(57).to_upper(),Vector2(320,343),true,Color("aaaeb8"))
        pixel_text((controls.binding_name("accept")+" CHOOSE / "+controls.binding_name("cancel")+" BACK / "+controls.binding_name("previous_page")+" "+controls.binding_name("next_page")+" PAGES").left(58).to_upper(),Vector2(320,365),true)
