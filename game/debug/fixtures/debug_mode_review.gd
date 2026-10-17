extends RefCounted

const Runtime=preload("res://scripts/session/runtime_mode.gd")
const Store=preload("res://scripts/session/journey_store.gd")
var checks: int=0
var failures: Array[String]=[]

func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failures.append(label)

func press(key: int) -> void:
    var event:=InputEventKey.new()
    event.keycode=key;event.physical_keycode=key;event.pressed=true
    Input.parse_input_event(event);Input.flush_buffered_events()
    event=event.duplicate();event.pressed=false
    Input.parse_input_event(event);Input.flush_buffered_events()

func files(path: String) -> Dictionary:
    var result: Dictionary={}
    for name in [path,path+".bak",path+".tmp","user://preferences.cfg"]:
        result[name]=FileAccess.get_file_as_bytes(name) if FileAccess.file_exists(name) else null
    return result

func world(parent: Node,debug_mode: bool) -> Node:
    var node: Node=load("res://scenes/main.tscn").instantiate()
    node.debug_mode=debug_mode;node.parse_launch_arguments=false;node.saving_enabled=false
    parent.add_child(node);node.set_physics_process(false)
    return node

func run_checks(parent: Node,path: String) -> Dictionary:
    var before_files: Dictionary=files(path)
    check(Runtime.has_debug(PackedStringArray(["--debug"]),PackedStringArray()),"engine-position debug flag")
    check(Runtime.has_debug(PackedStringArray(),PackedStringArray(["--debug"])),"user-position debug flag")
    check(not Runtime.has_debug(PackedStringArray(["--debug-collisions","--remote-debug"]),PackedStringArray(["--debug=false"])),"only exact flag enables game shortcuts")
    var unsafe: PackedStringArray=["--equipment-demo","--journey-demo","--cooperative","--encounter=dragon_fight","--capture=out.png","--audio-record=out.wav","--monster-timing-probe","--debug-mode-probe"]
    check(Runtime.filter_arguments(unsafe,false).is_empty(),"normal launch ignores every tested developer command")
    check(Runtime.filter_arguments(unsafe,true)==unsafe,"debug launch retains explicit developer commands")
    var public_args: PackedStringArray=["--no-gore","--mute","--sound-volume=0.5","--save-path=custom.json","--no-save","--smoke","--continue-smoke"]
    check(Runtime.filter_arguments(public_args,false)==public_args,"normal preferences and ordinary save/startup options remain")
    var normal: Node=world(parent,false)
    await parent.get_tree().process_frame
    var initial: Dictionary=normal.journey.checkpoint()
    for key in Runtime.MAP_SHORTCUTS:
        press(key)
        check(normal.journey.checkpoint()==initial and normal.arena==null and normal.practice_view==null,"normal map denies shortcut "+str(key))
    normal.show_training(&"guardian_fight");normal.show_practice()
    check(normal.arena==null and normal.practice_view==null,"direct practice entry points are also gated")
    var normal_hints: String=" ".join(normal.map_hints())
    for word in ["practice","F1","F3","Tab","DEBUG"]:check(not word in normal_hints,"normal map hides "+word)
    press(KEY_I);check(normal.inventory_view!=null,"normal inventory input remains")
    press(KEY_I);check(normal.inventory_view==null,"normal inventory closes")
    var site: String=normal.definition.lairs[0].id
    normal.journey.world.active_lair=site;normal.journey.start_site_combat();normal.show_lair()
    normal.arena.set_physics_process(false)
    await parent.get_tree().process_frame
    var combat: Dictionary=normal.arena.session.simulation.snapshot()
    for key in Runtime.ARENA_SHORTCUTS:
        press(key)
        check(normal.arena.session.simulation.snapshot()==combat,"normal fight denies shortcut "+str(key))
    press(KEY_F3);check(normal.arena!=null and normal.journey.combat!=null,"normal F3 cannot abandon a live fight")
    check(not normal.arena.debug_mode,"managed combat inherits normal launch")
    check(not "retry" in normal.arena.result_hint("victory") and not "R" in normal.arena.result_hint("defeat"),"normal results hide retries")
    check(not "F1" in normal.arena.navigation_hint() and not "restart" in normal.arena.navigation_hint(),"normal fight hides developer navigation")
    normal.queue_free()
    await parent.get_tree().process_frame
    var debug: Node=world(parent,true)
    await parent.get_tree().process_frame
    var debug_initial: Dictionary=debug.journey.checkpoint()
    press(KEY_P);check(debug.practice_view!=null,"debug P opens pictured practice")
    press(KEY_ENTER);check(debug.arena!=null and not debug.arena.managed_by_world,"debug practice starts standalone fight")
    if debug.arena!=null:
        debug.arena.set_physics_process(false)
        for key in [KEY_F1,KEY_F2,KEY_F4,KEY_F5,KEY_F6]:
            press(key)
            var expected: StringName={KEY_F1:&"duel",KEY_F2:&"spear_lair",KEY_F4:&"axe_lair",KEY_F5:&"troll_lair",KEY_F6:&"balok_lair"}[key]
            check(debug.arena.encounter==expected,"debug encounter switch "+str(key))
        press(KEY_TAB);check(debug.arena.mode==&"cooperative","debug combat mode switch")
        debug.arena.session.simulation.actors[1].health=1
        press(KEY_R);check(debug.arena.session.simulation.actors[1].health==20,"debug restart restores practice entry")
        var gore: bool=debug.arena.gore_enabled
        press(KEY_G);check(debug.arena.gore_enabled!=gore,"debug gore still toggles in memory")
        check(files(path)==before_files,"debug gore cannot create or alter preferences")
        press(KEY_F3);check(debug.arena==null and debug.journey.checkpoint()==debug_initial,"debug map return keeps journey kit independent")
        debug.set_physics_process(false)
    check("DEBUG" in " ".join(debug.map_hints()) and "practice" in " ".join(debug.map_hints()),"debug hints are visible")
    press(KEY_TAB);check(debug.journey.mode==&"cooperative","debug map mode switch")
    debug.save_store=Store.new(path,debug.journey.validate_checkpoint,false)
    debug.journey.store=debug.save_store
    debug.journey.inventory.gold+=7
    check(debug.journey.persist(),"debug progress remains usable without a disk write")
    var updated: Dictionary=debug.journey.checkpoint()
    check(debug.save_store.load_checkpoint()==updated,"debug Continue reads the session checkpoint")
    var copy: Dictionary=debug.save_store.load_checkpoint();copy.inventory.gold=999
    check(debug.save_store.load_checkpoint()==updated,"session checkpoint is copied")
    debug.show_menu(updated)
    check(debug.menu_view.debug_mode,"debug menu shows no-save notice")
    debug.journey_options_changed(true)
    check(debug.menu_view.saved.options.revisit_battles,"debug options work in memory")
    debug.menu_choice("continue")
    check(debug.menu_view==null and debug.journey.inventory.gold==updated.inventory.gold,"debug menu Continue retains session changes")
    debug.show_menu(updated)
    debug.menu_choice("new")
    check(debug.selection_view!=null,"debug New opens the ordinary knight selection")
    debug.start_selected({"kind":2,"name":"Debug Knight"})
    check(debug.selection_view==null and debug.menu_view==null and debug.journey.identity.kind==2 and debug.journey.character.experience==0,"debug New starts a fresh session without replacing a save")
    var store: RefCounted=Store.new(path,debug.journey.validate_checkpoint)
    if Runtime.debug_enabled():
        store.writable=true # A caller cannot override the command-line write guard.
        check(store.save_checkpoint(updated),"global debug write guard accepts valid session state")
        var audio: Node=parent.get_node_or_null("/root/MoonstoneAudio")
        if audio!=null:press(KEY_F8);press(KEY_F9);press(KEY_F10)
    else:
        check(store.writable,"normal stores remain writable")
    check(files(path)==before_files,"primary, backup, temporary and preference files are unchanged")
    debug.queue_free()
    await parent.get_tree().process_frame
    return {"checks":checks,"failures":failures,"launch_debug":Runtime.debug_enabled(),"normal_hints":normal_hints,"file_isolation":"PASS" if files(path)==before_files else "FAIL"}

func report(host: Node) -> void:
    var path: String="user://debug-mode-probe.json"
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--save-path="):path=arg.trim_prefix("--save-path=")
    var result: Dictionary=await run_checks(host,path)
    print("DEBUG_MODE_STATE=",JSON.stringify(result))
    if failures.is_empty():print("PASS:",checks," debug shortcut/action/hint and no-save checks")
    else:print("FAIL:",JSON.stringify(failures))
    host.get_tree().quit(0 if failures.is_empty() else 1)
