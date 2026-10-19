extends RefCounted

# A renderer receives values only, never the simulation, session or progression
# objects. Rebuilt once per draw; animation history advances only on game ticks.
var tick: int=0
var actors: Array[Dictionary]=[]
var perch: Dictionary={}
var projectiles: Array[Dictionary]=[]
var effects: Array[Dictionary]=[]
var gore: bool=true
var colour: int=0
var encounter: StringName

func capture(model: RefCounted, animator: RefCounted, hit_effects: RefCounted, rules: Resource,
        selected_encounter: StringName, gore_enabled: bool, knight_colour: int,
        colours: Dictionary, equipment: Dictionary) -> void:
    tick=model.tick;gore=gore_enabled;colour=knight_colour;encounter=selected_encounter
    actors.clear();projectiles.clear();effects.clear()
    perch=model.rat_perch.duplicate()
    for actor in model.actors.values():
        var visual: String=actor.get("visual_kind","")
        var hint: String=""
        if actor.grab_remaining>0:hint="HELD: guard + down"
        if actor.get("held_target",0)!=0:hint="HELD: Space + Down to counter" if actor.kind in ["ratman","mudman"] else "CAUGHT"
        var appearance: Dictionary=equipment.get(actor.id,{}).duplicate()
        if actor.kind in ["knight","black_knight"]:
            if not appearance.has("weapon"):appearance["weapon"]="long_sword"
            if not appearance.has("armour"):appearance["armour"]="padded_armour"
        appearance["colour"]=colours.get(actor.id,4 if actor.team==2 and visual=="death_knight" else colour)
        appearance["variant"]="blue" if actor.team==1 or actor.id in colours else "purple"
        var row: Dictionary={"id":actor.id,"kind":actor.kind,"family":actor.kind if visual.is_empty() else visual,
            "ground":Vector2(actor.x,actor.y),"height":actor.height,"facing":actor.facing,
            "alive":actor.health>0,"visible":actor.get("hidden_by",0)==0 and not actor.get("vanished",false),
            "flash":actor.flash>0,"guarding":actor.guarding,"team":actor.team,"hold_hint":hint,
            "motion":animator.motions.get(actor.id,{}).duplicate(),"appearance":appearance}
        if actor.kind=="dragon":row["feet"]=animator.motion.feet(actor,rules)
        actors.append(row)
    actors.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:return a.ground.y<b.ground.y)
    for projectile in model.projectiles:
        projectiles.append({"kind":projectile.get("kind","dagger"),"ground":Vector2(projectile.x,projectile.y),
            "height":projectile.get("height",0),"facing":projectile.get("facing",1),"age":projectile.get("age",0)})
    for effect in hit_effects.active:
        effects.append({"kind":effect.kind,"point":Vector2(effect.x,effect.y),"facing":effect.facing,
            "elapsed":tick-effect.born,"duration":effect.duration})
