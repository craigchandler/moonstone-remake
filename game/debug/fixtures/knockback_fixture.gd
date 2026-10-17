extends "res://debug/fixtures/hit_recovery_fixture.gd"

var direction:int=1
var origin_x:int=0
var samples:Array=[]
var sample_ticks:Array=[]
var started:int=-1
var lethal:bool=false
var edge:bool=false

func length()->int:return 300

func reset(session:RefCounted)->void:
    var requested:String=choice
    var parts:PackedStringArray=choice.trim_prefix("knock_").split("~")
    var kind:String=parts[0];lethal=parts[1] in ["dead","edge_dead"];edge=parts[1].begins_with("edge")
    var moves:Dictionary={"troll":"troll_sweep","balok":"balok_swipe","guardian":"guardian_lunge","guardian_release":"guardian_grab","dragon":"dragon_foot","fire":"ground_fire"}
    choice="recover_"+kind+"~"+moves[kind]
    super.reset(session);choice=requested
    var sim:RefCounted=session.simulation;var victim:Dictionary=sim.actors[1];var source:Dictionary=sim.actors[10]
    direction=1 if kind in ["dragon","fire"] else source.facing
    if edge:
        victim.x=40 if mirror else 290
        source.x=victim.x-140*direction
    origin_x=victim.x
    if lethal:victim.health=1;initial_health=1

func advance(session:RefCounted)->void:
    super.advance(session)
    var actor:Dictionary=session.simulation.actors[1]
    if tick==1 and lethal and choice.begins_with("knock_guardian_release"):
        # Source E5/E7 checks precede its target-alive check. Stage a fall only
        # after the normal command committed its windup, without inventing damage
        # for the damage-free capture itself.
        actor.health=0;session.simulation.knock_down(actor,"defeat");initial_health=0
    var hopping:bool=actor.reaction=="hop" or (actor.health==0 and actor.defeat_clip=="hop" and actor.hidden_by==0)
    if started<0 and hopping:started=tick-1
    if started>=0:
        samples.append(actor.x);sample_ticks.append(tick-1-started)

func verify(session:RefCounted)->bool:
    var actor:Dictionary=session.simulation.actors[1]
    checked.contact=seen.get("hold",false) and seen.get("damage",0)==0 if choice.begins_with("knock_guardian_release") else seen.get("damage",0)==1
    checked.path=started>=0 and samples.size()>54 and actor.motion.is_empty()
    var x:int=origin_x
    var step:int=0
    for n in samples.size():
        var elapsed:int=sample_ticks[n]
        while step<4 and step*6<=elapsed:
            var front:int=x+25*direction
            if front<=320 if direction>0 else front>=10:x+=[30,25,20,20][step]*direction
            step+=1
        if samples[n]!=x:checked.path=false
    checked.landing=actor.x==x and actor.y<=recovery_y and actor.height==0
    checked.ending=actor.health==0 and actor.down_remaining==0 if lethal else actor.health>0 and actor.reaction_remaining==0
    checked.facing=actor.facing==-direction
    for key in checked:
        if not checked[key]:push_error("Knockback fixture failed "+choice+"/"+key);return false
    return true
