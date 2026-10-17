extends RefCounted

const Profile=preload("res://scripts/session/controller_profile.gd")
const Runtime=preload("res://scripts/session/runtime_mode.gd")
const Local=preload("res://scripts/session/local_session.gd")
var controls: Node
var checks: int=0
var failures: Array[String]=[]
var traces: Dictionary={}
var device: int=42
var cursor_checks: int=0

func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failures.append(label)

func button(code: int,pressed: bool=true,pad: int=42) -> void:
    var event:=InputEventJoypadButton.new();event.device=pad;event.button_index=code;event.pressed=pressed
    Input.parse_input_event(event);Input.flush_buffered_events()

func axis(code: int,value: float,pad: int=42) -> void:
    var event:=InputEventJoypadMotion.new();event.device=pad;event.axis=code;event.axis_value=value
    Input.parse_input_event(event);Input.flush_buffered_events()

func tap(code: int) -> void:
    button(code);button(code,false)

func release_all() -> void:
    for code in range(32):button(code,false)
    for code in range(6):axis(code,0)
    controls.refresh_context()

func key(code: int,pressed: bool=true) -> void:
    var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=pressed
    Input.parse_input_event(event);Input.flush_buffered_events()

func mouse(point: Vector2,click: bool=false) -> void:
    var event: InputEventMouse=InputEventMouseButton.new() if click else InputEventMouseMotion.new()
    event.position=point;event.global_position=point
    if click:event.button_index=MOUSE_BUTTON_LEFT;event.button_mask=MOUSE_BUTTON_MASK_LEFT;event.pressed=true
    controls.get_tree().root.push_input(event,true)
    if click:
        event=event.duplicate();event.pressed=false;event.button_mask=0
        controls.get_tree().root.push_input(event,true)

func cursor_alignment_checks(parent: Node,world: Node) -> void:
    var start_checks: int=checks
    release_all()
    var exit_point:=Vector2(172,260)
    mouse(exit_point) # Position the mouse before opening; no motion in the new panel.
    world.journey.character.health=4
    world.journey.inventory.items={"healing_potion":1,"gem_of_seeing":1}
    world.show_inventory()
    var pack: Node=world.inventory_view
    check(pack.cursor_position()==exit_point and pack.pointer==exit_point,"new sheet sword starts at the real mouse position")
    check(pack.cursor_position()!=pack.row_rect(pack.selected).get_center(),"mouse sword is independent of keyboard selection")
    var initial: Vector2=pack.cursor_position()
    mouse(exit_point)
    check(pack.cursor_position()==initial,"first zero-distance motion cannot jump the sword")
    key(KEY_DOWN);key(KEY_DOWN,false)
    check(not pack.mouse_active and pack.cursor_position()==exit_point,"keyboard selection does not move the mouse sword")
    mouse(exit_point,true)
    check(world.inventory_view==null and world.journey.inventory.items.healing_potion==1,"click without moving after keyboard input exits the visible column without using an item")
    await parent.get_tree().process_frame
    world.show_inventory()
    pack=world.inventory_view
    var potion: Vector2=pack.row_rect(pack.rows().find("healing_potion")).get_center()
    # A child receives the motion, then closes. The parent must not retain its old cursor.
    var overlay: Node=load("res://scripts/presentation/original_panel_view.gd").new()
    pack.add_child(overlay)
    pack.set_process_unhandled_input(false)
    mouse(potion)
    pack.remove_child(overlay);overlay.free();pack.set_process_unhandled_input(true)
    check(pack.cursor_position()==potion,"returning from a child uses the current mouse position without another motion")
    mouse(potion,true)
    check(world.journey.character.health>4 and not world.journey.inventory.items.has("healing_potion"),"first click after child return uses exactly the displayed potion")
    mouse(exit_point)
    tap(JOY_BUTTON_RIGHT_STICK)
    check(world.inventory_view==null and controls.pointer==exit_point,"first controller cursor click uses the displayed sword without moving the stick")
    await parent.get_tree().process_frame
    world.show_inventory();pack=world.inventory_view
    var start:=Vector2(205,210)
    mouse(start)
    axis(JOY_AXIS_RIGHT_X,0.9);controls.move_pointer(0.05);axis(JOY_AXIS_RIGHT_X,0)
    check(controls.pointer.x>start.x and controls.pointer.x<start.x+20 and controls.pointer.y==start.y,"first right-stick motion starts at the displayed mouse position")
    var virtual: Vector2=controls.pointer
    check(pack.cursor_position()==virtual and pack.pointer==virtual,"controller sword and dispatched hit coordinates agree")
    tap(JOY_BUTTON_DPAD_DOWN)
    check(not pack.mouse_active and controls.pointer_active and pack.cursor_position()==virtual,"controller selection leaves its click cursor where it was drawn")
    world.close_inventory();world.show_inventory();pack=world.inventory_view
    check(pack.cursor_position()==virtual,"controller cursor stays aligned when reopening a sheet without movement")
    mouse(exit_point)
    check(pack.cursor_position()==exit_point and not controls.using_controller,"physical mouse motion takes back the same displayed and clickable cursor")
    mouse(exit_point,true)
    check(world.inventory_view==null,"mouse click after controller use hits its displayed exit")
    await parent.get_tree().process_frame
    cursor_checks=checks-start_checks

