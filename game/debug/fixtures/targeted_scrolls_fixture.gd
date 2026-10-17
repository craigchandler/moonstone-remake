extends RefCounted
# Equipment, starting date, flight contact and arena outcome are staged. Input,
# targeting, transfer, save validation and turn settlement use production paths.
var results: Dictionary={}
func key(host: Node,code: Key) -> void:
    var e:=InputEventKey.new();e.keycode=code;e.pressed=true
    host.get_viewport().push_input(e,true);e=e.duplicate();e.pressed=false;host.get_viewport().push_input(e,true)
func click(host: Node,point: Vector2) -> void:
    var e:=InputEventMouseButton.new();e.position=point;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=true
    host.get_viewport().push_input(e,true);e=e.duplicate();e.pressed=false;host.get_viewport().push_input(e,true)
func advance(host: Node) -> void:
    var j: RefCounted=host.journey
    var mode: String=host.scrolls_demo
    if host.elapsed==1:
        j.day=9 if mode in ["wyrm","catch","recover"] else 1
        j.inventory.items={"scroll_of_acquisition":2,"scroll_of_the_wyrm":2,"healing_potion":1}
        var row: Dictionary=j.rivals.records[1]
        row.inventory.items={"ring_of_protection":1,"healing_potion":2,"sword_of_sharpness":1};row.character.health=40;row.inventory.gold=41
        results.initial=j.checkpoint()
        if mode=="recover":
            j.quest.valley_stone=4;j.awarded_lairs.valley_guardian=true;j.world.cleared.valley_guardian=true;row.stones=4
            j.dragon_takes(row.inventory,row,false)
            j.world.active_lair="roaming_dragon";j.start_site_combat();host.show_lair();host.arena.set_physics_process(false)
    if mode=="recover":
        if host.elapsed==90:
            for a in j.combat.simulation.actors.values():
                if a.team==2:a.health=0;a.down_remaining=0
            host.show_loot();results.loot=j.checkpoint()
        if host.elapsed==160:
            var view: Node=host.loot_view
            click(host,view.row_rect(view.rows().find(j.quest_rules.stone_ids[2])).get_center())
        return
    if host.elapsed==20:
        key(host,KEY_I)
        var view: Node=host.inventory_view
        view.selected=view.rows().find("scroll_of_the_wyrm" if mode in ["wyrm","catch"] else "scroll_of_acquisition")
        click(host,view.row_rect(view.selected).get_center())
        results.before_choice=j.checkpoint()
    if host.elapsed==60:key(host,KEY_RIGHT)
    if host.elapsed==100:
        if mode=="cancel":key(host,KEY_ESCAPE)
        elif mode in ["wyrm","catch"]:key(host,KEY_ENTER)
        else:
            var view: Node=host.inventory_view.target_view
            click(host,view.row_rect(view.rows().find("ring_of_protection")).get_center())
        results.confirmed=j.checkpoint()
        var copy: RefCounted=load("res://scripts/session/journey_session.gd").new(host.definition,host.rules,2)
        results.restored=copy.restore_checkpoint(JSON.parse_string(JSON.stringify(results.confirmed))) and copy.checkpoint()==results.confirmed
    if host.elapsed==140:key(host,KEY_ESCAPE)
    if mode=="catch":
        if host.elapsed==160:j.rest()
        if host.elapsed==180:
            j.rivals.active=2;j.rivals.clear_path();j.rivals.target="player";j.rivals.goal=j.world.position;j.rivals.budget=96;j.rivals.walk.assign([100,10,-1,1,100,0])
            j.world.dragon.active=true;j.world.dragon.target=2;j.world.dragon.position=j.rivals.records[1].position+Vector2i(10,0)
        if host.elapsed==182:results.caught=j.checkpoint()
func finish(host: Node) -> void:
    var j: RefCounted=host.journey
    results.final=j.checkpoint()
    var valid: bool=not j.validate_checkpoint(results.final).is_empty()
    match host.scrolls_demo:
        "acquire":valid=valid and results.restored and j.inventory.items.get("ring_of_protection",0)==1 and j.inventory.items.scroll_of_acquisition==1 and j.rivals.records[1].character.health==20
        "cancel":valid=valid and results.restored and results.before_choice==results.confirmed
        "wyrm":valid=valid and results.restored and j.dragon_order==2 and j.inventory.items.scroll_of_the_wyrm==1 and j.world.dragon.target==2
        "catch":valid=valid and results.restored and results.caught.rivals.records[1].character.lives==4 and j.rivals.records[1].character.lives==4 and j.dragon_order==-1
        "recover":valid=valid and j.quest.stones==4 and j.lair_loot.roaming_dragon.stones==0 and j.loot_open
    if not valid:push_error("Targeted scroll fixture failed: "+JSON.stringify(results));host.get_tree().quit(1);return
    print("SCROLLS_STATE=",JSON.stringify(results))
    print("PASS: production targeted scroll and Dragon fixture: ",host.scrolls_demo)
    host.get_tree().quit()
