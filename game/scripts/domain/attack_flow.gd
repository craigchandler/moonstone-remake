extends RefCounted

# A bounded content interface. All persistent branch data lives on the actor.
static func manifest(rules: Resource) -> Dictionary:
    var p: Resource = rules.attack_timing
    return {p.profile_id:{"api":p.api_version,"version":p.content_version}}

static func policy(rules: Resource, actor: Dictionary) -> Dictionary:
    var resource: Resource = rules.attack_timing
    if resource.api_version != 1: return {}
    var p = resource.moves.get(actor.action,{})
    if not p is Dictionary or not p.get("kinds",[]) is Array or actor.kind not in p.get("kinds",[]): return {}
    if typeof(p.get("cancel_windup")) != TYPE_BOOL: return {}
    if typeof(p.get("contact_impact",0)) != TYPE_INT or p.get("contact_impact",0)<0 or p.get("contact_impact",0)>600: return {}
    for field in ["recovery_lock","contact_hold","contact_return"]:
        if typeof(p.get(field)) != TYPE_INT or p[field]<0 or p[field]>600: return {}
    return p

static func begin(rules: Resource, actor: Dictionary, tick: int) -> void:
    actor.attack_flow = {}
    if policy(rules,actor).is_empty(): return
    actor.attack_flow = {"profile":rules.attack_timing.profile_id,"version":rules.attack_timing.content_version,
        "started":tick,"branch":"full","impact_elapsed":0}

static func cancelable(rules: Resource, actor: Dictionary) -> bool:
    var move: Dictionary = rules.moves[actor.action]
    if actor.get("attack_flow",{}).get("branch","") == "contact": return false
    var p: Dictionary = policy(rules,actor)
    if actor.remaining > move.active+move.recovery:
        return p.get("cancel_windup",true)
    if actor.remaining > move.recovery: return false
    return move.recovery-actor.remaining >= int(p.get("recovery_lock",0))

static func contact(rules: Resource, actor: Dictionary, hit: Dictionary, tick: int) -> void:
    # Called after ALL simultaneous hits settle. Interrupted/dead actors cannot
    # restart an attack; executions and lethal choreography keep their full path.
    if actor.health<=0 or actor.remaining<=0 or actor.action!=hit.move or actor.stagger_remaining>0: return
    if not actor.interaction.is_empty() or actor.special_remaining>0 or actor.held_target!=0: return
    if not hit.get("resolved",false): return
    if hit.get("blocked",false) or hit.get("execution",false) or hit.amount<=0 or hit.get("lethal",false): return
    if actor.get("attack_flow",{}).get("branch","") == "contact": return
    var p: Dictionary = policy(rules,actor)
    if p.is_empty() or p.contact_hold==0 or p.contact_return==0: return
    var move: Dictionary = rules.moves[actor.action]
    if actor.remaining<=move.recovery or actor.remaining>move.active+move.recovery: return
    if actor.get("attack_flow",{}).is_empty():
        begin(rules,actor,tick-(move.windup+move.active+move.recovery-actor.remaining))
    actor.attack_flow.branch = "contact"
    actor.attack_flow.impact_elapsed = move.active+move.recovery-actor.remaining
    actor.remaining = int(p.get("contact_impact",0))+p.contact_hold+p.contact_return

static func settle(rules: Resource, actors: Dictionary, hits: Array, tick: int) -> void:
    var lethal_sources: Dictionary = {}
    for hit in hits:
        if hit.get("resolved",false) and hit.get("lethal",false): lethal_sources[hit.attacker]=true
    for hit in hits:
        # A blade can touch two opponents in one pass. A surviving contact
        # must not shorten the same blade's simultaneous lethal follow-through.
        if not lethal_sources.has(hit.attacker): contact(rules,actors[hit.attacker],hit,tick)

static func reaction(rules: Resource, actor: Dictionary, move: String) -> void:
    var p = rules.attack_timing.reactions.get(move,{})
    if not p is Dictionary or actor.kind not in p.get("kinds",[]): return
    if typeof(p.get("ticks"))!=TYPE_INT or p.ticks<1 or p.ticks>600 or typeof(p.get("clip"))!=TYPE_STRING: return
    actor.reaction=p.clip;actor.reaction_remaining=p.ticks;actor.reaction_duration=p.ticks

static func hurt_protected(rules: Resource,actor: Dictionary) -> bool:
    # Native stagger is the gameplay hurt window. Visual reaction tails can
    # finish early when an actor resumes its next action; they grant no armour.
    var clips: Array=rules.attack_timing.untargetable_reactions.get(actor.kind,[])
    # War Beast owns a dedicated hurt -> impact -> charge state rather than
    # generic stagger. Only its hurt stages omit the original hurt-list draws.
    return (actor.stagger_remaining>0 and actor.reaction in clips) or actor.get("beast",{}).get("stage","") in clips
