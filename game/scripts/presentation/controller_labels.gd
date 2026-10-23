extends RefCounted

const Profile=preload("res://scripts/session/controller_profile.gd")

static func label(binding: Dictionary,device: String) -> String:
    # The PortMaster SDL3 mapping named RG40XX H maps face buttons by their
    # printed letters. Only presentation names change; saved bindings do not.
    if device=="RG40XX H":
        if binding.kind=="trigger":return "L2" if int(binding.code)==JOY_AXIS_TRIGGER_LEFT else "R2"
        var names: Dictionary={JOY_BUTTON_BACK:"SE",JOY_BUTTON_START:"ST",JOY_BUTTON_GUIDE:"M",JOY_BUTTON_LEFT_SHOULDER:"L1",JOY_BUTTON_RIGHT_SHOULDER:"R1"}
        if names.has(int(binding.code)):return names[int(binding.code)]
    if binding.kind=="button" and int(binding.code)==JOY_BUTTON_START:return "Start"
    return Profile.label(binding)