func run_checks(parent: Node) -> Dictionary:
    controls=parent.get_node("/root/MoonstoneInput")
    var old_profile: Dictionary=controls.profile.duplicate(true)
    var old_path: String=controls.settings_path
    var old_write: bool=controls.allow_write
    var path: String="user://controller-unit-"+str(OS.get_process_id())+"-"+str(Time.get_ticks_usec())+".json"
    controls.profile=Profile.defaults();controls.settings_path=path;controls.allow_write=true
    controls.clear_input();controls.blocked.clear();controls.active_device=-1;controls.focused=true
    var controller_before: PackedByteArray=FileAccess.get_file_as_bytes(old_path) if FileAccess.file_exists(old_path) else PackedByteArray()
    var preferences_before: PackedByteArray=FileAccess.get_file_as_bytes("user://preferences.cfg") if FileAccess.file_exists("user://preferences.cfg") else PackedByteArray()
    check(not Profile.validate(Profile.defaults()).is_empty(),"default profile validates")
    var swapped: Dictionary=Profile.remap(Profile.defaults(),"heavy",Profile.button(JOY_BUTTON_X))
    check(swapped.bindings.heavy.code==JOY_BUTTON_X and swapped.bindings.swing.code==JOY_BUTTON_Y,"conflicting combat bindings swap atomically")
    var shared: Dictionary=Profile.remap(Profile.defaults(),"accept",Profile.button(JOY_BUTTON_X))
    check(not shared.is_empty() and shared.bindings.help.code==JOY_BUTTON_A and shared.bindings.end_turn.code==JOY_BUTTON_A,"shared UI/map conflicts swap only in relevant contexts")
    check(Profile.remap(Profile.defaults(),"swing",Profile.button(JOY_BUTTON_START)).is_empty(),"Start remains a recovery control")
    for action in Profile.COMBAT+Profile.MENUS:
        for code in range(11):
            var binding: Dictionary=Profile.button(code)
            if not Profile.valid_binding(binding):continue
            var mapped: Dictionary=Profile.remap(Profile.defaults(),action,binding)
            check(not mapped.is_empty() and mapped.bindings[action]==binding,"valid contextual button swap "+action+" "+str(code))
        for code in [JOY_AXIS_TRIGGER_LEFT,JOY_AXIS_TRIGGER_RIGHT]:
            var mapped: Dictionary=Profile.remap(Profile.defaults(),action,Profile.trigger(code))
            check(not mapped.is_empty() and mapped.bindings[action]==Profile.trigger(code),"valid contextual trigger swap "+action+" "+str(code))
    for bad in [{}, {"version":99}, {"kind":"key","code":KEY_F1}, {"kind":"button","code":-1}, {"kind":"button","code":1.5}, {"kind":"trigger","code":JOY_AXIS_LEFT_X}]:
        check(not Profile.valid_binding(bad),"invalid or developer binding rejected")
    controls.bind_action("heavy",Profile.button(JOY_BUTTON_X));controls.set_deadzone(0.45)
    if Runtime.debug_enabled():
        check(not FileAccess.file_exists(path) and not FileAccess.file_exists(path+".tmp"),"global debug mapping changes create no files")
    else:
        check(FileAccess.file_exists(path) and not FileAccess.file_exists(path+".tmp"),"normal settings commit atomically")
        var reload: Node=load("res://scripts/presentation/controller_input.gd").new();reload.settings_path=path
        check(reload.load_preferences() and reload.profile==controls.profile,"mapping and deadzone survive a new input adapter")
        var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string("invalid controller configuration");file.close()
        reload.profile=Profile.defaults()
        check(not reload.load_preferences() and reload.profile==Profile.defaults(),"corrupt configuration falls back safely")
        reload.free()
    controls.allow_write=false;controls.reset_defaults()
    var world: Node=load("res://scenes/main.tscn").instantiate()
    world.saving_enabled=false;world.parse_launch_arguments=false;world.debug_mode=false
    parent.add_child(world);world.set_physics_process(false)
    await parent.get_tree().process_frame
    world.show_menu({});world.show_intro()
    await parent.get_tree().process_frame
    release_all();tap(JOY_BUTTON_A)
    check(world.intro_view==null and world.menu_view!=null,"controller skips opening to menu")
    check(controls.using_controller,"translated UI events retain controller hints")
    tap(JOY_BUTTON_A)
    check(world.selection_view!=null and not world.selection_view.editing,"menu confirm opens knight selection once")
    tap(JOY_BUTTON_DPAD_RIGHT);tap(JOY_BUTTON_A)
    check(world.selection_view.selected==1 and world.selection_view.editing,"controller selects a knight and accepts default name")
    tap(JOY_BUTTON_A)
    check(world.selection_view==null and world.menu_view==null and world.journey.identity.kind==1,"controller starts an ordinary journey")
    world.set_physics_process(false)
    release_all();axis(JOY_AXIS_LEFT_X,0.12)
    check(controls.direction()==Vector2i.ZERO,"stick drift stays inside deadzone")
    axis(JOY_AXIS_LEFT_X,0.8);axis(JOY_AXIS_LEFT_Y,-0.8)
    check(controls.direction()==Vector2i(1,-1),"stick movement quantizes diagonally")
    axis(JOY_AXIS_LEFT_X,0);axis(JOY_AXIS_LEFT_Y,0)
    button(JOY_BUTTON_DPAD_LEFT)
    check(controls.direction()==Vector2i.LEFT,"D-pad movement")
    button(JOY_BUTTON_DPAD_LEFT,false)
    var initial: Dictionary=world.journey.checkpoint()
    for code in [JOY_BUTTON_LEFT_SHOULDER,JOY_BUTTON_RIGHT_SHOULDER]:tap(code)
    for code in [JOY_AXIS_TRIGGER_LEFT,JOY_AXIS_TRIGGER_RIGHT]:axis(code,0.9);axis(code,0)
    check(world.journey.checkpoint()==initial and world.arena==null and world.practice_view==null,"controller cannot invoke normal-mode developer shortcuts")
    button(JOY_BUTTON_START)
    check(world.menu_view!=null,"Start opens journey menu")
    button(JOY_BUTTON_START,false)
    var index: int=world.menu_view.selected
    button(JOY_BUTTON_DPAD_DOWN);controls.repeat_navigation(0.2)
    check(world.menu_view.selected==posmod(index+1,world.menu_view.rows().size()),"menu repeat waits after initial press")
    controls.repeat_navigation(0.16)
    check(world.menu_view.selected==posmod(index+2,world.menu_view.rows().size()),"held D-pad repeats navigation")
    button(JOY_BUTTON_DPAD_DOWN,false)
    while world.menu_view.rows()[world.menu_view.selected]!="options":tap(JOY_BUTTON_DPAD_DOWN)
    tap(JOY_BUTTON_A);tap(JOY_BUTTON_DPAD_DOWN);tap(JOY_BUTTON_A)
    check(world.menu_view.controller_view!=null,"actual Options opens controller configuration")
    if world.menu_view.controller_view!=null:
        tap(JOY_BUTTON_A)
        check(controls.capture_action=="swing","choose begins capture without binding the opening confirm")
        axis(JOY_AXIS_LEFT_Y,0.9)
        check(controls.capture_action=="swing","stick navigation cannot accidentally become an attack binding")
        axis(JOY_AXIS_LEFT_Y,0);tap(JOY_BUTTON_Y)
        check(controls.profile.bindings.swing.code==JOY_BUTTON_Y and controls.profile.bindings.heavy.code==JOY_BUTTON_X,"UI capture swaps buttons and remains in configuration")
        tap(JOY_BUTTON_A);tap(JOY_BUTTON_START)
        check(controls.capture_action.is_empty(),"fixed Start cancels capture")
        tap(JOY_BUTTON_RIGHT_SHOULDER);tap(JOY_BUTTON_RIGHT_SHOULDER);tap(JOY_BUTTON_RIGHT_SHOULDER);tap(JOY_BUTTON_DPAD_DOWN)
        tap(JOY_BUTTON_DPAD_RIGHT)
        check(world.menu_view.controller_view.section==3 and controls.profile.deadzone>0.3,"controller adjusts deadzone in Settings")
        tap(JOY_BUTTON_DPAD_DOWN);tap(JOY_BUTTON_A)
        check(controls.profile==Profile.defaults(),"controller restores default mappings from Settings")
        tap(JOY_BUTTON_B)
        check(world.menu_view.controller_view==null and world.menu_view.options_open,"controller returns to Options")
    check(world.journey.checkpoint()==initial,"controller options do not mutate journey state")
    tap(JOY_BUTTON_B)
    world.menu_view.selected=world.menu_view.rows().find("continue");tap(JOY_BUTTON_A)
    controls.reset_defaults();release_all()
    world.journey.character.health=4;world.journey.inventory.items={"healing_potion":1}
    tap(JOY_BUTTON_Y)
    check(world.inventory_view!=null,"controller inventory opens")
    tap(JOY_BUTTON_A)
    check(world.inventory_view!=null and world.journey.character.health>4 and not world.journey.inventory.items.has("healing_potion"),"confirm uses potion rather than closing inventory")
    tap(JOY_BUTTON_B)
    check(world.inventory_view==null,"controller closes inventory")
    # Real loot input: confirm takes treasure; it must not act like Enter/exit.
    var site: String=world.definition.lairs[0].id
    world.journey.lair_loot[site].gold=17 # Explicit, nonrandom treasure input fixture.
    button(JOY_BUTTON_A)
    world.journey.world.active_lair=site;world.journey.start_site_combat();world.show_lair();world.arena.set_physics_process(false)
    await parent.get_tree().process_frame
    check(controls.combat_action()=="idle","held location-confirm cannot become an attack when a fight opens")
    button(JOY_BUTTON_A,false)
    world.journey.combat.simulation.spawn_remaining=0
    for actor in world.journey.combat.simulation.actors.values():
        if actor.team==2:actor.health=0
    world.journey.persist();world.show_loot()
    await parent.get_tree().process_frame
    release_all();var gold: int=world.journey.inventory.gold
    tap(JOY_BUTTON_A)
    check(world.loot_view!=null and world.journey.inventory.gold>gold,"controller confirm takes gold and stays in loot")
    tap(JOY_BUTTON_Y)
    check(world.loot_view.character_view!=null,"controller opens character sheet while looting")
    tap(JOY_BUTTON_B);tap(JOY_BUTTON_B)
    # Original trading icons need a real pointer click, not list navigation.
    var trader: RefCounted=load("res://scripts/session/journey_session.gd").new(world.definition,world.rules,123)
    trader.inventory.gold=100
    trader.world.position=trader.town("highwood").position
    trader.enter_town("highwood");trader.open_service("temple")
    trader.places.market.items={"ring_of_protection":1}
    var market: Node=load("res://scripts/presentation/town_market_view.gd").new();market.journey=trader;parent.add_child(market)
    await parent.get_tree().process_frame
    release_all()
    var stock: Array=market.buy_slots()
    check(not stock.is_empty(),"original trade fixture has stock")
    if not stock.is_empty():
        var id: String=stock[0].id
        var coins: int=trader.inventory.gold
        var owned: int=int(trader.inventory.items.get(id,0))
        controls.pointer=stock[0].rect.get_center()-Vector2(14,0)
        controls.pointer_active=true
        axis(JOY_AXIS_RIGHT_X,0.9);controls.move_pointer(0.05);axis(JOY_AXIS_RIGHT_X,0)
        check(market.mouse_active and stock[0].rect.has_point(controls.pointer),"right stick positions the original sword cursor")
        tap(JOY_BUTTON_RIGHT_STICK)
        check(trader.inventory.gold<coins and int(trader.inventory.items.get(id,0))==owned+1,"remappable cursor click buys the actual stock icon once")
        for slot in market.own_slots():
            if slot.id==id:controls.pointer=slot.rect.get_center();break
        coins=trader.inventory.gold;tap(JOY_BUTTON_RIGHT_STICK)
        check(trader.inventory.gold>coins and int(trader.inventory.items.get(id,0))==owned,"controller pointer sells the actual carried item once")
    trader.inventory.items.healing_potion=100
    var stock_page: int=market.page
    button(JOY_BUTTON_LEFT_STICK);tap(JOY_BUTTON_RIGHT_SHOULDER);button(JOY_BUTTON_LEFT_STICK,false)
    check(market.pack_page==1 and market.page==stock_page,"own-pack modifier pages personal stock without changing merchant stock")
    market.queue_free()
    await parent.get_tree().process_frame
    await cursor_alignment_checks(parent,world)
    world.queue_free()
    await parent.get_tree().process_frame
    # Full session state parity for every held combat action, including AI/RNG.
    for action in ["swing","heavy","lunge","reverse","upward","dagger","block","move"]:
        var arena: Node=load("res://scenes/arena.tscn").instantiate();arena.encounter=&"duel";arena.debug_mode=false
        parent.add_child(arena);arena.set_physics_process(false)
        await parent.get_tree().process_frame
        release_all()
        var reference: RefCounted=Local.new(arena.rule_set);reference.start(arena.mode,arena.encounter)
        if action=="move":axis(JOY_AXIS_LEFT_X,0.85);axis(JOY_AXIS_LEFT_Y,-0.85)
        else:
            var binding: Dictionary=controls.profile.bindings[action]
            if binding.kind=="button":button(binding.code)
            else:axis(binding.code,0.9)
        var direction:=Vector2i(1,-1) if action=="move" else Vector2i.ZERO
        var expected: String="idle" if action=="move" else action
        check(controls.direction()==direction and controls.combat_action()==expected,"pad command for "+action)
        for tick in range(60):
            arena._physics_process(0.02);reference.advance(direction,expected)
            check(arena.session.simulation.snapshot()==reference.simulation.snapshot(),"full input adapter/session parity "+action+" tick "+str(tick))
        traces[action]=arena.session.simulation.snapshot().hash()
        release_all()
        if action=="block":
            key(KEY_Z)
            check(controls.combat_action()=="swing","physical keyboard remains usable with a controller connected")
            key(KEY_Z,false)
            controls.bind_action("swing",Profile.button(JOY_BUTTON_Y));button(JOY_BUTTON_Y)
            check(controls.combat_action()=="swing","remapped button reaches actual combat command")
            button(JOY_BUTTON_Y,false);controls.reset_defaults();release_all()
            axis(JOY_AXIS_TRIGGER_LEFT,0.9);button(JOY_BUTTON_DPAD_DOWN)
            check(controls.combat_action()=="block" and controls.direction()==Vector2i.DOWN,"mapped guard plus Down supplies hold escape input")
            release_all()
            button(JOY_BUTTON_X,true,99)
            check(controls.combat_action()=="idle","another controller cannot hijack the active device")
            button(JOY_BUTTON_X,false,99)
            button(JOY_BUTTON_START)
            check(parent.get_tree().paused and controls.pause_view!=null,"Start pauses a fight instead of retreating")
            button(JOY_BUTTON_START,false)
            var snapshot: Dictionary=arena.session.simulation.snapshot()
            arena.set_physics_process(true)
            for frame in range(4):await parent.get_tree().process_frame
            check(arena.session.simulation.snapshot()==snapshot,"paused live combat cannot advance")
            tap(JOY_BUTTON_DPAD_DOWN);tap(JOY_BUTTON_A)
            check(controls.pause_view.options!=null,"paused combat opens mapping configuration")
            tap(JOY_BUTTON_B);tap(JOY_BUTTON_START)
            check(not parent.get_tree().paused and controls.pause_view==null,"Start resumes without changing battle kit")
            arena.set_physics_process(false)
            button(JOY_BUTTON_A);controls._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
            check(parent.get_tree().paused and controls.direction()==Vector2i.ZERO and controls.combat_action()=="idle","focus loss pauses and clears controls")
            controls._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
            tap(JOY_BUTTON_START)
            check(controls.combat_action()=="idle","held attack remains blocked after focus returns")
            button(JOY_BUTTON_A,false)
            controls.connection_changed(device,false)
            check(parent.get_tree().paused and controls.active_device==-1,"active pad disconnect pauses combat")
            button(JOY_BUTTON_START,true,7);button(JOY_BUTTON_START,false,7)
            check(controls.active_device==7 and not parent.get_tree().paused,"replacement controller can resume")
            controls.select_device(device);release_all()
        arena.queue_free()
        await parent.get_tree().process_frame
    check((FileAccess.get_file_as_bytes("user://preferences.cfg") if FileAccess.file_exists("user://preferences.cfg") else PackedByteArray())==preferences_before,"controller configuration preserves audio/gore preferences")
    check((FileAccess.get_file_as_bytes(old_path) if FileAccess.file_exists(old_path) else PackedByteArray())==controller_before,"probe leaves original controller settings untouched")
    for suffix in ["",".tmp"]:
        if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
    controls.profile=old_profile;controls.settings_path=old_path;controls.allow_write=old_write;controls.clear_input();controls.blocked.clear();controls.active_device=-1;controls.using_controller=false
    return {"checks":checks,"failures":failures,"cursor_alignment_checks":cursor_checks,"session_traces":traces,"default_profile":Profile.defaults(),"debug_no_settings_write":Runtime.debug_enabled(),"physical_hardware":"NOT_RUN: synthetic joypad input only"}

func report(host: Node) -> void:
    var result: Dictionary=await run_checks(host)
    print("CONTROLLER_STATE=",JSON.stringify(result))
    print("PASS:" if failures.is_empty() else "FAIL:",checks," controller mapping/menu/gameplay/pause/connection checks ",JSON.stringify(failures))
    host.get_tree().quit(0 if failures.is_empty() else 1)
