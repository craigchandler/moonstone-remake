class_name JourneyStore
extends RefCounted

const Runtime=preload("res://scripts/session/runtime_mode.gd")

var path: String
var validate: Callable
var message: String = ""
var last_source: String = ""
var writable: bool = true
var session_checkpoint: Dictionary = {}
const MAX_BYTES: int = 1048576

func _init(save_path: String, validator: Callable, allow_write: bool = true) -> void:
    path = save_path
    validate = validator
    writable = allow_write and not Runtime.debug_enabled()

func read_file(file_path: String) -> Dictionary:
    if not FileAccess.file_exists(file_path): return {}
    var file := FileAccess.open(file_path, FileAccess.READ)
    if file == null or file.get_length() > MAX_BYTES: return {}
    var parser := JSON.new()
    if parser.parse(file.get_as_text()) != OK: return {}
    var envelope: Variant = parser.data
    if typeof(envelope) != TYPE_DICTIONARY or envelope.get("format") != "moonstone.journey" or envelope.get("version") != 1: return {}
    if typeof(envelope.get("data")) != TYPE_STRING or typeof(envelope.get("sha256")) != TYPE_STRING: return {}
    if envelope.data.sha256_text() != envelope.sha256: return {}
    if parser.parse(envelope.data) != OK: return {}
    return validate.call(parser.data)

func load_checkpoint() -> Dictionary:
    if not session_checkpoint.is_empty():
        last_source="session"
        message="Debug mode: progress is not saved."
        return validate.call(session_checkpoint.duplicate(true))
    for candidate in [path, path + ".bak"]:
        var data: Dictionary = read_file(candidate)
        if not data.is_empty():
            last_source = candidate
            message = "Recovered backup save." if candidate.ends_with(".bak") else "Journey ready to continue."
            return data
    message = "No compatible save found." if FileAccess.file_exists(path) else ""
    return {}

func save_checkpoint(data: Dictionary) -> bool:
    if validate.call(data).is_empty():
        message = "Save failed: invalid journey checkpoint."
        return false
    # Guard here, before directories, primary, backup or temporary files. Even
    # an accidentally writable store cannot persist a command-line debug run.
    if not writable or Runtime.debug_enabled():
        session_checkpoint=data.duplicate(true)
        message="Debug mode: progress is not saved."
        return true
    var folder: String = ProjectSettings.globalize_path(path).get_base_dir()
    if DirAccess.make_dir_recursive_absolute(folder) != OK: return failed()
    var body: String = JSON.stringify(data)
    var envelope: String = JSON.stringify({"format": "moonstone.journey", "version": 1, "data": body, "sha256": body.sha256_text()})
    var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
    if file == null: return failed()
    file.store_string(envelope)
    file.flush()
    var error: Error = file.get_error()
    file.close()
    if error != OK or read_file(path + ".tmp").is_empty(): return failed()
    # A corrupt/incompatible primary must never replace a known-good backup.
    if not read_file(path).is_empty():
        if DirAccess.copy_absolute(path, path + ".bak") != OK: return failed()
    if DirAccess.rename_absolute(path + ".tmp", path) != OK: return failed()
    message = "Journey saved."
    return true

func failed() -> bool:
    message = "Could not save journey. Check available storage."
    return false
