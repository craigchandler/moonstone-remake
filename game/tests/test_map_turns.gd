extends SceneTree
const World=preload("res://scripts/domain/world_simulation.gd")
const Journey=preload("res://scripts/session/journey_session.gd")
const Definition=preload("res://scripts/content/world_definition.gd")
const TravelRules=preload("res://scripts/content/map_travel_rules.gd")
var production: Resource=preload("res://content/first_journey.tres").duplicate()
var rules: Resource=preload("res://content/foundation_rules.tres")
var failures: int=0
func check(ok: bool,label: String) -> void:
    if not ok:
        failures+=1
        push_error(label)
func fresh(flat: bool=false) -> RefCounted:
    return Journey.new(Definition.new() if flat else production,rules,1297043278)
func _init() -> void:
    production.rival_turns=false # Isolated historical component fixture.

func _initialize() -> void:
    var imported: Resource=production.travel_rules
    check(imported.terrain.size()==1000 and imported.regions.size()==1040,"Original terrain and region grids imported as native resources")
    for point in [Vector2i(-999,-999),Vector2i(0,0),Vector2i(319,199),Vector2i(9999,9999)]:
        check(imported.mask_at(point) in [0,1,2,3],"Foot lookup safely clamps both axes at map edges")
    for mask in range(4):
        var definition: Resource=Definition.new()
        definition.lairs.clear();definition.special_encounters.clear()
        definition.start_position=Vector2i(100,100)
        definition.travel_rules=TravelRules.new()
        definition.travel_rules.terrain.resize(1000);definition.travel_rules.terrain.fill(mask)
        var w: RefCounted=World.new(definition)
        var costs: int=0
        var xs: Array=[]
        for t in range(16):
            w.advance(Vector2i.RIGHT)
            costs+=w.last_step_cost
            if t%2==1:xs.append(w.position.x-100)
        check(w.position.x-100==[8,4,4,2][mask] and costs==[8,4,4,2][mask],"Full/half/half/quarter native movement and uncharged blocked frames: %d"%mask)
        check(xs==[[1,2,3,4,5,6,7,8],[0,1,1,2,2,3,3,4],[1,1,1,2,3,3,3,4],[0,0,0,1,1,1,1,2]][mask],"Masks1 and2 preserve their distinct movement rhythms: %d"%mask)
        w.terrain_counter=65535;w.tick=1
        w.advance(Vector2i.RIGHT)
        check(w.terrain_counter==0 if mask!=0 else w.terrain_counter==65535,"16-bit terrain phase wraps without blocking the map")
    # Real mixed-terrain motion continues at the exact odd tick/terrain phase.
    var j: RefCounted=fresh()
    for t in range(37):j.travel(Vector2i.RIGHT)
    var saved: Dictionary=j.checkpoint()
    var copy: RefCounted=fresh()
    check(copy.restore_checkpoint(saved) and copy.checkpoint()==saved,"Terrain counter and half-step save exactly")
    for t in range(80):
        check(j.travel(Vector2i.RIGHT)==copy.travel(Vector2i.RIGHT) and j.checkpoint()==copy.checkpoint(),"Mixed-terrain Continue replays exact movement/flight/encounter state")
    # Every original lair remains reachable despite slow cells, with unchanged
    # encounter identity, treasure seed and initial progression.
    for site in production.lairs:
        j=fresh();j.world.position=site.position-Vector2i(8,0)
        var rewards: Dictionary=j.lair_loot.duplicate(true)
        for t in range(80):
            j.travel(Vector2i.RIGHT)
            if j.confirm_location(site.id):break
        check(j.combat!=null and j.world.active_lair==site.id and j.lair_loot==rewards and j.character.experience==0,"Original terrain permits entry without rewards/rerolls: "+site.id)
    # Exhaustion ends one turn. Held input, idle updates and another rest cannot
    # consume the following round while its message is awaiting acknowledgement.
    j=fresh(true);j.world.position=Vector2i(250,160);j.travel_spent=j.travel_allowance()-1
    j.character.health=12;j.haste=true;j.travel_spent=j.travel_allowance()-1
    j.travel(Vector2i.LEFT);j.travel(Vector2i.LEFT)
    check(j.turn_pending and j.turn_reason=="travel" and j.day==2 and j.world.position==Vector2i(249,160) and not j.haste,"Last allowed movement ends turn and expires Haste once")
    check(j.character.health==15 and j.travel_remaining()==96,"One end-turn recovery and renewed ordinary allowance")
    var boundary: Dictionary=j.checkpoint()
    for t in range(500):j.travel(Vector2i.LEFT)
    check(not j.rest() and j.checkpoint()==boundary,"Held travel/rest cannot silently spend multiple rounds")
    check(copy.restore_checkpoint(boundary) and copy.checkpoint()==boundary,"Turn-end pause survives Continue exactly")
    check(copy.begin_turn() and copy.day==2 and copy.character.health==15 and not copy.begin_turn(),"Beginning the next turn cannot advance or heal a second time")
    # A last-step town uses exactly one turn, on departure, not two.
    j=fresh(true);j.world.position=Vector2i(76,28);j.travel_spent=j.travel_allowance()-1
    j.travel(Vector2i.RIGHT);j.travel(Vector2i.RIGHT)
    check(j.town_id=="highwood" and not j.turn_pending and j.day==1 and j.travel_remaining()==0,"Last-step town opens before exhaustion is resolved")
    check(not j.rest() and j.day==1,"Rest API cannot end an open town visit behind its screen")
    check(j.leave_town() and j.turn_pending and j.turn_reason=="town" and j.day==2 and not j.leave_town(),"Town departure spends exactly one turn")
    # Last-step lair keeps its result/loot until exit, then renews the turn once.
    j=fresh(true);j.world.position=Vector2i(59,63);j.travel_spent=j.travel_allowance()-1
    j.travel(Vector2i.RIGHT);j.travel(Vector2i.RIGHT)
    check(j.combat!=null and not j.turn_pending and j.day==1,"Last-step combat is never replaced by a turn message")
    if j.combat!=null:
        j.combat.simulation.spawn_remaining=0;j.combat.simulation.actors[1].health=7
        for actor in j.combat.simulation.actors.values():
            if actor.team==2:actor.health=0
        j.prepare_loot()
        check(j.loot_open and j.character.experience==1 and not j.turn_pending,"Won loot/XP resolve before the turn transition")
        j.return_to_map(false)
        check(j.turn_pending and j.day==2 and j.character.health==10 and j.character.experience==1,"Leaving last-step loot ends once, preserves XP and recovers once")
    # A pending scroll decision also resolves before the last-step turn ends.
    j=fresh(true);j.inventory.items.scroll_of_protection=1
    j.world.position=Vector2i(40,90);j.travel_spent=j.travel_allowance()-1
    j.travel(Vector2i.RIGHT);j.travel(Vector2i.RIGHT)
    check(j.pending_attack=="roaming_black_knight" and not j.turn_pending,"Last-step knight attack retains the protection-scroll choice")
    check(j.resolve_pending_attack(true) and j.turn_pending and j.day==2 and j.character.experience==0,"Avoiding last-step fight ends once without fake rewards")
    # Explicit lunar state: four completed rounds per phase, eight for Dragon.
    j=fresh()
    for i in range(8):
        check(j.rest() and j.turn_pending,"Rest ends a round")
        check(j.calendar().lunar_counter==(i+1)/4 and j.calendar().moon_subcount==(i+1)%4,"Lunar phase advances only once per four completed rounds")
        j.begin_turn();j.travel(Vector2i.ZERO)
        check(j.world.dragon.active==(i==7),"Dragon uses the same completed-round lunar clock")
    # Current and actual old-schema flight preserve state without a new turn.
    var old: Dictionary=j.checkpoint();old.schema=6;old.content="journey.campaign.v4"
    old.world.schema=2;old.world.content="journey.v7";old.world.erase("terrain_counter")
    old.erase("turn_pending");old.erase("turn_reason")
    var before: Dictionary=old.duplicate(true)
    check(copy.restore_checkpoint(old) and old==before and copy.world.dragon.snapshot()==old.world.dragon and copy.day==old.day and copy.lair_loot==old.lair_loot,"Dragon-Map save migration preserves exact flight/clock/kit/rolls without spending a turn")
    var good: Dictionary=copy.checkpoint()
    for count in [-1,65536,2.5]:
        var bad: Dictionary=good.duplicate(true);bad.world.terrain_counter=count
        check(not copy.restore_checkpoint(bad) and copy.checkpoint()==good,"Invalid terrain phase rejects atomically")
    var bad: Dictionary=good.duplicate(true);bad.turn_reason="travel"
    check(not copy.restore_checkpoint(bad),"Unpaired turn reason is rejected")
    bad=good.duplicate(true);bad.turn_pending=true;bad.turn_reason="town";bad.travel_spent=1
    check(not copy.restore_checkpoint(bad),"Spent pending-turn state is rejected")
    if failures==0:print("PASS: imported terrain/feet/bounds/cadences, mixed-path saved replay, all24 original lairs, single travel/rest/town turn boundaries, last-step combat/loot/scroll precedence, lunar gate, exact legacy flight migration and atomic invalid-state rejection")
    quit(1 if failures else 0)
