extends RefCounted

# Deterministic acceptance/review fixture. Positions, equipment and battle
# outcomes are staged; movement, UI, settlement and Continue use real paths.
var results: Dictionary={}
var seen: Dictionary={}
var initial_chests: Dictionary={}

func advance(host: Node) -> void:
    var j: RefCounted=host.journey
    var mode: String=host.rivals_demo
    if host.elapsed==1:
        initial_chests=j.lair_loot.duplicate(true)
        results.initial=j.checkpoint()
        if mode=="round":j.rest()
        else:
            var row: Dictionary=j.rivals.records[1]
            j.world.position=row.position
            row.character.armour="chainmail";row.character.weapon="broad_sword"
            row.inventory.items={"ring_of_protection":1,"healing_potion":2}
            row.character.health=47;row.character.daggers=4
            if mode=="final":row.character.lives=1;row.inventory.gold=70
            if mode=="protection":j.inventory.items.scroll_of_protection=1
            j.begin_rival_encounter(row.id,true)
            if j.combat!=null:host.show_lair();host.arena.set_physics_process(false)
    if mode=="round":
        seen[j.rivals.active]=true
        if host.elapsed==60:
            var save: Dictionary=j.checkpoint()
            results.mid=save
            results.restored=j.restore_checkpoint(JSON.parse_string(JSON.stringify(save))) and j.checkpoint()==save
        return
    if mode=="protection":
        if host.elapsed==60:
            var event:=InputEventKey.new();event.keycode=KEY_SPACE;event.pressed=true
            host.get_viewport().push_input(event,true)
        if host.elapsed==120 and host.inventory_view!=null:
            var view: Node=host.inventory_view
            var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true
            event.position=view.row_rect(view.selected).get_center()
            host.get_viewport().push_input(event,true)
        return
    if host.elapsed==80:
        if mode=="defeat":j.combat.simulation.actors[1].health=0
        else:
            for actor in j.combat.simulation.actors.values():
                if actor.team==2:actor.health=0;actor.down_remaining=0
            host.show_loot()
        results.settled=j.checkpoint()
    if host.elapsed==130 and mode!="defeat":
        var copy: RefCounted=load("res://scripts/session/journey_session.gd").new(host.definition,host.rules,2)
        results.restored=copy.restore_checkpoint(JSON.parse_string(JSON.stringify(j.checkpoint()))) and copy.checkpoint()==j.checkpoint()
    if host.elapsed==190 and mode!="defeat":
        if host.loot_view!=null:
            var view: Node=host.loot_view
            view.selected=view.rows().find("ring_of_protection")
            view.take_selected()
    if host.elapsed==240:host.return_to_map(false)
    if host.elapsed==260 and mode=="final":j.world.position+=Vector2i(20,20)

func finish(host: Node) -> void:
    var j: RefCounted=host.journey
    results.final=j.checkpoint()
    var valid: bool=not j.validate_checkpoint(results.final).is_empty()
    if host.rivals_demo=="round":
        valid=valid and seen.has(1) and seen.has(2) and seen.has(3) and seen.has(0) and results.restored
        valid=valid and j.day==2 and j.turn_pending and j.rivals.active==0 and j.lair_loot==initial_chests
    elif host.rivals_demo=="protection":
        valid=valid and host.inventory_view==null and host.arena==null and j.pending_attack=="" and not j.inventory.items.has("scroll_of_protection") and j.rivals.records[1].character.lives==5
    elif host.rivals_demo=="defeat":
        valid=valid and j.character.lives==4 and j.rivals.records[1].character.experience==1
    else:
        valid=valid and results.restored and j.rivals.records[1].character.lives==(0 if host.rivals_demo=="final" else 4) and j.inventory.items.get("ring_of_protection",0)==1
    if not valid:push_error("Rival fixture failed: "+JSON.stringify(results));host.get_tree().quit(1);return
    print("RIVALS_STATE=",JSON.stringify(results))
    print("PASS: three rival turns/icons, persistent kit/duel settlement and Protection choice: ",host.rivals_demo)
    host.get_tree().quit()
