extends RefCounted

# Named native stages, selected from numeric rules. No original script executes.
static func stage(model:RefCounted,holder:Dictionary,name:String)->void:
    model.Finishers.stage(holder,name,model.rules.guardian.duration(name))
    holder.visual_kind="guardian_finishes"

static func begin(model:RefCounted,holder:Dictionary,move:String)->bool:
    var victim:Dictionary=model.nearest_opponent(holder)
    if victim.is_empty() or not holder.interaction.is_empty():return false
    holder.interaction={"kind":"guardian","flow":"crush" if move=="guardian_strike" else "grab","victim":victim.id}
    stage(model,holder,"crush" if move=="guardian_strike" else "windup")
    return true

static func link(model:RefCounted,holder:Dictionary,victim:Dictionary,restart_attacker:bool=true)->void:
    holder.held_target=victim.id
    victim.grabbed_by=holder.id;victim.grab_remaining=1;victim.hidden_by=holder.id
    victim.action="idle";victim.remaining=0;victim.guarding=false
    victim.reaction="";victim.reaction_remaining=0;victim.stagger_remaining=0
    if victim.health>0:victim.visual_kind=""
    victim.motion={};victim.rest_height=0;victim.height=0
    if victim.health<=0:victim.down_remaining=maxi(2,victim.down_remaining)
    model.events.append({"type":"hold","actor":victim.id,"attacker":holder.id,"kind":"guardian","restart_attacker":restart_attacker})

static func unhold(holder:Dictionary,victim:Dictionary)->void:
    # A late stage must never clear a hold which now belongs to another creature.
    if victim.hidden_by==holder.id:victim.hidden_by=0
    if victim.grabbed_by==holder.id:victim.grabbed_by=0;victim.grab_remaining=0
    holder.held_target=0

static func capture(model:RefCounted,holder:Dictionary,victim:Dictionary,name:String="grab_close")->bool:
    if holder.health<=0 or victim.hidden_by!=0:return false
    if holder.interaction.is_empty():holder.interaction={"kind":"guardian","flow":"grab","victim":victim.id}
    link(model,holder,victim)
    stage(model,holder,name)
    return true

static func gate(model:RefCounted,holder:Dictionary,victim:Dictionary,far:bool)->void:
    var content:Resource=model.rules.guardian
    var distance:int=abs(holder.x-victim.x)
    var low:int=content.far_min if far else content.close_min
    var high:int=content.far_max if far else content.close_max
    if victim.hidden_by==0 and distance>=low and distance<=high:
        capture(model,holder,victim,"grab_far" if far else "grab_close")
    else:stage(model,holder,"miss_far" if far else "miss_close")

static func hop(model:RefCounted,holder:Dictionary,victim:Dictionary)->void:
    unhold(holder,victim)
    if victim.health>0:model.start_hop_recovery(victim,holder.facing)
    else:
        victim.visual_kind="death_knight";victim.defeat_clip="hop"
        victim.down_duration=model.rules.death_frames.duration("death_knight","hop")
        victim.down_remaining=victim.down_duration
        model.Knockback.start(victim,holder.facing,model.rules.knockback,model.tick)

static func finish(model:RefCounted,holder:Dictionary,victim:Dictionary)->void:
    unhold(holder,victim)
    holder.interaction={};holder.special_clip="";holder.visual_kind=""
    holder.cooldown_remaining=model.rules.actor_definitions[holder.kind].attack_cooldown_ticks

static func release_crush(model:RefCounted,holder:Dictionary,victim:Dictionary)->void:
    unhold(holder,victim)
    victim.x=holder.x+model.rules.guardian.release_offset*holder.facing
    if victim.x>=320:victim.x=319
    if victim.x<0:victim.x=1
    victim.y=holder.y;victim.facing=-holder.facing
    if victim.health>0:
        victim.action="idle";victim.remaining=0;victim.reaction="";victim.reaction_remaining=0
        victim.stagger_remaining=0;victim.visual_kind="";victim.motion={}
    else:model.knock_down(victim,"defeat")

static func advance(model:RefCounted,holder:Dictionary,victim:Dictionary)->void:
    var sequence:Dictionary=holder.interaction
    sequence.elapsed+=1;holder.hold_elapsed=sequence.elapsed
    if victim.health<=0 and victim.hidden_by==holder.id:victim.down_remaining=maxi(2,victim.down_remaining)
    var content:Resource=model.rules.guardian
    if sequence.flow=="crush":
        if sequence.elapsed==content.crush_damage_tick:
            if victim.hidden_by!=0:
                finish(model,holder,victim);return
            var amount:int=mini(victim.health,content.crush_damage)
            if amount>0:
                victim.health-=amount;victim.flash=7
                if victim.health==0:model.knock_down(victim,"defeat")
                model.events.append({"type":"damage","actor":victim.id,"attacker":holder.id,"amount":amount,"move":"guardian_strike","blocked":false})
                if victim.health==0:model.events.append({"type":"down","actor":victim.id})
            link(model,holder,victim,false)
        if sequence.elapsed==content.crush_release_tick:release_crush(model,holder,victim)
        if sequence.elapsed>=sequence.duration:finish(model,holder,victim)
        return
    if sequence.elapsed<sequence.duration:return
    match sequence.stage:
        "windup":gate(model,holder,victim,false)
        "grab_close","miss_close":
            var held:bool=sequence.stage=="grab_close"
            stage(model,holder,"release_close")
            if held:hop(model,holder,victim)
        "release_close":gate(model,holder,victim,true)
        "grab_far","miss_far":
            var held:bool=sequence.stage=="grab_far"
            stage(model,holder,"release_far")
            if held:hop(model,holder,victim)
        "release_far":finish(model,holder,victim)
