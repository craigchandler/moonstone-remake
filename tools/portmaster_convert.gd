extends Node

# Runs in the export runtime, with no editor/import database. Convert disk-
# derived PNG/WAV files to native resources and pack declarative content only.
var pack: PCKPacker
var temporary: String
var game_root: String
var count: int=0
var last_progress_ms: int=0
var recovered_paths: Dictionary={}
var item_index: int=0
var worker: int=0
var workers: int=1

func fail(message: String) -> void:
    push_error(message)
    get_tree().quit(1)

func _ready() -> void:
    var args: PackedStringArray=OS.get_cmdline_user_args().slice(1)
    if args.size() not in [3,5]:fail("Expected source game directory, output PCK, temporary directory and optional worker partition");return
    if args.size()==5:
        worker=int(args[3]);workers=int(args[4])
        if workers<1 or workers>4 or worker<0 or worker>=workers:fail("Invalid resource worker partition");return
    game_root=args[0]
    temporary=args[2]
    # Recovery exports contain thousands of intermediate cels/contact sheets.
    # Only retained resource references and literal game references need native
    # textures. Leave source recovery files intact for independent verification.
    var literals: Variant=JSON.parse_string(FileAccess.get_file_as_string(game_root.get_base_dir().path_join("runtime_media_paths.json")))
    if not literals is Array:fail("Missing runtime media reference list");return
    for path in literals:recovered_paths[path]=true
    collect_recovered_references(game_root)
    print("CONTENT_PACK_STARTED")
    DirAccess.make_dir_recursive_absolute(temporary)
    pack=PCKPacker.new()
    if pack.pck_start(args[1])!=OK:fail("Cannot create content pack");return
    for folder in ["assets/classic", "content/generated"]:
        if not add_folder(folder):return
    if count==0 or pack.flush()!=OK:fail("Cannot finish content pack");return
    print("CONTENT_PACK_FILES="+str(count))
    get_tree().quit()

func collect_recovered_references(folder: String) -> void:
    var dir: DirAccess=DirAccess.open(folder)
    if dir==null:return
    for child in dir.get_directories():collect_recovered_references(folder.path_join(child))
    var pattern: RegEx=RegEx.new()
    pattern.compile('res://assets/classic/recovered/[^"\\s]+\\.png')
    for name in dir.get_files():
        if name.get_extension()!="tres":continue
        for found in pattern.search_all(FileAccess.get_file_as_string(folder.path_join(name))):
            recovered_paths[found.get_string()]=true

func add_folder(relative: String) -> bool:
    var dir: DirAccess=DirAccess.open(game_root.path_join(relative))
    if dir==null:fail("Missing converted content: "+relative);return false
    var directories: PackedStringArray=dir.get_directories()
    directories.sort()
    for child in directories:
        if not add_folder(relative.path_join(child)):return false
    var files: PackedStringArray=dir.get_files()
    files.sort()
    for name in files:
        var path: String=relative.path_join(name)
        var source: String=game_root.path_join(path)
        var extension: String=name.get_extension()
        if extension not in ["png", "wav", "tres", "json"]:continue
        if path.begins_with("assets/classic/recovered/") and extension=="png" and not recovered_paths.has("res://"+path):continue
        # Separate headless processes own every ImageTexture and ResourceSaver;
        # no rendering/resource objects are shared across threads or workers.
        item_index+=1
        if (item_index-1)%workers!=worker:continue
        if extension in ["png", "wav"]:
            var resource: Resource
            if extension=="png":
                var pixels: Image=Image.load_from_file(source)
                if pixels==null:fail("Cannot read "+path);return false
                resource=ImageTexture.create_from_image(pixels)
            else:
                # Match the desktop import preset's QOA compression and retain
                # sample rate, channels, timing and gain. Keep the smaller audio
                # footprint on 1 GB handhelds.
                resource=AudioStreamWAV.load_from_file(source,{"compress/mode":2,"edit/trim":false,"edit/normalize":false})
            if resource==null:fail("Cannot convert "+path);return false
            var converted: String=temporary.path_join("resource.res")
            if ResourceSaver.save(resource,converted,ResourceSaver.FLAG_COMPRESS)!=OK:fail("Cannot save "+path);return false
            var packed_path: String="res://.moonstone/"+path+".res"
            if pack.add_file(packed_path,converted)!=OK:fail("Cannot pack "+path);return false
            var remap_path: String=temporary.path_join("resource.remap")
            var remap: FileAccess=FileAccess.open(remap_path,FileAccess.WRITE)
            remap.store_string('[remap]\npath="'+packed_path+'"\n')
            remap.close()
            if pack.add_file("res://"+path+".remap",remap_path)!=OK:fail("Cannot map "+path);return false
        elif pack.add_file("res://"+path,source)!=OK:fail("Cannot pack "+path);return false
        count+=1
        report_progress()
    return true

func report_progress() -> void:
    var now: int=Time.get_ticks_msec()
    if now-last_progress_ms<1000:return
    last_progress_ms=now
    print("CONTENT_PACK_PROGRESS="+str(count))
    var path: String=OS.get_environment("MOONSTONE_IMPORT_STATUS")
    if path.is_empty() or not FileAccess.file_exists(path):return
    var status: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
    if not status is Dictionary or status.get("state")!="running":return
    status["detail"]="Packed resources: "+str(count)
    var file: FileAccess=FileAccess.open(path+".new",FileAccess.WRITE)
    if file==null:return
    file.store_string(JSON.stringify(status)+"\n")
    file.close()
    DirAccess.rename_absolute(path+".new",path)
