extends RefCounted

# Named native interactions, independent of the classic artwork and its importer.
# A holder owns the clock; the linked victim never drives a second copy of it.
static func stage(holder: Dictionary, name: String, duration: int) -> void:
    holder.interaction.stage = name
    holder.interaction.elapsed = 0
    holder.interaction.duration = duration
    holder.special_clip = name
    holder.hold_elapsed = 0
    holder.action = "idle"
    holder.remaining = 0
    holder.reaction_remaining = 0
    holder.guarding = false

static func begin(model: RefCounted, holder: Dictionary, victim: Dictionary, kind: String) -> bool:
    if holder.health <= 0 or not holder.interaction.is_empty() or holder.held_target != 0 or victim.hidden_by != 0: return false
    if kind=="guardian":return model.Guardian.capture(model,holder,victim)
    var content: Resource = model.rules.finishes
    holder.interaction = {"kind":kind,"victim":victim.id}
    holder.held_target = victim.id
    victim.grabbed_by = holder.id
    victim.grab_remaining = 1
    victim.hidden_by = holder.id
    victim.action = "idle"
    victim.remaining = 0
    victim.guarding = false
    victim.reaction_remaining = 0
    victim.motion={}
    victim.rest_height = 0
    holder.rest_height = 0
    holder.height = 0
    match kind:
        "spear":
            holder.visual_kind = "spear_finishes"
            stage(holder,"impale",content.spear_impale_ticks)
            victim.down_remaining = content.spear_impale_ticks
            victim.down_duration = victim.down_remaining
        "balok":
            holder.visual_kind = "balok_finishes"
            stage(holder,"lift",content.balok_lift_ticks)
            if victim.health <= 0:
                victim.down_remaining = content.balok_lift_ticks+content.balok_shake_ticks+content.balok_eat_a_ticks
                victim.down_duration = victim.down_remaining
        "mud":
            holder.visual_kind = "mud_finishes"
            stage(holder,"carry",content.mud_carry_ticks)
            victim.grab_remaining = content.mud_carry_ticks
    model.events.append({"type":"hold","actor":victim.id,"attacker":holder.id,"kind":kind})
    return true

static func release(model: RefCounted, holder: Dictionary, victim: Dictionary) -> void:
    victim.hidden_by = 0
    victim.grabbed_by = 0
    victim.grab_remaining = 0
    victim.stagger_remaining = victim.reaction_remaining if victim.reaction=="hop" else 0
    holder.held_target = 0
    holder.interaction = {}
    holder.special_clip = ""
    holder.visual_kind = ""
    holder.cooldown_remaining = model.rules.actor_definitions[holder.kind].attack_cooldown_ticks

static func kill(model: RefCounted, holder: Dictionary, victim: Dictionary, duration: int) -> void:
    if victim.health > 0:
        var amount: int = victim.health
        victim.health = 0
        model.knock_down(victim,"defeat")
        model.events.append({"type":"damage","actor":victim.id,"attacker":holder.id,"amount":amount,"move":"finish","blocked":false})
        model.events.append({"type":"down","actor":victim.id})
    victim.hidden_by = holder.id
    victim.grabbed_by = holder.id
    victim.grab_remaining = 1
    victim.down_remaining = duration
    victim.down_duration = duration

static func appear(model: RefCounted, mud: Dictionary) -> void:
    var victim: Dictionary = model.nearest_opponent(mud)
    if victim.is_empty(): return
    mud.x = victim.x+75 if victim.x<160 else victim.x-75
    mud.y = victim.y
    mud.facing = -1 if victim.x<160 else 1
    mud.visual_kind = "mud_finishes"
    mud.interaction = {"kind":"emerge","victim":victim.id}
    stage(mud,"appear",model.rules.finishes.mud_appear_ticks)

static func interrupt(model: RefCounted, holder: Dictionary) -> void:
    if holder.interaction.is_empty(): return
    var victim: Dictionary = model.actors.get(holder.interaction.get("victim",0),{})
    if not victim.is_empty() and victim.hidden_by == holder.id:
        release(model,holder,victim)
        if victim.health<=0:
            # A co-op rescue cannot resurrect an already lethal hit. Restore a
            # visible independent corpse if the executing monster is interrupted.
            victim.visual_kind = "death_knight"
            victim.defeat_clip = "defeat"
            victim.down_remaining = model.rules.death_frames.duration("death_knight","defeat")
            victim.down_duration = victim.down_remaining
    holder.interaction = {}
    holder.held_target = 0
    holder.special_clip = ""
    holder.visual_kind = ""

