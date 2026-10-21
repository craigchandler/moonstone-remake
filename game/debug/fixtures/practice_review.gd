extends RefCounted

const Practice = preload("res://scripts/session/practice_session.gd")
const Local = preload("res://scripts/session/local_session.gd")
const Store = preload("res://scripts/session/journey_store.gd")
const Profile = preload("res://scripts/session/controller_profile.gd")
var checks: int = 0
var failures: Array[String] = []
var replays: Dictionary = {}

func check(ok: bool, label: String) -> void:
    checks += 1
    if not ok: failures.append(label)

func press(code: int, echo: bool = false) -> void:
    var event := InputEventKey.new()
    event.keycode=code; event.physical_keycode=code; event.pressed=true; event.echo=echo
    Input.parse_input_event(event); Input.flush_buffered_events()
    event=event.duplicate(); event.pressed=false
    Input.parse_input_event(event); Input.flush_buffered_events()

func click(parent: Node, point: Vector2) -> void:
    var event := InputEventMouseButton.new()
    event.position=point; event.button_index=MOUSE_BUTTON_LEFT; event.pressed=true
    parent.get_tree().root.push_input(event,true)
    event=event.duplicate(); event.pressed=false
    parent.get_tree().root.push_input(event,true)

func tap(code: int) -> void:
    var event := InputEventJoypadButton.new()
    event.device=42; event.button_index=code; event.pressed=true
    Input.parse_input_event(event); Input.flush_buffered_events()
    event=event.duplicate(); event.pressed=false
    Input.parse_input_event(event); Input.flush_buffered_events()

func files(path: String) -> Dictionary:
    var result: Dictionary = {}
    for name in [path,path+".bak",path+".tmp","user://preferences.cfg","user://controller.json"]:
        result[name]=FileAccess.get_file_as_bytes(name) if FileAccess.file_exists(name) else null
    return result

