extends RefCounted

# Device IDs are runtime-only. Saved player choices are logical controller ports.
var states: Dictionary={}
var test_devices: Array=[]
var port_devices: Array=[-1,-1,-1,-1]

func ingest(event: InputEvent,deadzone: float) -> void:
    if not states.has(event.device):states[event.device]={"buttons":{},"axes":{},"blocked":{}}
    var state: Dictionary=states[event.device]
    if event is InputEventJoypadButton:
        state.buttons[event.button_index]=event.pressed
        if not event.pressed:state.blocked.erase("button"+str(event.button_index))
    else:
        state.axes[event.axis]=event.axis_value
        if absf(event.axis_value)<minf(0.2,deadzone):state.blocked.erase("trigger"+str(event.axis))

func devices() -> Array:
    return test_devices.duplicate() if not test_devices.is_empty() else Array(Input.get_connected_joypads())

func device_for(port: int) -> int:
    var connected: Array=devices()
    for device in connected:
        if device not in port_devices and -1 in port_devices:port_devices[port_devices.find(-1)]=device
    if port<=0 or port>4:return -1
    return int(port_devices[port-1]) if port_devices[port-1] in connected else -1

func down(device: int,binding: Dictionary) -> bool:
    var state: Dictionary=states.get(device,{"buttons":{},"axes":{},"blocked":{}})
    if state.blocked.has(binding.kind+str(binding.code)):return false
    return bool(state.buttons.get(binding.code,false)) if binding.kind=="button" else float(state.axes.get(binding.code,0))>0.5

func direction(device: int,deadzone: float) -> Vector2i:
    var state: Dictionary=states.get(device,{"buttons":{},"axes":{},"blocked":{}})
    var x: float=0 if state.blocked.has("trigger"+str(JOY_AXIS_LEFT_X)) else float(state.axes.get(JOY_AXIS_LEFT_X,0))
    var y: float=0 if state.blocked.has("trigger"+str(JOY_AXIS_LEFT_Y)) else float(state.axes.get(JOY_AXIS_LEFT_Y,0))
    return Vector2i(clampi(int(x>deadzone)-int(x< -deadzone)+int(down(device,{"kind":"button","code":JOY_BUTTON_DPAD_RIGHT}))-int(down(device,{"kind":"button","code":JOY_BUTTON_DPAD_LEFT})),-1,1),clampi(int(y>deadzone)-int(y< -deadzone)+int(down(device,{"kind":"button","code":JOY_BUTTON_DPAD_DOWN}))-int(down(device,{"kind":"button","code":JOY_BUTTON_DPAD_UP})),-1,1))

func block_held(deadzone: float) -> void:
    for state in states.values():
        for code in state.buttons:
            if state.buttons[code]:state.blocked["button"+str(code)]=true
        for code in state.axes:
            if absf(float(state.axes[code]))>deadzone:state.blocked["trigger"+str(code)]=true

func clear() -> void:
    for state in states.values():state.buttons.clear();state.axes.clear()

func disconnected(device: int) -> void:
    states.erase(device)
    if device in port_devices:port_devices[port_devices.find(device)]=-1
