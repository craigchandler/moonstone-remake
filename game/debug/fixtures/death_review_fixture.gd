extends RefCounted

# Explicit visual fixture: stages source-derived deaths, not an AI playthrough.
var choice:String="audit_ratman~defeat_heavy"
var mirror:bool=false
var tick:int=0
var checked:Dictionary={}
var kind:String=""
var clip:String=""
var target:int=10
func length()->int:
    return 450
func advance(session:RefCounted)->void:
    if tick==0:
        var parts:PackedStringArray=choice.trim_prefix("audit_").split("~")
        kind=parts[0];clip=parts[1]
        var encs:Dictionary={"trogg_spear":"spear_lair","trogg_axe":"axe_lair","trogg_hammer":"hammer_lair","giant_troll":"troll_lair","balok":"balok_lair","ratman":"rat_lair","mudman":"mud_lair","dragon":"dragon_fight","guardian":"guardian_fight","black_knight":"black_knight_fight","knight":"duel"}
        var enc:String=encs.get(kind,"rat_lair")
        if kind in ["burn","bite"]:enc="dragon_fight"
        if kind=="guardian_kill":enc="guardian_fight"
        session.start(&"competitive",StringName(enc),{"count":1,"concurrent":1})
        var sim:RefCounted=session.simulation;sim.spawn_remaining=0
        for id in sim.actors.keys():
            if id not in [1,10] and kind!="knight":sim.actors.erase(id)
        for actor in sim.actors.values():
            actor.x=210 if actor.id==1 else 110;actor.y=166;actor.facing=-1 if actor.id==1 else 1
            actor.entering=false;actor.cooldown_remaining=10000
            if actor.kind=="mudman":actor.interaction={};actor.visual_kind=""
            if mirror:actor.x=320-actor.x;actor.facing=-actor.facing
        target=1 if kind in ["knight","rat_victim","rat_throw","rat_squeeze","burn","bite","guardian_kill"] else 10
        var victim:Dictionary=sim.actors[target]
        if kind in ["rat_throw","rat_squeeze"]:
            victim.health=1
            sim.start_rat_hold(sim.actors[10],victim,"ride" if kind=="rat_throw" else "squeeze",1 if kind=="rat_throw" else 90)
        else:
            victim.health=0;sim.knock_down(victim,clip if kind in encs else "defeat")
            if kind=="rat_victim":sim.select_player_death(victim,sim.actors[10],"rat_strike" if clip=="strike" else "rat_bite")
            if kind in ["burn","bite"]:sim.dragon_finish(sim.actors[10],victim,"dragon_breath" if kind=="burn" else "dragon_bite")
            if kind=="guardian_kill":sim.Finishers.begin(sim,sim.actors[10],victim,"guardian")
    session.simulation.advance()
    tick+=1
func verify(session:RefCounted)->bool:
    var victim:Dictionary=session.simulation.actors[target]
    checked.death=victim.health==0 and victim.down_remaining==0
    checked.links=victim.hidden_by==0 and victim.grab_remaining==0
    if kind=="bite":checked.consumed=victim.vanished
    if kind.begins_with("rat_") and kind!="rat_victim":checked.remains=victim.defeat_clip==("remains_throw" if kind=="rat_throw" else "remains_squeeze")
    for key in checked:
        if not checked[key]:push_error("Death review failed "+choice+"/"+key);return false
    return true
