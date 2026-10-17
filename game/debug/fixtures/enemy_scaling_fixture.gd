extends RefCounted
# Staged character/site, followed by actual journey entry and ordinary live AI.
var choice: String="scaling_beast"
var mirror: bool=false
var tick: int=0
var checked: Dictionary={}
var initial: Dictionary={}
var journey: RefCounted
func length() -> int:return 180
func setup(session: RefCounted) -> void:
    journey=preload("res://scripts/session/journey_session.gd").new(preload("res://content/first_journey.tres"),preload("res://content/foundation_rules.tres"),0x4d4f4f4e)
    if choice=="scaling_beast":
        journey.character.stats.strength=4;journey.character.stats.constitution=5
        journey.character.weapon="claymore";journey.character.health=60
    var id: String="grassland_east" if choice=="scaling_beast" else "lair_05"
    journey.world.position=journey.world.lair(id).position;journey.world.active_lair=id
    journey.start_site_combat()
    session.simulation=journey.combat.simulation;session.sequence.clear()
    if mirror:
        for a in session.simulation.actors.values():a.x=320-a.x;a.facing=-a.facing
    initial=session.simulation.snapshot()
func advance(session: RefCounted) -> void:
    if tick==0:setup(session)
    session.advance(Vector2i.ZERO if choice=="scaling_beast" else (Vector2i.UP if tick<10 else Vector2i.ZERO),"idle")
    tick+=1
func verify(_session: RefCounted) -> bool:
    var beasts: bool=choice=="scaling_beast"
    var foes: Array=initial.actors.values().filter(func(a:Dictionary)->bool:return a.team==2)
    checked={"actual_total":initial.encounter_settings.count==(9 if beasts else 5),"actual_slots":foes.size()==(3 if beasts else 2),
        "real_character":initial.actors[1].maximum==(60 if beasts else 20),"fixed_enemy_hp":foes.all(func(a:Dictionary)->bool:return a.health==(10 if beasts else 7)),
        "no_xp":journey.character.experience==0}
    for key in checked:
        if not checked[key]:push_error(choice+" failed: "+key)
    return not checked.values().has(false)
func report() -> Dictionary:return {"choice":choice,"mirror":mirror,"checks":checked,"initial":initial}
