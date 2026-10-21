extends SceneTree
const Session=preload("res://scripts/session/campaign_session.gd")
const Store=preload("res://scripts/session/campaign_store.gd")
const Host=preload("res://scripts/session/campaign_host.gd")
var failures: Array[String]=[]
var checks: int=0
func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failures.append(label);push_error(label)
func _initialize() -> void:
    var s: RefCounted=Session.new(9123,[0,3])
    var path: String="user://campaign-store-test-"+str(OS.get_process_id())+".json"
    var store: RefCounted=Store.new(path)
    check(store.load_room(s.journey.validate_checkpoint).is_empty(),"missing network save is not a solo save")
    var value: Dictionary={"room":"a".repeat(32),"credentials":{0:"1".repeat(64),3:"2".repeat(64)},"checkpoint":s.safe_checkpoint()}
    check(store.save_room(value,s.journey.validate_checkpoint),"network envelope accepts the complete reserved roster")
    check(store.save_room(value,s.journey.validate_checkpoint),"second save creates a safe backup")
    var loaded: Dictionary=store.load_room(s.journey.validate_checkpoint)
    check(loaded.room==value.room and loaded.credentials.size()==2 and not s.journey.validate_checkpoint(loaded.checkpoint).is_empty(),"saved envelope retains compatible party checkpoint and credentials")
    var broken: Dictionary=value.duplicate(true);broken.credentials.erase(3)
    check(not store.save_room(broken,s.journey.validate_checkpoint),"missing human credential cannot create an unrecoverable room")
    broken=value.duplicate(true);broken.credentials[2]="3".repeat(64)
    check(not Store.valid(broken,s.journey.validate_checkpoint),"AI seat cannot receive a reconnect credential")
    broken=value.duplicate(true);broken.credentials[0]="z".repeat(64)
    check(not Store.valid(broken,s.journey.validate_checkpoint),"malformed private hash is rejected")
    var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string("corrupt primary");file.close()
    check(store.load_room(s.journey.validate_checkpoint).room==value.room,"corrupt primary recovers the last validated backup")
    file=FileAccess.open(path+".bak",FileAccess.WRITE);file.store_string("corrupt backup");file.close()
    check(store.load_room(s.journey.validate_checkpoint).is_empty(),"two corrupt copies are not silently replaced")
    var host: RefCounted=Host.new(2,1,path)
    check(not host.notice.is_empty() and not host.listen(38000+OS.get_process_id()%10000),"host refuses to overwrite an invalid existing save")
    for suffix in ["",".bak",".tmp"]:
        if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
    if failures.is_empty():print("PASS: ",checks," separate network saves, credentials, corruption recovery and overwrite protection")
    quit(0 if failures.is_empty() else 1)
