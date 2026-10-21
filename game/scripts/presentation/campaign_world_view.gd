extends "res://scripts/presentation/world_view.gd"

signal finished
const RemoteInventory=preload("res://scripts/presentation/campaign_inventory_view.gd")
const RemoteLoot=preload("res://scripts/presentation/campaign_loot_view.gd")
const RemoteArena=preload("res://scripts/presentation/campaign_arena_view.gd")
const RemoteService=preload("res://scripts/presentation/campaign_service_screen.gd")
const RemoteMarket=preload("res://scripts/presentation/campaign_market_view.gd")
const RemoteWizard=preload("res://scripts/presentation/campaign_wizard_view.gd")
var connection: RefCounted
var panel_key: String=""
var personal_pack: Node2D
var leaving: bool=false
var shown_battle_id: int=0
var network_overlay: Node2D
func input_kind() -> String:return "world_view"
func is_network_campaign() -> bool:return true
func _ready() -> void:
    process_mode=Node.PROCESS_MODE_ALWAYS
    debug_mode=false;saving_enabled=false;parse_launch_arguments=false
    journey=connection.replica
    add_to_group("moonstone_input_surfaces")
    setup_dragon_display()
    var layer:=CanvasLayer.new();layer.layer=20;add_child(layer)
    network_overlay=Node2D.new();layer.add_child(network_overlay)
    network_overlay.draw.connect(draw_network_status)
    connection.frame_received.connect(sync_view)
    connection.changed.connect(sync_view)
    sync_view()
func can_act() -> bool:
    return connection.state=="playing" and journey.party!=null and connection.seat==journey.party.active and connection.phase!="computer"
func _process(_delta: float) -> void:connection.poll()
func _physics_process(_delta: float) -> void:
    if not get_tree().paused:elapsed+=1 # Presentation-only classic map/arrival blink.
    var controls: Node=get_node("/root/MoonstoneInput")
    var direction: Vector2i=Vector2i.ZERO
    var action: String="idle"
    var accessible: bool=personal_pack==null and connection.state=="playing" and not get_tree().paused
    if accessible and connection.phase=="battle":
        if journey.combat!=null and journey.combat.human_actors.values().has(connection.seat+1):direction=controls.direction();action=controls.combat_action()
    elif accessible and connection.phase=="map" and can_act() and inventory_view==null and arrival_choices.is_empty():direction=controls.direction()
    if connection.phase=="battle" and journey.combat!=null and journey.combat.human_actors.values().has(connection.seat+1):connection.advance(direction,action)
    elif connection.phase=="map" and can_act():connection.advance(direction,action)
    if inventory_view!=null:
        if inventory_view.has_method("advance_visit"):inventory_view.advance_visit()
        inventory_view.queue_redraw()
    if henge_view!=null:henge_view.advance()
    if quest_view!=null:quest_view.advance()
    update_dragon_sprite();queue_redraw();network_overlay.queue_redraw()
func clear_panels(keep_arena: bool=false) -> void:
    for field in ["town_view","inventory_view","loot_view","henge_view","quest_view"]:
        var node: Node=get(field)
        if node!=null:node.set_process_unhandled_input(false);node.set_process_unhandled_key_input(false);remove_child(node);node.queue_free();set(field,null)
    if not keep_arena and arena!=null:
        arena.set_physics_process(false);remove_child(arena);arena.queue_free();arena=null
    arrival_choices=[]
func sync_view() -> void:
    if journey.party==null:return
    journey.read_only=not can_act()
    connection.own_inventory.read_only=not can_act() or connection.phase in ["battle","result","battle_ready","turn_ready"]
    var phase: String=connection.phase
    var group: String="battle" if phase in ["battle","battle_ready","result"] else phase
    var wizard: String="sheet" if journey.places.visit.get("phase")=="sheet" else "wizard"
    var key: String=group+":"+str(connection.replica.battle_number)+":"+journey.town_id+":"+journey.service+":"+wizard+":"+str(journey.party.active)+":"+str(can_act())
    if key!=panel_key:
        var keep: bool=arena!=null and group in ["battle","loot"] and shown_battle_id==connection.replica.battle_number
        clear_panels(keep);panel_key=key
        if group=="battle":
            if arena==null:create_arena()
            arena.show();arena.set_physics_process(true)
        elif phase=="loot":
            if arena==null:create_arena()
            arena.hide();arena.set_physics_process(false)
            loot_view=RemoteLoot.new();loot_view.journey=journey
            var player: Dictionary=journey.combat.simulation.actors[1]
            loot_view.health=player.health;loot_view.maximum=player.maximum;loot_view.daggers=player.daggers
            loot_view.finished.connect(func() -> void:connection.command("leave_loot"));add_child(loot_view)
        elif phase=="town":create_town_panel()
        elif phase=="attack":create_inventory(journey,0,true)
        elif phase=="henge":
            henge_view=HengeView.new();henge_view.journey=journey;add_child(henge_view)
        elif phase in ["quest","ending"]:
            quest_view=QuestView.new();quest_view.journey=journey
            quest_view.chosen.connect(func(action: String) -> void:
                if action=="menu" and journey.quest.ending.get("stage")=="complete":finished.emit()
            )
            add_child(quest_view)
        get_node("/root/MoonstoneInput").block_held()
    if arena!=null and journey.combat!=null:
        arena.source_fight=journey.combat;arena.render_frame()
    for node in [town_view,inventory_view,loot_view,henge_view,quest_view]:
        if node!=null:
            node.set_process_unhandled_key_input(can_act());node.set_process_unhandled_input(can_act());node.queue_redraw()
    if personal_pack!=null:personal_pack.queue_redraw()
    update_dragon_sprite();queue_redraw();network_overlay.queue_redraw()