static func advance(model: RefCounted) -> void:
    var ids: Array = model.actors.keys(); ids.sort()
    for id in ids:
        var holder: Dictionary = model.actors[id]
        if holder.interaction.is_empty(): continue
        if holder.health<=0:
            interrupt(model,holder)
            continue
        var sequence: Dictionary = holder.interaction
        var victim: Dictionary = model.actors.get(sequence.victim,{})
        if victim.is_empty():
            interrupt(model,holder)
            continue
        if sequence.kind=="guardian":
            model.Guardian.advance(model,holder,victim)
            continue
        var content: Resource = model.rules.finishes
        if victim.health<=0 and victim.hidden_by==holder.id:
            victim.down_remaining=maxi(2,victim.down_remaining)
        sequence.elapsed += 1
        holder.hold_elapsed = sequence.elapsed
        if sequence.kind == "mud" and sequence.stage == "carry":
            var command: Dictionary = model.pending.get(victim.id,{})
            victim.grab_remaining = maxi(1,sequence.duration-sequence.elapsed)
            # LAB_0EAC decrements first. Expiry wins even if the escape
            # combination arrives on the final carry tick.
            if sequence.elapsed<sequence.duration and command.get("action","") == "block" and command.get("dy",0)>0:
                stage(holder,"release",content.mud_release_ticks)
                model.events.append({"type":"escape","actor":victim.id})
                continue
        var end_at: int=sequence.duration
        if model.mode!=&"cooperative" and sequence.kind in ["spear","balok"]:
            var family: String="complete_spear_finishes" if sequence.kind=="spear" else "complete_balok_finishes"
            end_at=mini(end_at,model.rules.death_frames.solo_limit(family,sequence.stage))
        if sequence.elapsed < end_at: continue
        match sequence.kind:
            "emerge":
                if sequence.stage == "appear":
                    var distance: int = abs(holder.x-victim.x)
                    if victim.health>0 and victim.hidden_by==0 and abs(holder.y-victim.y)<=5 and distance>=20 and distance<=80:
                        holder.held_target = victim.id
                        sequence.kind = "mud"
                        model.events.append({"type":"attack","actor":holder.id,"move":"mud_ambush"})
                        kill(model,holder,victim,content.mud_quick_ticks)
                        stage(holder,"quick_drag",content.mud_quick_ticks)
                    else: stage(holder,"withdraw",12)
                else:
                    holder.interaction = {}
                    holder.special_clip = ""
                    holder.visual_kind = ""
                    holder.cooldown_remaining = 30
            "balok":
                if sequence.stage == "lift": stage(holder,"shake",content.balok_shake_ticks)
                elif sequence.stage == "shake":
                    if victim.health>0:
                        victim.x = clampi(holder.x+75*holder.facing,22,298)
                        victim.y = holder.y
                        release(model,holder,victim)
                    else:
                        model.balok_finish_toggle ^= 1
                        var clip: String = "eat_a" if model.balok_finish_toggle==1 else "eat_b"
                        var duration: int = content.balok_eat_a_ticks if clip=="eat_a" else content.balok_eat_b_ticks
                        kill(model,holder,victim,duration)
                        stage(holder,clip,duration)
                else:
                    var remains: String="remains_a" if sequence.stage=="eat_a" else "remains_b"
                    victim.x=holder.x
                    victim.y=holder.y; victim.facing=holder.facing
                    release(model,holder,victim)
                    victim.visual_kind="balok_finishes"; victim.defeat_clip=remains
                    victim.down_duration=6; victim.down_remaining=0
            "mud":
                if sequence.stage == "carry":
                    kill(model,holder,victim,content.mud_swallow_ticks)
                    stage(holder,"swallow",content.mud_swallow_ticks)
                elif sequence.stage == "release":
                    release(model,holder,victim)
                    holder.health = maxi(0,holder.health-1)
                    if holder.health==0: model.knock_down(holder,"defeat")
                    else:
                        holder.reaction="hurt_a";holder.reaction_remaining=18;holder.stagger_remaining=18
                else:
                    release(model,holder,victim)
                    victim.vanished=true
                    holder.cooldown_remaining=90
            "spear":
                victim.x=holder.x;victim.y=holder.y;victim.facing=holder.facing
                release(model,holder,victim)
                victim.visual_kind="spear_finishes";victim.defeat_clip="remains";victim.down_duration=6
                victim.down_remaining=0

static func flung(model: RefCounted, victim: Dictionary) -> void:
    victim.visual_kind="death_knight"
    victim.defeat_clip="flung"
    victim.down_duration=model.rules.finishes.knight_flung_ticks
    victim.down_remaining=victim.down_duration
