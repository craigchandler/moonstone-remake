extends RefCounted

const Session=preload("res://scripts/session/local_session.gd")
const Animator=preload("res://scripts/presentation/actor_animator.gd")
const Effects=preload("res://scripts/presentation/combat_hit_effects.gd")
const Finish=preload("res://debug/fixtures/finisher_fixture.gd")
const Death=preload("res://debug/fixtures/death_review_fixture.gd")
const Rules=preload("res://content/foundation_rules.tres")
const Art=preload("res://content/classic_art.tres")

# Expected digests were recorded from the initial classic drawing code before
# introducing the renderer interface. Balok blood and the combat-pace rules
# deliberately update live-combat traces; fixed finishers/deaths stay identical.
# Fixtures remain the gameplay authority.
func run_cases(draw_frame: Callable) -> Dictionary:
    var results: Dictionary={}
    for name in ["spear","balok_a","balok_b","troll","mud_carry","mud_quick","guardian_close","guardian_far","dragon_death","guardian_death","hammer_a","hammer_b"]:
        for mirror in [false,true]:
            var fixture: RefCounted=Finish.new();fixture.choice=name;fixture.mirror=mirror
            record(results,name+str(mirror),fixture,1950 if name=="balok_b" else 1100,draw_frame)
    for name in ["audit_rat_victim~strike","audit_rat_victim~bite","audit_rat_throw~defeat","audit_rat_squeeze~defeat","audit_burn~burn","audit_bite~defeat","audit_guardian_kill~defeat"]:
        for mirror in [false,true]:
            var fixture: RefCounted=Death.new();fixture.choice=name;fixture.mirror=mirror
            record(results,name+str(mirror),fixture,2500 if name=="audit_burn~burn" else 500,draw_frame)
    for encounter in Rules.encounters:
        var fixture: RefCounted=Combat.new();fixture.encounter=encounter
        record(results,encounter,fixture,600,draw_frame)
    return results

func record(results: Dictionary, key: String, fixture: RefCounted, ticks: int, draw_frame: Callable) -> void:
    var session: RefCounted=Session.new(Rules)
    var animator: RefCounted=Animator.new()
    var effects: RefCounted=Effects.new()
    var digest:=HashingContext.new();digest.start(HashingContext.HASH_SHA256)
    for tick in ticks:
        fixture.advance(session)
        animator.update(session.simulation.actors,Rules,Art)
        effects.update(session.simulation,Art)
        if tick%7==0 or tick==ticks-1:
            digest.update(var_to_bytes(draw_frame.call(session,animator,effects,tick)))
    results[key]=digest.finish().hex_encode()

class Combat extends RefCounted:
    var encounter: String
    var age: int=0
    func advance(session: RefCounted) -> void:
        if age==0:session.start(&"cooperative",StringName(encounter),{"count":2,"concurrent":2})
        var moves: Array=["swing","heavy","lunge","reverse","upward","dagger","block",""]
        session.advance(Vector2i(1 if age%120<60 else -1,1 if age%90<45 else -1),moves[(age/40)%moves.size()])
        age+=1
