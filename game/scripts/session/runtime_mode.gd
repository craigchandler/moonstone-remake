extends RefCounted

# Shared launch policy. Editor/debug export builds alone do not enable cheats.
# Godot may consume its own --debug before exposing engine arguments. Launchers
# pass game options after --; native executables use -- --debug explicitly.
const MAP_SHORTCUTS: Array[int]=[KEY_P,KEY_TAB,KEY_F1,KEY_F2,KEY_F3,KEY_F4,KEY_F5,KEY_F6]
const ARENA_SHORTCUTS: Array[int]=[KEY_R,KEY_TAB,KEY_F1,KEY_F2,KEY_F4,KEY_F5,KEY_F6]
const PUBLIC_FLAGS: Array[String]=["--smoke","--continue-smoke","--no-save","--no-gore","--mute","--unmute"]
const PUBLIC_PREFIXES: Array[String]=["--save-path=","--sound-volume="]

static func has_debug(engine_args: PackedStringArray,user_args: PackedStringArray) -> bool:
    return "--debug" in engine_args or "--debug" in user_args

static func debug_enabled() -> bool:
    return has_debug(OS.get_cmdline_args(),OS.get_cmdline_user_args())

static func filter_arguments(arguments: PackedStringArray,debug_mode: bool) -> PackedStringArray:
    if debug_mode:return arguments.duplicate()
    var allowed: PackedStringArray=[]
    for argument in arguments:
        if argument in PUBLIC_FLAGS or PUBLIC_PREFIXES.any(func(prefix:String)->bool:return argument.begins_with(prefix)):
            allowed.append(argument)
    return allowed

static func user_arguments(debug_mode: bool) -> PackedStringArray:
    return filter_arguments(OS.get_cmdline_user_args(),debug_mode)
