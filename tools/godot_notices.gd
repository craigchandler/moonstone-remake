extends SceneTree

func _initialize() -> void:
    var arguments: PackedStringArray = OS.get_cmdline_user_args()
    if arguments.size() != 1:
        quit(1)
        return
    var folder: String = arguments[0]
    if DirAccess.make_dir_recursive_absolute(folder) != OK:
        quit(1)
        return
    var license_file := FileAccess.open(folder.path_join("GODOT-LICENSE.txt"), FileAccess.WRITE)
    var copyright_file := FileAccess.open(folder.path_join("GODOT-COPYRIGHT.txt"), FileAccess.WRITE)
    if license_file == null or copyright_file == null:
        quit(1)
        return
    license_file.store_string(Engine.get_license_text())
    copyright_file.store_string(JSON.stringify(Engine.get_copyright_info(), "  ") + "\n\n")
    for name in Engine.get_license_info():
        copyright_file.store_string(name + "\n" + Engine.get_license_info()[name] + "\n\n")
    license_file.close()
    copyright_file.close()
    print("PASS: engine and third-party notices generated from the matching binary")
    quit()