func create_arena() -> void:
    if journey.combat==null:return
    shown_battle_id=connection.replica.battle_number
    arena=RemoteArena.new();arena.connection=connection;arena.source_fight=journey.combat
    arena.session=connection.replica.FightView.new();arena.session.simulation.apply(journey.combat.simulation.snapshot(),[])
    arena.managed_by_world=true;arena.debug_mode=false;arena.mode=&"competitive"
    arena.encounter=journey.world.lair(journey.world.active_lair).encounter
    arena.knight_kind=journey.identity.kind;arena.knight_name=journey.identity.name
    arena.actor_equipment=connection.latest.get("equipment",{}).duplicate(true)
    for id in journey.combat.simulation.actors:
        var actor: Dictionary=journey.combat.simulation.actors[id]
        if actor.kind in ["knight","black_knight"]:
            var seat: int=journey.party.active if actor.team==1 else journey.party.seat_for(journey.world.active_lair)
            if seat>=0:arena.actor_colours[id]=seat
    var backdrop: String="res://assets/classic/lairs/"+journey.world.active_lair+".png"
    if ResourceLoader.exists(backdrop):arena.background_override=load(backdrop)
    add_child(arena)
func create_inventory(model: RefCounted,tab: int,attack: bool=false) -> void:
    inventory_view=RemoteInventory.new();inventory_view.journey=model
    inventory_view.set_tab(tab)
    if inventory_view.service_screen!=null:
        inventory_view.service_screen=RemoteService.new({3:"healer",4:"tavern",5:"mystic"}[tab]);inventory_view.service_screen.journey=model
    inventory_view.finished.connect(func() -> void:
        if attack:connection.command("protection",{"use":false})
        else:connection.command("close_service")
    )
    add_child(inventory_view)
func create_town_panel() -> void:
    if journey.town_id=="wizard" and journey.places.visit.get("phase")!="sheet":
        inventory_view=RemoteWizard.new();inventory_view.journey=journey;add_child(inventory_view)
    elif journey.town_id in ["home","wizard"]:create_inventory(journey,0 if journey.town_id=="home" else 2)
    elif journey.service=="temple" and journey.town_id=="highwood":
        inventory_view=RemoteMarket.new();inventory_view.journey=journey;inventory_view.finished.connect(func() -> void:connection.command("close_service"));add_child(inventory_view)
    elif not journey.service.is_empty():create_inventory(journey,{"smith":1,"temple":2,"healer":3,"tavern":4,"mystic":5}.get(journey.service,0))
    else:
        town_view=TownView.new();town_view.journey=journey
        town_view.service_requested.connect(func(id: String) -> void:
            if id=="pack":open_pack()
            else:connection.command("service",{"id":id})
        )
        town_view.finished.connect(func() -> void:connection.command("leave_town"));add_child(town_view)
func open_pack() -> void:
    if personal_pack!=null:return
    personal_pack=RemoteInventory.new();personal_pack.journey=connection.own_inventory
    personal_pack.loot_context=true;personal_pack.set_tab(0)
    personal_pack.finished.connect(close_pack);add_child(personal_pack)
    get_node("/root/MoonstoneInput").block_held()
func close_pack() -> void:
    if personal_pack==null:return
    personal_pack.set_process_unhandled_key_input(false);personal_pack.set_process_unhandled_input(false)
    remove_child(personal_pack);personal_pack.queue_free();personal_pack=null
    get_node("/root/MoonstoneInput").block_held()