func run_checks(parent: Node, path: String) -> Dictionary:
    var controls: Node = parent.get_node("/root/MoonstoneInput")
    var old_profile: Dictionary = controls.profile.duplicate(true)
    controls.profile=Profile.defaults(); controls.clear_input(); controls.active_device=-1; controls.focused=true
    var protected: Dictionary = files(path)
    var pointer_mode: int = Input.mouse_mode
    for party in [false,true]:
        var host: Node = load("res://scenes/main.tscn").instantiate()
        host.debug_mode=false; host.parse_launch_arguments=false; host.saving_enabled=false
        parent.add_child(host); host.set_physics_process(false)
        await parent.get_tree().process_frame
        if party:
            var players: Array=[]
            for kind in range(4):players.append({"human":kind<2,"input":kind,"identity":{"kind":kind,"name":"PRACTICE "+str(kind+1)}})
            check(host.journey.start_local_party(players,7001,false),"party setup for isolation")
        else:
            host.journey.inventory.gold=73; host.journey.character.experience=7; host.journey.character.health=8
            host.journey.inventory.items.healing_potion=2
        var saved: Dictionary = host.journey.checkpoint()
        var state: Dictionary = host.journey.snapshot()
        host.save_store=Store.new(path,host.journey.validate_checkpoint,false)
        host.journey.store=host.save_store
        host.show_menu(saved)
        check(host.menu_view.rows().has("practice") and host.menu_view.rows().size()==7,"normal title exposes practice beside Continue")
        check(host.menu_view.button_rect(5).end.y<=376,"all six title rows fit above footer")
        press(KEY_P)
        check(host.practice_view!=null and not host.menu_view.visible and host.practice!=null,"normal title P opens classic practice")
        if host.practice_view==null: host.queue_free(); continue
        check(controls.kind(controls.active_surface())=="practice_menu","practice picker owns input")
        check(host.practice_view.art.panel_background.resource_path.ends_with("loot/panels.png") and host.practice_view.art.pixel_font!=null,"original arches and bitmap font")
        check(host.practice_view.choices==Practice.CHOICES and Practice.CHOICES.size()==12,"whole native roster and both knight choices")
        press(KEY_UP); check(host.practice_view.selected==11,"opponents wrap upward")
        press(KEY_DOWN); check(host.practice_view.selected==0,"opponents wrap downward")
        press(KEY_LEFT); check(host.practice_view.knight_kind==3,"knight colours wrap left")
        press(KEY_RIGHT); check(host.practice_view.knight_kind==0,"knight colours wrap right")
        press(KEY_DOWN,true); check(host.practice_view.selected==0,"key echo cannot skip menu choices")
        press(KEY_F1); press(KEY_ENTER)
        check(host.practice_view!=null and not host.practice_view.help_visible and host.arena==null,"help consumes confirm without starting fight")
        tap(JOY_BUTTON_DPAD_DOWN); tap(JOY_BUTTON_DPAD_RIGHT)
        check(host.practice_view.selected==1 and host.practice_view.knight_kind==1,"controller chooses opponent and colour")
        var prior_fight: Variant = host.practice.fight
        host.practice_choice(&"invalid")
        check(host.arena==null and host.practice.fight==prior_fight,"unknown practice content cannot start a fight")
        for index in range(Practice.CHOICES.size()):
            var choice: String = Practice.CHOICES[index]
            click(parent,host.practice_view.row_rect(index).get_center())
            check(host.practice_view.selected==index and host.arena==null,"mouse selects and previews before beginning "+choice)
            check(Rect2(346,80,246,278).encloses(host.practice_view.row_rect(index)),"opponent row fits inside arch "+choice)
            var kind: String = host.rules.encounters.get(choice,{}).get("creature","knight")
            var parts: Array[Dictionary] = host.practice_view.preview_parts(kind)
            var bounds: Rect2 = host.practice_view.preview_bounds(parts)
            check(bounds.size.x>0 and bounds.size.y>0 and not parts.is_empty(),"visible layered preview "+choice)
            if kind == "dragon": check(parts.size()==3,"Dragon preview includes both feet and head")
            if kind == "guardian": check(parts.size()==2,"Guardian preview includes body and head")
            var colour: int = host.practice_view.knight_kind
            if index%2==0: click(parent,host.practice_view.begin_rect.get_center())
            else: press(KEY_Z)
            check(host.arena!=null and not host.arena.debug_mode and host.arena.practice_mode and not host.arena.managed_by_world,"normal practice starts independent fight "+choice)
            if host.arena==null: break
            host.arena.set_physics_process(false)
            check(not host.practice_view.visible and controls.kind(controls.active_surface())=="arena_view","fight owns input "+choice)
            check(host.arena.knight_kind==colour and host.arena.session!=host.journey.combat,"chosen colour is presentation only "+choice)
            var expected: RefCounted = Local.new(host.rules)
            expected.start(&"competitive",StringName(choice),host.practice.settings())
            var initial: Dictionary = host.arena.session.simulation.snapshot()
            check(initial==expected.simulation.snapshot(),"practice uses unchanged native encounter rules "+choice)
            for tick in range(120):
                var move := Vector2i(1 if tick<24 else 0,0)
                host.arena.session.advance(move,"swing")
                expected.advance(move,"swing")
            check(host.arena.session.simulation.snapshot()==expected.simulation.snapshot(),"seeded command replay "+choice)
            if not party: replays[choice]=var_to_str(expected.simulation.snapshot()).sha256_text()
            host.arena.session.simulation.actors[1].health=1
            host.arena.session.simulation.actors[1].daggers=0
            press(KEY_R)
            check(host.arena.session.simulation.snapshot()==initial,"R restores complete fresh practice state "+choice)
            var before: Dictionary = host.arena.session.simulation.snapshot()
            press(KEY_F1); host.arena._physics_process(0.02)
            check(host.arena.practice_overlay.help_visible and host.arena.session.simulation.snapshot()==before,"help pauses fight without commands "+choice)
            press(KEY_ESCAPE)
            check(host.arena!=null and not host.arena.practice_overlay.help_visible,"Escape dismisses help without leaving "+choice)
            for key in [KEY_TAB,KEY_F2,KEY_F4,KEY_F5,KEY_F6]:press(key)
            check(host.arena.session.simulation.snapshot()==initial,"developer encounter/mode switches remain denied "+choice)
            # A deterministic result fixture checks UI timing, not combat balance.
            var model: RefCounted = host.arena.session.simulation
            model.spawn_remaining=0
            for actor in model.actors.values():
                if actor.team==2:actor.health=0; actor.down_remaining=2
            press(KEY_ENTER)
            check(model.outcome()=="victory" and not host.arena.practice_finished(),"result waits for death drawings "+choice)
            host.arena._physics_process(0.02); host.arena._physics_process(0.02)
            check(host.arena.practice_finished(),"finished practice reaches retry state "+choice)
            var settled: Dictionary=model.snapshot()
            host.arena._physics_process(0.02)
            check(model.snapshot()==settled,"finished practice freezes at settled tick "+choice)
            tap(JOY_BUTTON_A)
            check(host.arena.session.simulation.snapshot()==initial,"controller confirm retries finished practice "+choice)
            host.arena.session.simulation.actors[1].health=0
            check(host.arena.practice_overlay.result_label()=="PRACTICE LOST","defeat is labelled correctly "+choice)
            press(KEY_ENTER)
            check(host.arena.session.simulation.snapshot()==initial,"defeat confirm retries without campaign lives "+choice)
            host.arena.session.simulation.spawn_remaining=0
            for actor in host.arena.session.simulation.actors.values():actor.health=0; actor.down_remaining=0
            check(host.arena.practice_overlay.result_label()=="PRACTICE DRAW","simultaneous defeat is labelled as a draw "+choice)
            press(KEY_ENTER)
            check(host.arena.session.simulation.snapshot()==initial,"draw confirm retries complete fight "+choice)
            host._physics_process(0.02)
            check(host.journey.checkpoint()==saved and host.journey.snapshot()==state,"no world, party, kit, reward or RNG changes "+choice)
            press(KEY_ESCAPE)
            check(host.arena==null and host.practice_view.visible and host.practice_view.selected==index and host.practice_view.knight_kind==colour,"Escape retains selection and returns to opponents "+choice)
        click(parent,Vector2(316,260))
        check(host.practice==null and host.practice_view==null and host.menu_view.visible,"arch column returns to title")
        check(host.journey.checkpoint()==saved and host.journey.snapshot()==state and files(path)==protected,"entire practice visit preserves campaign and disk files")
        press(KEY_C)
        check(host.menu_view==null and host.journey.checkpoint()==saved,"Continue still restores exact saved journey")
        host.queue_free()
        await parent.get_tree().process_frame
    # Practice is also reachable on a first launch without creating a campaign save.
    var fresh: Node = load("res://scenes/main.tscn").instantiate()
    fresh.debug_mode=false; fresh.parse_launch_arguments=false; fresh.saving_enabled=false
    parent.add_child(fresh); fresh.set_physics_process(false)
    fresh.show_menu({})
    click(parent,fresh.menu_view.button_rect(fresh.menu_view.rows().find("practice")).get_center())
    check(fresh.practice_view!=null and fresh.menu_view.saved.is_empty(),"first-launch mouse practice needs no saved journey")
    press(KEY_ESCAPE)
    check(fresh.practice_view==null and fresh.menu_view.visible and files(path)==protected,"cancel preserves absent/existing files")
    fresh.queue_free(); await parent.get_tree().process_frame
    controls.clear_input(); controls.active_device=-1; controls.profile=old_profile
    check(Input.mouse_mode==pointer_mode,"practice restores original cursor mode")
    return {"checks":checks,"failures":failures,"replays":replays,"file_isolation":"PASS" if files(path)==protected else "FAIL"}

