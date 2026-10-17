extends SceneTree
const ART=preload("res://assets/classic/intro_menu/art.tres")
const Store=preload("res://scripts/session/journey_store.gd")
var failures: int=0
func check(ok: bool,label: String) -> void:
    if not ok:failures+=1;push_error(label)
func press(key: Key) -> void:
    var event:=InputEventKey.new();event.keycode=key;event.physical_keycode=key;event.pressed=true
    root.push_input(event,true);event=event.duplicate();event.pressed=false;root.push_input(event,true)
func click(point: Vector2) -> void:
    var event:=InputEventMouseButton.new();event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true
    root.push_input(event,true);event=event.duplicate();event.pressed=false;root.push_input(event,true)
func _initialize() -> void:run.call_deferred()
func run() -> void:
    check(ART.total_ticks==5989 and ART.frames==417 and ART.sections.size()==18,"finite opening scene count/duration")
    check(ART.music_tick==1280 and ART.music is AudioStreamWAV and absf(ART.music.get_length()-95.18)<0.001,"original opening PCM and post-credit music handoff resolve")
    check(ART.menu_loop_begin==15360 and ART.menu_loop_end==1244160 and absf(ART.menu_music.get_length()-25.92)<0.001,"four original menu voices and repeated musical-state loop")
    var last: int=0
    for run in ART.runs:
        check(run.start==last and run.ticks>0 and run.frame>=0 and run.frame<ART.frames,"contiguous native drawing runs")
        check(ART.pose_at(run.start)==run and ART.pose_at(run.start+run.ticks-1)==run,"drawing boundary lookup")
        last+=run.ticks
    check(last==ART.total_ticks,"timeline fully covers every tick")
    check(ART.credits.size()==7,"all six original credits plus personal card")
    var headings: Array=[]
    for card in ART.credits:headings.append(card.lines[0].text)
    check(headings==["created by","Programmed by","Artwork by","Music and Sound by","Additional Art by","Design by","Godot remake by"],"original credit order and named insertion anchor")
    check(ART.credits[5].lines[1].text=="Rob Anderson" and ART.credits[5].lines[2].text=="Todd Prescott" and ART.credits[6].lines[1].text=="Craig Chandler","original and requested names exact")
    var host: Node=load("res://scenes/main.tscn").instantiate();host.saving_enabled=false
    root.add_child(host);host.set_physics_process(false);await process_frame
    var audio: Node=root.get_node("MoonstoneAudio")
    audio.stop_music();audio.trace_enabled=true;audio.trace_path="user://unit-intro-audio.json";audio.played.clear()
    var store: RefCounted=Store.new("user://unit-intro-save.json",host.journey.validate_checkpoint)
    host.journey.inventory.gold=73;host.journey.character.experience=7
    var saved: Dictionary=host.journey.checkpoint();check(store.save_checkpoint(saved),"actual saved campaign fixture")
    var before: PackedByteArray=FileAccess.get_file_as_bytes(store.path)
    host.save_store=store;host.show_menu(saved)
    host.show_intro()
    check(host.intro_view!=null and not host.menu_view.visible and not audio.music_active,"credits precede the source music handoff")
    for key in [KEY_R,KEY_N,KEY_C,KEY_O,KEY_RIGHT]:press(key)
    host.travel(Vector2i.RIGHT)
    check(host.journey.checkpoint()==saved and host.intro_view!=null,"intro guards new/Continue/options/map inputs")
    press(KEY_F1);check(host.intro_view.help_visible,"intro help uses original small font")
    press(KEY_F1)
    press(KEY_SPACE)
    check(host.intro_view==null and host.menu_view!=null and host.menu_view.visible and audio.music_owner=="menu","skip reaches menu without starting journey")
    check(FileAccess.get_file_as_bytes(store.path)==before and host.journey.checkpoint()==saved,"skip never writes or changes save")
    var cues: int=audio.played.size()
    press(KEY_DOWN);press(KEY_UP);press(KEY_O);press(KEY_ESCAPE)
    check(audio.played.size()==cues,"cursor and options do not restart music")
    host.menu_view.selected=host.menu_view.rows().find("intro");press(KEY_SPACE)
    check(host.intro_view!=null and host.intro_view.tick==0,"replay through actual menu input does not instantly skip")
    click(Vector2(250,200))
    check(host.intro_view==null and host.menu_view!=null,"mouse skip consumed before menu activation")
    host.menu_choice("intro")
    var movie: Node=host.intro_view
    for tick in range(ART.total_ticks):movie.advance()
    check(host.intro_view==null and host.intro_finishes==3,"complete film returns to menu exactly once")
    movie.finish();check(host.intro_finishes==3,"completion is idempotent")
    check(FileAccess.get_file_as_bytes(store.path)==before and host.journey.checkpoint()==saved,"full opening/replays preserve actual save bytes")
    press(KEY_C)
    check(host.menu_view==null and host.journey.checkpoint()==saved and not audio.music_active,"Continue restores exact campaign and stops title score")
    var menu_cues: int=0;var intro_cues: int=0
    for cue in audio.played:
        if cue.key=="menu_music":menu_cues+=1
        if cue.key=="opening_music":intro_cues+=1
    check(menu_cues==4 and intro_cues==1,"one score onset when the film reaches its music cue; early skips remain silent")
    audio.trace_enabled=false;audio.stop_music()
    host.queue_free();await process_frame
    for name in [store.path,store.path+".bak",store.path+".tmp","user://unit-intro-audio.json"]:
        if FileAccess.file_exists(name):DirAccess.remove_absolute(name)
    if failures==0:print("PASS: full native opening, original six credits and exact remake anchor, bitmap menu, PCM loops/onsets, actual skip/replay/input guards, save byte preservation and exact Continue")
    quit(1 if failures else 0)
