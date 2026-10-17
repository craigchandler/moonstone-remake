extends RefCounted

# Retail drawing passes mapped to the native six-tick creature cadence.
# These are source-derived; exact scheduling still needs original comparison.
const INTRO: int=30
const LOOP: int=12
const COUNTER: int=30
const RELEASE: int=18

static func duration(clip: String) -> int:
    return {"rat_squeeze":INTRO,"rat_squeeze_loop":LOOP,"rat_squeeze_hit":COUNTER}.get(clip,LOOP)

static func unlink(holder: Dictionary,victim: Dictionary) -> void:
    if victim.hidden_by==holder.id:victim.hidden_by=0
    if victim.grabbed_by==holder.id:victim.grabbed_by=0;victim.grab_remaining=0
    holder.held_target=0

static func advance(model: RefCounted,holder: Dictionary,victim: Dictionary,pressed: bool) -> bool:
    if holder.hold_kind!="squeeze":return false
    if holder.health<=0:
        unlink(holder,victim)
        model.release_rat_perch(holder)
        return true
    holder.hold_elapsed+=1
    holder.rat_phase_elapsed+=1
    # No fabricated600tick release. The squeeze ends through a kill/rescue.
    victim.grab_remaining=1
    if holder.rat_phase_elapsed<duration(holder.special_clip):return true
    holder.rat_phase_elapsed=0
    model.events.append({"type":"hold_cycle","actor":holder.id})
    if pressed:
        var amount: int=mini(holder.health,(int(model.rules.moves.swing.damage)+int(victim.damage_bonus))<<int(victim.moon_damage_shift))
        holder.health-=amount
        model.events.append({"type":"damage","actor":holder.id,"attacker":victim.id,"amount":amount,"move":"rat_counter","blocked":false})
        if holder.health>0:
            holder.special_clip="rat_squeeze_hit"
            return true
        # Source casterDropVictim selects0868, not the ordinary ground death.
        # Keep the dying Ratman's elevated placement until its18tick release ends.
        var height: int=holder.rest_height
        unlink(holder,victim)
        model.knock_down(holder,"defeat_counter")
        holder.rest_height=height;holder.height=height
        holder.visual_kind="ratman";holder.defeat_clip="rat_release"
        holder.down_duration=RELEASE;holder.down_remaining=RELEASE
        model.events.append({"type":"escape","actor":victim.id})
        model.events.append({"type":"down","actor":holder.id})
        return true
    holder.special_clip="rat_squeeze_loop"
    var amount: int=mini(1,int(victim.health))
    victim.health-=amount
    model.events.append({"type":"damage","actor":victim.id,"attacker":holder.id,"amount":amount,"move":"rat_hold","blocked":false})
    if victim.health>0:return true
    # Retain the existing finite lethal composite and result wait.
    unlink(holder,victim)
    model.knock_down(victim,"defeat")
    victim.hidden_by=holder.id
    victim.down_duration=72;victim.down_remaining=72
    holder.terminal_clip="rat_squeeze_finish"
    model.start_special(holder,"rat_squeeze_finish",72)
    model.events.append({"type":"down","actor":victim.id})
    return true
