extends RefCounted

const COMBAT: Array[String]=["swing","heavy","lunge","reverse","upward","dagger","block","retreat"]
const MENUS: Array[String]=["accept","cancel","inventory","end_turn","help","click","alternate","previous_page","next_page","previous_tab","next_tab"]
const TITLES: Dictionary={"swing":"Swing","heavy":"Overhead chop","lunge":"Lunge","reverse":"Reverse strike","upward":"Upward thrust","dagger":"Throw dagger","block":"Guard / hold escape","retreat":"Retreat","accept":"Choose / enter / use","cancel":"Back / close","inventory":"Inventory","end_turn":"End turn on map","help":"Panel help","previous_page":"Previous pack page","next_page":"Next pack page","previous_tab":"Previous sheet","next_tab":"Next sheet","click":"Cursor click","alternate":"Own pack page modifier"}
const CONTEXTS: Array=[COMBAT,["accept","cancel","inventory","end_turn"],["accept","cancel","inventory","help","click","alternate","previous_page","next_page","previous_tab","next_tab"]]

static func button(code: int) -> Dictionary:return {"kind":"button","code":code}
static func trigger(code: int) -> Dictionary:return {"kind":"trigger","code":code}
static func defaults() -> Dictionary:
    return {"version":1,"deadzone":0.3,"bindings":{
        "swing":button(JOY_BUTTON_X),"heavy":button(JOY_BUTTON_Y),"lunge":button(JOY_BUTTON_A),"reverse":button(JOY_BUTTON_B),
        "upward":button(JOY_BUTTON_LEFT_SHOULDER),"dagger":button(JOY_BUTTON_RIGHT_SHOULDER),"block":trigger(JOY_AXIS_TRIGGER_LEFT),"retreat":button(JOY_BUTTON_BACK),
        "accept":button(JOY_BUTTON_A),"cancel":button(JOY_BUTTON_B),"inventory":button(JOY_BUTTON_Y),"end_turn":button(JOY_BUTTON_X),"help":button(JOY_BUTTON_X),
        "click":button(JOY_BUTTON_RIGHT_STICK),"alternate":button(JOY_BUTTON_LEFT_STICK),"previous_page":button(JOY_BUTTON_LEFT_SHOULDER),"next_page":button(JOY_BUTTON_RIGHT_SHOULDER),"previous_tab":trigger(JOY_AXIS_TRIGGER_LEFT),"next_tab":trigger(JOY_AXIS_TRIGGER_RIGHT)}}

static func valid_binding(value: Variant) -> bool:
    if not value is Dictionary or value.size()!=2 or not value.has_all(["kind","code"]):return false
    if typeof(value.code) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value.code)) or float(value.code)!=floorf(float(value.code)):return false
    if value.kind=="trigger":return int(value.code) in [JOY_AXIS_TRIGGER_LEFT,JOY_AXIS_TRIGGER_RIGHT]
    return value.kind=="button" and int(value.code)>=0 and int(value.code)<128 and int(value.code) not in [JOY_BUTTON_START,JOY_BUTTON_DPAD_UP,JOY_BUTTON_DPAD_DOWN,JOY_BUTTON_DPAD_LEFT,JOY_BUTTON_DPAD_RIGHT]

static func validate(value: Variant) -> Dictionary:
    if not value is Dictionary or value.size()!=3 or not value.has_all(["version","deadzone","bindings"]) or value.version!=1:return {}
    if typeof(value.deadzone) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value.deadzone)) or value.deadzone<0.1 or value.deadzone>0.6:return {}
    if not value.bindings is Dictionary or value.bindings.size()!=COMBAT.size()+MENUS.size():return {}
    var result: Dictionary={"version":1,"deadzone":float(value.deadzone),"bindings":{}}
    for action in COMBAT+MENUS:
        if not valid_binding(value.bindings.get(action)):return {}
        result.bindings[action]={"kind":value.bindings[action].kind,"code":int(value.bindings[action].code)}
    for group in CONTEXTS:
        var used: Array=[]
        for action in group:
            if result.bindings[action] in used:return {}
            used.append(result.bindings[action])
    return result

static func remap(profile: Dictionary,action: String,binding: Dictionary) -> Dictionary:
    if not profile.bindings.has(action) or not valid_binding(binding):return {}
    var next: Dictionary=profile.duplicate(true)
    var previous: Dictionary=next.bindings[action].duplicate()
    next.bindings[action]=binding.duplicate()
    # An action such as Inventory belongs to both map and panel contexts.
    # Propagate the control swap through those shared contexts atomically.
    var pending: Array[String]=[action]
    var changed: Dictionary={action:true}
    while not pending.is_empty():
        var current: String=pending.pop_back()
        for group in CONTEXTS:
            if current not in group:continue
            for other in group:
                if other==current or next.bindings[other]!=next.bindings[current]:continue
                if changed.has(other):return {}
                next.bindings[other]=(previous if next.bindings[current]==binding else binding).duplicate()
                changed[other]=true;pending.append(other)
    return validate(next)

static func label(binding: Dictionary) -> String:
    if binding.kind=="trigger":return "LT" if int(binding.code)==JOY_AXIS_TRIGGER_LEFT else "RT"
    return {JOY_BUTTON_A:"A",JOY_BUTTON_B:"B",JOY_BUTTON_X:"X",JOY_BUTTON_Y:"Y",JOY_BUTTON_BACK:"View",JOY_BUTTON_GUIDE:"Guide",JOY_BUTTON_LEFT_SHOULDER:"LB",JOY_BUTTON_RIGHT_SHOULDER:"RB",JOY_BUTTON_LEFT_STICK:"L3",JOY_BUTTON_RIGHT_STICK:"R3"}.get(int(binding.code),"Button "+str(int(binding.code)+1))
