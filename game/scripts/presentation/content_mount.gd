extends Node

# First autoload: mount the user's generated resources before scripts preload
# presentation assets. Ordinary provisioned desktop builds need no mount.
func _init() -> void:
    var path: String=OS.get_environment("MOONSTONE_CONTENT_PACK")
    if path.is_empty():return
    if not ProjectSettings.load_resource_pack(path, false):
        push_error("Moonstone content could not be opened: "+path)
        Engine.get_main_loop().quit(1)
        return
    print("Moonstone external content mounted")
