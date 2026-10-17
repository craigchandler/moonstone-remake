extends RefCounted

# Reproducible commands and staged entry positions, not an AI playthrough.
var choice:String="guard_close"
var mirror:bool=false
var tick:int=0
var checked:Dictionary={}
var kind:String=""
var timeline:Array=[]
var holds:Array=[]
var damage:Array=[]
var released:Array=[]
var initial_x:int=0
var initial_y:int=166
var facing:int=1
var first_free:int=-1
var last_stage:String="?"

func length()->int:return 300

func reset(session:RefCounted)->void:
    kind=choice.trim_prefix("guard_")
    var cooperative:bool=kind in ["rescue_close","rescue_far","rescue_crush","rescue_dead","interrupt","late_hit"]
    session.start(&"cooperative" if cooperative else &"competitive",&"guardian_fight",{"count":1,"concurrent":1})
    var sim:RefCounted=session.simulation;sim.spawn_remaining=0
    var holder:Dictionary=sim.actors[10];var victim:Dictionary=sim.actors[1]
    for actor in sim.actors.values():actor.entering=false;actor.cooldown_remaining=10000;actor.y=166
    holder.x=60;holder.facing=1;victim.x=185;victim.facing=-1
    if kind in ["far","overlap"]:victim.x=195
    if kind=="miss_low":victim.x=179
    if kind in ["double","rescue_far"]:holder.x=160;victim.x=280
    if kind.begins_with("crush") or kind in ["rescue_crush","rescue_dead"]:victim.x=holder.x+115
    if kind in ["crush_dead","rescue_dead"]:victim.health=10
    if kind=="crush_zero":holder.x=137;holder.facing=-1;victim.x=22;victim.facing=1
    if cooperative:sim.actors[2].x=victim.x+5;sim.actors[2].facing=-1
    if mirror:
        for actor in sim.actors.values():actor.x=320-actor.x;actor.facing=-actor.facing
    initial_x=victim.x;facing=holder.facing;initial_y=victim.y
    holder.cooldown_remaining=0
    session.command(10,holder.owner,Vector2i.ZERO,"guardian_strike" if kind.begins_with("crush") or kind in ["rescue_crush","rescue_dead"] else "guardian_grab")

func advance(session:RefCounted)->void:
    if tick==0:reset(session)
    var sim:RefCounted=session.simulation;var victim:Dictionary=sim.actors[1];var holder:Dictionary=sim.actors[10]
    if (kind=="far" and tick>=1 and tick<=5) or (kind=="escape" and tick>=1 and tick<=15):
        session.command(1,1,Vector2i(facing,0),"idle")
    elif kind=="depth" and tick>=1 and tick<=8:session.command(1,1,Vector2i.UP,"idle")
    elif not holds.is_empty() or kind.begins_with("crush") or kind in ["rescue_crush","rescue_dead"]:
        session.command(1,1,Vector2i.UP,"block")
    var attack_tick:int={"rescue_close":31,"rescue_far":52,"rescue_crush":20,"rescue_dead":20,"interrupt":5,"late_hit":45}.get(kind,-1)
    if tick==attack_tick:
        sim.actors[2].cooldown_remaining=0
        session.command(2,sim.actors[2].owner,Vector2i.ZERO,"lunge",-facing)
    var was_hidden:bool=victim.hidden_by==10
    sim.advance()
    for event in sim.events:
        if event.actor!=1:continue
        if event.type=="hold":holds.append(tick)
        if event.type=="damage":damage.append({"tick":tick,"amount":event.amount})
    if was_hidden and victim.hidden_by==0:released.append(tick)
    var stage:String=holder.interaction.get("stage","")
    if stage!=last_stage:timeline.append([tick,stage]);last_stage=stage
    if not holds.is_empty() and victim.health>0 and victim.hidden_by==0 and victim.reaction_remaining==0 and victim.y<initial_y and first_free<0:first_free=tick
    tick+=1

func verify(session:RefCounted)->bool:
    var sim:RefCounted=session.simulation;var victim:Dictionary=sim.actors[1];var holder:Dictionary=sim.actors[10]
    var crushed:bool=kind.begins_with("crush") or kind in ["rescue_crush","rescue_dead"]
    var dead:bool=kind in ["crush_dead","rescue_dead"]
    checked.links=victim.hidden_by==0 and victim.grabbed_by==0 and victim.grab_remaining==0 and holder.held_target==0 and holder.interaction.is_empty()
    checked.health=victim.health==(0 if dead else (10 if crushed else 20))
    checked.damage=damage==[{"tick":12,"amount":10}] if crushed else damage.is_empty()
    checked.ending=(victim.down_remaining==0 if dead else (first_free>=0 or holds.is_empty())) and victim.motion.is_empty()
    if kind in ["close","overlap","depth"]:checked.schedule=timeline==[[0,"windup"],[30,"grab_close"],[42,"release_close"],[60,"miss_far"],[66,"release_far"],[84,""]] and holds==[30] and released==[42]
    elif kind=="far":checked.schedule=timeline==[[0,"windup"],[30,"miss_close"],[36,"release_close"],[54,"grab_far"],[60,"release_far"],[78,""]] and holds==[54] and released==[60]
    elif kind in ["miss_low","escape"]:checked.schedule=timeline==[[0,"windup"],[30,"miss_close"],[36,"release_close"],[54,"miss_far"],[60,"release_far"],[78,""]] and holds.is_empty()
    elif kind=="double":checked.schedule=timeline==[[0,"windup"],[30,"grab_close"],[42,"release_close"],[60,"grab_far"],[66,"release_far"],[84,""]] and holds==[30,60] and released==[42,66]
    elif kind.begins_with("crush"):checked.schedule=timeline==[[0,"crush"],[96,""]] and holds==[12] and released==[90]
    else:checked.interrupted=holder.health==136 and (holds.is_empty() if kind=="interrupt" else not holds.is_empty())
    if kind=="rescue_far":checked.rescued_art=holds==[30,60] and victim.visual_kind.is_empty() and victim.reaction.is_empty()
    if crushed and kind.begins_with("crush"):
        var x:int=holder.x+137*facing
        if x>=320:x=319
        if x<0:x=1
        checked.position=victim.x==x and victim.facing==-facing and (victim.defeat_clip=="defeat" if dead else victim.reaction.is_empty())
    for key in checked:
        if not checked[key]:push_error("Guardian fixture failed "+choice+"/"+key+" timeline="+str(timeline));return false
    return true