func capture_frame(host: Node, directory: String, label: String) -> void:
    await host.get_tree().process_frame
    await host.get_tree().process_frame
    await RenderingServer.frame_post_draw
    check(host.get_viewport().get_texture().get_image().save_png(directory+"/"+label+".png")==OK,"graphical capture "+label)

func graphical(parent: Node, directory: String) -> Dictionary:
    if DisplayServer.get_name()=="headless": return {"failures":["graphical capture needs a display"]}
    DirAccess.make_dir_recursive_absolute(directory)
    var host: Node=load("res://scenes/main.tscn").instantiate()
    host.debug_mode=false;host.parse_launch_arguments=false;host.saving_enabled=false
    parent.add_child(host);host.set_physics_process(false)
    host.show_menu({})
    await capture_frame(host,directory,"title-new")
    host.menu_view.saved=host.journey.checkpoint();host.menu_view.queue_redraw()
    await capture_frame(host,directory,"title-continue")
    host.menu_choice("practice")
    for index in range(Practice.CHOICES.size()):
        host.practice_view.selected=index;host.practice_view.knight_kind=index%4;host.practice_view.queue_redraw()
        await capture_frame(host,directory,"picker-%02d" % index)
    host.practice_view.help_visible=true;host.practice_view.queue_redraw()
    await capture_frame(host,directory,"picker-help")
    host.practice_view.help_visible=false
    for choice in Practice.CHOICES:
        host.practice_choice(StringName(choice));host.arena.set_physics_process(false)
        for tick in range(30):host.arena._physics_process(0.02)
        await capture_frame(host,directory,"fight-"+choice)
        if choice=="duel":
            host.arena.practice_overlay.help_visible=true;host.arena.practice_overlay.queue_redraw()
            await capture_frame(host,directory,"fight-help")
            host.arena.practice_overlay.help_visible=false
            # Explicit result layouts; not a human win/defeat or balance claim.
            host.arena.session.simulation.actors[2].health=0;host.arena.session.simulation.actors[2].down_remaining=0;host.arena.queue_redraw();host.arena.practice_overlay.queue_redraw()
            await capture_frame(host,directory,"fight-win")
            host.arena.restart()
            host.arena.session.simulation.actors[1].health=0;host.arena.queue_redraw();host.arena.practice_overlay.queue_redraw()
            await capture_frame(host,directory,"fight-loss")
        host.leave_practice_fight()
    host.close_practice();await capture_frame(host,directory,"title-return")
    host.queue_free();await parent.get_tree().process_frame
    return {"checks":checks,"failures":failures}

func report(host: Node) -> void:
    for argument in OS.get_cmdline_user_args():
        if argument.begins_with("--practice-capture="):
            var captured: Dictionary=await graphical(host,argument.trim_prefix("--practice-capture="))
            print("PRACTICE_CAPTURE=",JSON.stringify(captured))
            if captured.failures.is_empty():print("PASS: practice graphical captures")
            host.get_tree().quit(0 if captured.failures.is_empty() else 1)
            return
    var path: String="user://practice-probe.json"
    for argument in OS.get_cmdline_user_args():
        if argument.begins_with("--save-path="):path=argument.trim_prefix("--save-path=")
    var result: Dictionary=await run_checks(host,path)
    print("PRACTICE_STATE=",JSON.stringify(result))
    print("PASS: "+str(checks)+" normal practice/menu/retry/roster/isolation checks" if failures.is_empty() else "FAIL: "+JSON.stringify(failures))
    host.get_tree().quit(0 if failures.is_empty() else 1)
