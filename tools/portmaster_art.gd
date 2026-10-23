extends SceneTree

# Build the catalogue thumbnail from the real game capture. Keep the original
# screenshot intact and halve its doubled classic pixels without filtering.
func _initialize() -> void:
    var arguments: PackedStringArray=OS.get_cmdline_user_args()
    if arguments.size()!=2:quit(1);return
    var capture: Image=Image.load_from_file(arguments[0])
    if capture==null or capture.get_size()!=Vector2i(640,400):quit(1);return
    capture.resize(320,200,Image.INTERPOLATE_NEAREST)
    if capture.save_png(arguments[1])!=OK:quit(1);return
    print("PASS: 320x200 muOS menu thumbnail; source capture preserved")
    quit()