func _input(event: InputEvent) -> void:
    if get_tree().paused:return
    if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_I:
        get_viewport().set_input_as_handled()
        if personal_pack==null:open_pack()
        else:close_pack()
func _unhandled_key_input(event: InputEvent) -> void:
    if get_tree().paused:return
    if not event is InputEventKey or not event.pressed or event.echo:return
    if event.keycode==KEY_ESCAPE:
        if personal_pack!=null:close_pack()
        elif not arrival_choices.is_empty():arrival_choices=[]
        elif connection.phase in ["battle","result"] and can_act():connection.command("retreat")
        else:finished.emit()
        get_viewport().set_input_as_handled();return
    if connection.state=="paused":
        if event.keycode in [KEY_ENTER,KEY_KP_ENTER,KEY_SPACE]:connection.ready();get_viewport().set_input_as_handled()
        return
    if not can_act() and connection.phase!="battle_ready":return
    if connection.phase=="turn_ready" and event.keycode in [KEY_ENTER,KEY_KP_ENTER,KEY_SPACE,KEY_Z]:connection.command("begin_turn")
    elif connection.phase=="battle_ready" and event.keycode in [KEY_ENTER,KEY_KP_ENTER,KEY_SPACE]:connection.command("battle_ready")
    elif connection.phase=="result" and event.keycode in [KEY_ENTER,KEY_KP_ENTER,KEY_SPACE]:connection.command("result")
    elif connection.phase=="map":
        if not arrival_choices.is_empty():
            if event.keycode in [KEY_UP,KEY_DOWN]:arrival_selected=posmod(arrival_selected+(1 if event.keycode==KEY_DOWN else -1),arrival_choices.size())
            elif event.keycode in [KEY_ENTER,KEY_SPACE,KEY_Z]:connection.command("enter",{"id":arrival_choices[arrival_selected].id});arrival_choices=[]
        elif event.keycode in [KEY_ENTER,KEY_KP_ENTER,KEY_Z]:
            var rows: Array[Dictionary]=journey.arrivals()
            if rows.size()==1:connection.command("enter",{"id":rows[0].id})
            elif rows.size()>1:arrival_choices=rows;arrival_selected=0
        elif event.keycode==KEY_E:connection.command("rest")
    queue_redraw()
func _unhandled_input(event: InputEvent) -> void:
    if not event is InputEventMouseButton or not event.pressed or event.button_index!=MOUSE_BUTTON_LEFT:return
    if connection.state=="paused":connection.ready();return
    if not can_act():return
    if connection.phase=="turn_ready":connection.command("begin_turn")
    elif connection.phase=="battle_ready":connection.command("battle_ready")
    elif connection.phase=="map":
        var rows: Array[Dictionary]=journey.arrivals()
        if rows.size()==1:connection.command("enter",{"id":rows[0].id})
func map_hints() -> PackedStringArray:
    return PackedStringArray(["Arrows travel / Enter or Z enter / E end turn" if can_act() else "Watching the active knight", "I: your inventory / Esc: leave game"])
func _draw() -> void:
    super._draw()
func draw_network_status() -> void:
    if journey.party==null:return
    # A separate canvas keeps pause/readiness visible above battle/town panels.
    if connection.phase in ["map","computer","turn_ready","battle","battle_ready","result"]:
        network_overlay.draw_rect(Rect2(0,0,640,22),Color("101820"))
        network_overlay.draw_string(font,Vector2(10,16),"NETWORK / "+journey.party.players[journey.party.turn].identity.name+" / YOU: "+journey.party.players[connection.seat].identity.name,HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("ddc68c"))
    var text: String=""
    if connection.state!="playing":text="CAMPAIGN PAUSED - YOUR KNIGHT IS RESERVED"
    elif connection.phase=="battle_ready":text="ENTER: READY FOR THE KNIGHT DUEL"
    elif connection.phase=="turn_ready":text="ENTER: BEGIN YOUR TURN" if can_act() else "WAITING FOR THE ACTIVE KNIGHT"
    if not text.is_empty() and personal_pack==null:
        network_overlay.draw_rect(Rect2(62,132,516,126),Color("101820"))
        network_overlay.draw_rect(Rect2(62,132,516,126),Color("ddc68c"),false,2)
        network_overlay.draw_string(font,Vector2(85,164),text,HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("ddc68c"))
        network_overlay.draw_string(font,Vector2(85,197),connection.notice.left(52),HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color.WHITE)
        network_overlay.draw_string(font,Vector2(85,232),"I: your inventory / Esc: leave game",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color.WHITE)
func _notification(what: int) -> void:
    if what==NOTIFICATION_WM_CLOSE_REQUEST:connection.close();get_tree().quit()
