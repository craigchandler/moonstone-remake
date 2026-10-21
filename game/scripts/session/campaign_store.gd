extends RefCounted

# Network campaigns have their own envelope and never write journey.json.
const MAX_BYTES: int=2097152
var path: String
var notice: String=""
func _init(file_path: String) -> void:path=file_path
func load_room(validate: Callable) -> Dictionary:
    for candidate in [path,path+".bak"]:
        if not FileAccess.file_exists(candidate):continue
        var file: FileAccess=FileAccess.open(candidate,FileAccess.READ)
        if file==null or file.get_length()>MAX_BYTES:continue
        var parser:=JSON.new()
        if parser.parse(file.get_as_text())!=OK:continue
        var envelope: Variant=parser.data
        if typeof(envelope)!=TYPE_DICTIONARY or envelope.get("format")!="moonstone.network-campaign" or envelope.get("version")!=1 or typeof(envelope.get("data"))!=TYPE_STRING or typeof(envelope.get("sha256"))!=TYPE_STRING or envelope.data.sha256_text()!=envelope.sha256:continue
        if parser.parse(envelope.data)!=OK:continue
        var value: Variant=parser.data
        if typeof(value)!=TYPE_DICTIONARY or not valid(value,validate):continue
        return value
    return {}
static func valid(value: Dictionary,validate: Callable) -> bool:
    if value.size()!=3 or typeof(value.get("room"))!=TYPE_STRING or value.room.length()!=32 or not value.room.is_valid_hex_number(false) or typeof(value.get("credentials"))!=TYPE_DICTIONARY or value.credentials.size()>4 or validate.call(value.get("checkpoint")).is_empty():return false
    var checkpoint: Dictionary=validate.call(value.checkpoint)
    if checkpoint.get("schema")!=17:return false
    var humans: int=0
    for player in checkpoint.party.players:
        if player.human:humans+=1
    if value.credentials.size()!=humans:return false
    for key in value.credentials:
        if str(key) not in ["0","1","2","3"] or not checkpoint.party.players[int(key)].human:return false
        var hash: Variant=value.credentials[key]
        if typeof(hash)!=TYPE_STRING or hash.length()!=64 or not hash.is_valid_hex_number(false):return false
    return true
func save_room(value: Dictionary,validate: Callable) -> bool:
    if path.is_empty():return true
    if not valid(value,validate):notice="INVALID CAMPAIGN SAVE";return false
    var data: String=JSON.stringify(value)
    var text: String=JSON.stringify({"format":"moonstone.network-campaign","version":1,"data":data,"sha256":data.sha256_text()})
    if text.to_utf8_buffer().size()>MAX_BYTES:return false
    var absolute: String=ProjectSettings.globalize_path(path)
    if DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())!=OK:return false
    var temp: FileAccess=FileAccess.open(path+".tmp",FileAccess.WRITE)
    if temp==null:notice="CANNOT WRITE CAMPAIGN SAVE";return false
    temp.store_string(text);temp.flush();temp.close()
    if FileAccess.file_exists(path):
        if DirAccess.copy_absolute(absolute,absolute+".bak")!=OK:notice="CANNOT BACK UP CAMPAIGN SAVE";return false
    if DirAccess.rename_absolute(absolute+".tmp",absolute)!=OK:notice="CANNOT REPLACE CAMPAIGN SAVE";return false
    notice="";return true
