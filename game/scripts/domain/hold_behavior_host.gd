extends RefCounted

# Only this host applies a behaviour's validated intent to authoritative state.
# A registry entry can replace the ride without adding a creature dispatch case.
static func manifest(rules: Resource) -> Dictionary:
    var result: Dictionary={}
    var ids: Array=rules.hold_behaviors.keys();ids.sort()
    for id in ids:
        var behavior: Resource=rules.hold_behaviors[id]
        result[String(id)]={"api":behavior.api_version,"version":behavior.content_version}
    return result

static func valid(command: Dictionary) -> bool:
    if command.get("operation") == "wait":return command.size()==1
    if command.get("operation") not in ["release","throw"]:return false
    if typeof(command.get("clip"))!=TYPE_STRING or command.clip.is_empty():return false
    if typeof(command.get("ticks"))!=TYPE_INT or command.ticks<1 or command.ticks>3000:return false
    if command.operation=="release":return command.size()==3
    return command.size()==5 and typeof(command.get("damage"))==TYPE_INT and command.damage>=0 and command.damage<=255 and typeof(command.get("flight_ticks"))==TYPE_INT and command.flight_ticks>=1 and command.flight_ticks<=3000

static func advance(model: RefCounted,holder: Dictionary,victim: Dictionary,release_requested: bool) -> bool:
    var id: String=String(model.rules.actor_definitions[holder.kind].hold_behavior_ids.get(holder.hold_kind,""))
    if id.is_empty():return false
    var behavior: Resource=model.rules.hold_behaviors.get(id)
    if behavior==null or behavior.behavior_id!=StringName(id) or behavior.api_version!=1:return false
    var command: Dictionary=behavior.decide({"tick":model.tick,"elapsed":holder.hold_elapsed,
        "remaining":victim.grab_remaining,"release_requested":release_requested,
        "holder":{"id":holder.id,"health":holder.health},
        "victim":{"id":victim.id,"health":victim.health}}.duplicate(true))
    if not valid(command):return false # fail closed, without partial state changes
    holder.hold_elapsed+=1
    if command.operation=="wait":
        victim.grab_remaining=maxi(1,victim.grab_remaining-1)
        return true
    if command.operation=="release":
        model.RatHold.unlink(holder,victim)
        model.release_rat_perch(holder)
        holder.special_clip="";holder.rest_height=0;holder.height=0
        if holder.health>0:
            # 085D contains BOTH actors. Keep the independent knight hidden
            # through the complete five-pass drawing, avoiding duplicate bodies.
            victim.hidden_by=holder.id
            model.start_special(holder,command.clip,command.ticks)
        model.events.append({"type":"escape","actor":victim.id})
        return true
    victim.grab_remaining=0;victim.grabbed_by=0;holder.held_target=0
    var damage: int=mini(victim.health,int(command.damage))
    victim.health-=damage
    if damage>0:model.events.append({"type":"damage","actor":victim.id,"attacker":holder.id,"amount":damage,"move":"rat_hold","blocked":false})
    if victim.health>0:
        victim.hidden_by=0
        holder.leap_from_x=holder.x;holder.leap_to_x=clampi(holder.x+150*holder.facing,22,298)
        holder.leap_from_y=holder.y;holder.leap_to_y=holder.y
        holder.leap_from_height=0;holder.leap_to_height=0
        model.start_special(holder,"rat_air",command.flight_ticks)
    else:
        model.knock_down(victim,"defeat")
        victim.down_remaining=command.ticks;victim.down_duration=command.ticks
        model.events.append({"type":"down","actor":victim.id})
        model.start_special(holder,command.clip,command.ticks)
    return true
