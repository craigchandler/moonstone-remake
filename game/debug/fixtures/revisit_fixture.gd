extends RefCounted

# Staged results exercise the actual entry, settlement, menu and Continue paths.
# This fixture is not a normal-AI/human campaign playthrough.
var results: Dictionary={}

func freeze_arena(host: Node) -> void:
    if host.arena!=null:host.arena.set_physics_process(false)

func win(host: Node) -> void:
    host.journey.combat.simulation.spawn_remaining=0
    for actor in host.journey.combat.simulation.actors.values():
        if actor.team==2:actor.health=0
    host.journey.prepare_loot()

func advance(host: Node) -> void:
    var j: RefCounted=host.journey
    var site: Dictionary=host.definition.lairs[0]
    var enabled: bool=host.revisit_demo!="off"
    match host.elapsed:
        1:
            j.world.position=site.position
            j.lair_loot[site.id]={"kind":3,"gold":12,"keys":0,"items":{"healing_potion":2}}
            host.enter_location(site.id);freeze_arena(host);win(host);host.show_loot()
            results.first=j.checkpoint()
        30:
            j.take_loot("gold");j.take_loot("healing_potion");host.return_to_map(false)
            results.left=j.checkpoint()
        45:
            host.show_menu(j.checkpoint());host.menu_view.activate("options")
        65:
            if enabled:host.menu_view.activate("revisit")
        90:
            host.menu_view.activate("back");host.menu_choice("continue")
        110:
            host.enter_location(site.id);freeze_arena(host)
            results.entered_battle=not j.loot_open and j.combat.simulation.outcome()=="ongoing"
            results.entered_xp=j.character.experience
            results.entered=j.checkpoint()
        135:
            if host.revisit_demo=="resume":
                var saved: Dictionary=j.checkpoint()
                host.return_to_map(false)
                results.resumed_entry=j.restore_checkpoint(JSON.parse_string(JSON.stringify(saved)))
                host.enter_location(site.id);freeze_arena(host)
        155:
            if host.revisit_demo=="loss":
                j.combat.simulation.actors[1].health=0;host.return_to_map(false)
            elif host.revisit_demo=="retreat":host.return_to_map(false)
            elif enabled:win(host);host.show_loot()
        175:
            results.after=j.checkpoint()
            if host.revisit_demo in ["on","resume"]:
                var copy: RefCounted=load("res://scripts/session/journey_session.gd").new(host.definition,host.rules,2)
                results.resumed_loot=copy.restore_checkpoint(JSON.parse_string(JSON.stringify(j.checkpoint())))
                copy.prepare_loot();copy.settle_battle()
                results.continued_xp=copy.character.experience
        190:
            if host.revisit_demo not in ["loss","retreat"]:host.return_to_map(true)
        205:host.show_menu(j.checkpoint())
    host.queue_redraw()

func finish(host: Node) -> void:
    var j: RefCounted=host.journey
    results.final=j.checkpoint()
    var won_repeat: bool=host.revisit_demo in ["on","resume"]
    var valid: bool=results.first.character.experience==1 and results.left.character.experience==1 and results.left.lair_loot[host.definition.lairs[0].id].items=={"healing_potion":1}
    valid=valid and results.entered_battle==(host.revisit_demo!="off") and results.entered_xp==1 and j.revisit_battles==(host.revisit_demo!="off")
    valid=valid and j.character.experience==(2 if won_repeat else 1) and j.character.lives==(4 if host.revisit_demo=="loss" else 5)
    valid=valid and j.has_treasure(host.definition.lairs[0].id)==(host.revisit_demo in ["loss","retreat"])
    if won_repeat:valid=valid and results.resumed_loot and results.continued_xp==2
    if host.revisit_demo=="resume":valid=valid and results.resumed_entry
    if not valid:push_error("Revisit fixture failed: "+JSON.stringify(results));host.get_tree().quit(1);return
    print("REVISIT_STATE=",JSON.stringify(results))
    print("PASS: saved optional lair refights, exact victory XP, retained treasure, loss/retreat and menu/Continue")
    host.get_tree().quit()
