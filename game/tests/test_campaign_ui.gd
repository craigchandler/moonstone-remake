extends SceneTree
const Session=preload("res://scripts/session/campaign_session.gd")
const ReadModel=preload("res://scripts/session/campaign_projection.gd")
const Connection=preload("res://scripts/session/campaign_connection.gd")
const RemoteWorld=preload("res://scripts/presentation/campaign_world_view.gd")
var failures: Array[String]=[]
var checks: int=0
func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failures.append(label);push_error(label)
func _initialize() -> void:run.call_deferred()
func run() -> void:
    var s: RefCounted=Session.new(123,[0,1])
    var connection: RefCounted=Connection.new();connection.profile_path="";connection.state="playing";connection.seat=0
    connection.receive("view",ReadModel.view(s,0))
    var view: Node=RemoteWorld.new();view.connection=connection;root.add_child(view)
    await process_frame
    check(view.journey.party.players.size()==4,"classic map has all four stable knights")
    check(view.input_kind()=="world_view","network map uses the usual keyboard/controller adapter")
    view.open_pack();await process_frame
    check(view.personal_pack!=null and view.personal_pack.journey==connection.own_inventory,"own inventory is separate from shared spectator view")
    view.close_pack()
    s.command(0,1,s.epoch,"begin_turn")
    s.journey.world.active_lair="grassland_east";s.journey.start_site_combat();s.sync_phase()
    connection.receive("view",ReadModel.view(s,0));await process_frame
    check(view.arena!=null and view.arena.source_fight==connection.replica.combat,"classic battle renderer consumes the network replica")
    var before: Dictionary=s.journey.combat.simulation.snapshot()
    var replica_before: Dictionary=connection.replica.combat.simulation.snapshot()
    connection.pending_inputs=[{"sequence":1,"direction":Vector2i.RIGHT,"action":"idle"}]
    view.arena.render_frame();await physics_frame
    check(s.journey.combat.simulation.snapshot()==before and connection.replica.combat.simulation.snapshot()==replica_before,"prediction and rendering cannot mutate confirmed combat")
    view.open_pack();await process_frame
    check(view.personal_pack!=null and view.arena!=null,"players can browse inventory while battle stays present")
    view.close_pack()
    connection.state="paused";s.set_paused(true);connection.receive("view",ReadModel.view(s,0));await process_frame
    check(view.arena!=null and s.journey.combat.simulation.snapshot()==before,"pause retains exact live battle")
    view.clear_panels()
    connection.state="playing";s.set_paused(false)
    for service in ["", "smith", "healer", "tavern", "temple", "mystic"]:
        # Each case starts on the first knight's live turn. Leaving a town
        # consumes that turn, so reusing a prior case would test an AI turn.
        s=Session.new(123,[0,1]);s.command(0,1,s.epoch,"begin_turn")
        s.journey.world.position=Vector2i(277,143) if service=="mystic" else Vector2i(84,32)
        check(s.journey.enter_town("waterdeep" if service=="mystic" else "highwood"),"town fixture enters on its own turn")
        if not service.is_empty():check(s.journey.open_service(service),"town fixture supports "+service)
        s.sync_phase();connection.latest_tick=-1;connection.latest_revision=0;connection.newest_frame={};connection.receive("view",ReadModel.view(s,0));await process_frame
        check(view.town_view!=null or view.inventory_view!=null,"classic town/service panel opens: "+service)
        if view.inventory_view!=null:view.inventory_view.queue_redraw()
    # Clocked scenes use confirmed host phases; the panels cannot roll rewards.
    s=Session.new(123,[0,1]);s.command(0,1,s.epoch,"begin_turn")
    s.journey.world.position=s.journey.town("wizard").position
    check(s.journey.enter_town("wizard"),"wizard fixture enters normally")
    s.sync_phase();connection.latest_tick=-1;connection.latest_revision=0;connection.newest_frame={};connection.receive("view",ReadModel.view(s,0));await process_frame
    check(view.inventory_view!=null and view.inventory_view.input_kind()=="wizard_view","classic wizard scene uses remote clock adapter")
    for step in range(3):
        s.command(0,int(s.command_sequences.get(0,0))+1,s.epoch,"visit_next")
        connection.latest_tick=-1;connection.latest_revision=0;connection.newest_frame={};connection.receive("view",ReadModel.view(s,0));await process_frame
    check(s.journey.places.visit.phase=="sheet" and view.inventory_view!=null,"wizard gift advances to classic character sheet")
    check(connection.replica.service==s.journey.service,"opening inventory tabs preserves the confirmed service")
    view.clear_panels()
    view.queue_free();connection.close();await process_frame
    var main: Node=load("res://scenes/main.tscn").instantiate();main.parse_launch_arguments=false;main.debug_mode=false;main.saving_enabled=false;root.add_child(main)
    main.show_menu({});main.menu_view.activate("network");await process_frame
    check(main.campaign_lobby!=null and main.campaign_lobby.actions().has("resume"),"ordinary title opens campaign lobby with embedded/resume/join actions")
    main.close_campaign_network();main.queue_free();await process_frame
    connection=null;s=null;view=null;main=null
    print("CAMPAIGN_UI=",JSON.stringify({"checks":checks,"failures":failures}))
    if failures.is_empty():print("PASS: ",checks," classic campaign UI, independent inventory and presentation authority checks")
    quit(0 if failures.is_empty() else 1)
