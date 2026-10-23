extends Control

var game_dir: String
var worker: int=-1
var elapsed: float=0
var message: Label
var bar: ProgressBar
var footer: Label
var started_ms: int=0
var state: String="missing"
var cancelling: bool=false

func _ready() -> void:
    if "--verify-content" in OS.get_cmdline_user_args():
        verify_content()
        return
    if "--convert" in OS.get_cmdline_user_args():
        add_child(load("res://convert.gd").new())
        return
    # This window only polls status twice a second. Leave CPU/GPU time for the
    # converters; the game runs in a separate process with its normal settings.
    Engine.max_fps=10
    OS.low_processor_usage_mode=true
    game_dir=OS.get_environment("MOONSTONE_GAME_DIR")
    get_tree().auto_accept_quit=false
    var background:=ColorRect.new()
    background.color=Color(0.035,0.045,0.065)
    background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(background)
    var title:=Label.new()
    title.text="MOONSTONE — ORIGINAL GAME DATA"
    title.position=Vector2(32,40);title.add_theme_font_size_override("font_size",23)
    add_child(title)
    message=Label.new()
    message.position=Vector2(32,110);message.size=Vector2(576,240)
    message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
    message.add_theme_font_size_override("font_size",19)
    add_child(message)
    bar=ProgressBar.new();bar.position=Vector2(32,360);bar.size=Vector2(576,24)
    bar.show_percentage=false
    add_child(bar)
    footer=Label.new();footer.text="A: retry     B: exit"
    footer.position=Vector2(32,410);footer.add_theme_font_size_override("font_size",18)
    add_child(footer)
    if "--setup-probe" in OS.get_cmdline_user_args():
        print("SETUP_STATE="+JSON.stringify({"missing_assets_ui":true,"original_assets_loaded":false}))
        get_tree().quit();return
    start_import()
    for argument in OS.get_cmdline_user_args():
        if argument.begins_with("--setup-capture="):
            capture_setup.call_deferred(argument.trim_prefix("--setup-capture="))

func verify_content() -> void:
    var args:=OS.get_cmdline_user_args()
    if args.size()!=2:get_tree().quit(1);return
    var folder:String=args[1].path_join("content")
    var pointer:Variant=JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("current.json")))
    if not pointer is Dictionary or pointer.get("version")!=1:get_tree().quit(1);return
    var checksum:String=str(pointer.get("sha256",""))
    var pattern:=RegEx.new();pattern.compile("^[0-9a-f]{64}$")
    if pattern.search(checksum)==null or pointer.get("directory")!="classic-v1-"+checksum.left(16):get_tree().quit(1);return
    var generation:String=folder.path_join(str(pointer.directory))
    var pack_path:String=generation.path_join("assets.pck")
    var report:Variant=JSON.parse_string(FileAccess.get_file_as_string(generation.path_join("manifest.json")))
    if not report is Dictionary or report.get("version")!=1 or report.get("sha256")!=checksum or report.get("startup")!="PASS":get_tree().quit(1);return
    if FileAccess.get_sha256(pack_path)!=checksum:get_tree().quit(1);return
    print("CONTENT_PACK_PATH="+pack_path)
    get_tree().quit(0)

func capture_setup(path: String) -> void:
    # Covered test windows can stop emitting frame_post_draw.
    RenderingServer.force_draw(false)
    var result: int=get_viewport().get_texture().get_image().save_png(path)
    get_tree().quit(0 if result==OK else 1)

func start_import() -> void:
    if worker>0:return
    var missing: PackedStringArray=[]
    for disk in ["A","B","C"]:
        if not FileAccess.file_exists(game_dir.path_join("disks/Moonstone_Disk"+disk+".ipf")):missing.append(disk)
    if not missing.is_empty():
        state="missing"
        message.text="Copy your three original IPF images into the disks folder beside the game, named:\n\nMoonstone_DiskA.ipf\nMoonstone_DiskB.ipf\nMoonstone_DiskC.ipf\n\nThen press A or Enter."
        return
    state="running"
    started_ms=Time.get_ticks_msec()
    footer.text="B: cancel"
    message.text="Preparing your original game data.\n\nKeep the device powered on. This happens once; later launches use the saved content."
    var old_status: String=game_dir.path_join("import-status.json")
    if FileAccess.file_exists(old_status):DirAccess.remove_absolute(old_status)
    var cancellation: String=game_dir.path_join("import-cancel")
    if FileAccess.file_exists(cancellation):DirAccess.remove_absolute(cancellation)
    cancelling=false
    var python: String=OS.get_environment("MOONSTONE_LAUNCHER_PYTHON")
    if python.is_empty():
        var runner: String=game_dir.path_join("moonstone-run")
        if not FileAccess.file_exists(runner):runner=game_dir.path_join("moonstone-run.sh")
        worker=OS.create_process("/bin/bash",[runner,
            "--prepare-content",OS.get_executable_path()])
    else:
        worker=OS.create_process(python,["-B",game_dir.path_join("moonstone-launcher.py"),"--prepare-content"])
    if worker<=0:
        state="failed";message.text="Could not start the importer. Reinstall the Moonstone package."
        footer.text="A: retry     B: exit"

func _process(delta: float) -> void:
    if worker<=0:return
    elapsed+=delta
    if elapsed<0.5:return
    elapsed=0
    var file: String=game_dir.path_join("import-status.json")
    if FileAccess.file_exists(file):
        var status: Variant=JSON.parse_string(FileAccess.get_file_as_string(file))
        if status is Dictionary:
            message.text=str(status.get("message","Preparing content"))
            if status.has("detail"):message.text+="\n"+str(status.detail)
            bar.value=float(status.get("percent",0))
            state=str(status.get("state","running"))
            if state=="running":
                var seconds: int=int((Time.get_ticks_msec()-started_ms)/1000)
                if status.has("stage"):
                    message.text+="\nStep %d of %d" % [int(status.stage),int(status.stages)]
                message.text+="\n\nElapsed: %d:%02d\nStages vary in length. Keep the device powered on." % [seconds/60,seconds%60]
    if not OS.is_process_running(worker):
        worker=-1
        footer.text="A: retry     B: exit"
        if cancelling:get_tree().quit(2)
        elif state=="complete":get_tree().quit(0)
        elif state!="failed":state="failed";message.text="Import stopped. See import.log beside the game, then press A or Enter to retry."

func cancel_import() -> void:
    if worker<=0:
        get_tree().quit(2)
        return
    cancelling=true
    var file:=FileAccess.open(game_dir.path_join("import-cancel"),FileAccess.WRITE)
    if file!=null:file.store_string("cancel\n");file.close()
    message.text="Cancelling import. Waiting for the tools to stop."
    footer.text="Your previous content and saves are preserved."

func _notification(what: int) -> void:
    if what==NOTIFICATION_WM_CLOSE_REQUEST:cancel_import()

func _input(event: InputEvent) -> void:
    var accept: bool=(event is InputEventJoypadButton and event.pressed and event.button_index==JOY_BUTTON_A) or (event is InputEventKey and event.pressed and event.keycode==KEY_ENTER)
    var cancel: bool=(event is InputEventJoypadButton and event.pressed and event.button_index==JOY_BUTTON_B) or (event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE)
    if accept and worker<=0:start_import()
    if cancel:cancel_import()
