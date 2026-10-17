extends SceneTree

const Journey = preload("res://scripts/session/journey_session.gd")
const Flight = preload("res://scripts/domain/map_dragon.gd")
var definition: Resource = preload("res://content/first_journey.tres").duplicate()
var combat_rules: Resource = preload("res://content/foundation_rules.tres")
var failures: int = 0

func check(ok: bool, label: String) -> void:
    if not ok:
        failures += 1
        push_error(label)

func fresh() -> RefCounted:
    return Journey.new(definition, combat_rules, 0x4d4f4f4e)

func _init() -> void:
    definition.rival_turns=false # Isolated historical component fixture.

func _initialize() -> void:
    var j: RefCounted = fresh()
    var kit: Dictionary = j.character.snapshot()
    var chests: Dictionary = j.lair_loot.duplicate(true)
    for completed in range(8):
        for t in range(100): j.travel(Vector2i.ZERO)
        check(not j.world.dragon.active and j.combat==null, "No dragon before eight completed rounds: %d" % completed)
        j.rest()
        j.begin_turn()
    j.travel(Vector2i.ZERO)
    check(j.day==9 and j.world.dragon.active and j.world.dragon.position==Vector2i(10,100), "Classic counter2 appears after eight rounds, entering at left edge")
    check(j.character.snapshot()==kit and j.lair_loot==chests and j.character.experience==0, "Clock trigger never invents combat rewards or changes entry kit")
    var f: RefCounted = j.world.dragon
    var frames: Dictionary = {}
    var max_x: int = f.position.x
    var saw_return: bool = false
    var saw_glide: bool = false
    for t in range(650):
        var old: Dictionary = f.snapshot()
        f.advance(8,Vector2i(200,30),true)
        frames[f.frame()] = true
        max_x = maxi(max_x, f.position.x)
        if f.timer<=60 and f.subtick==0:
            saw_glide=true
            check(f.position.y==old.y and f.frame()==3, "Glide holds wings and altitude while still travelling")
        if f.speed_x<0: saw_return=true
    check(frames.size()==8 and saw_glide, "All eight original wing poses plus held glide are used")
    check(max_x>350 and saw_return, "Pass leaves the map; gliding is not clamped; flapping later reverses")
    f.position=Vector2i(-20,100);f.speed_x=-2;f.facing=1;f.timer=100;f.subtick=1
    f.advance(8,Vector2i(200,100),true)
    check(f.position.x==-10 and f.speed_x==2 and f.facing==3,"Left offscreen return uses original anchor and mirrored direction")
    check(not f.touches(Vector2i(200,100)), "An unrelated remote knight position cannot trigger a fight")
    f.position=Vector2i(200,100)
    check(f.touches(Vector2i(190,100)) and not f.touches(Vector2i(190,100),1), "Only the selected token touching the body starts combat")
    # Flight is saved data, not derived from a global path clock.
    j=fresh();j.day=9
    for t in range(37):j.travel(Vector2i.ZERO)
    var saved: Dictionary=j.checkpoint()
    var resumed: RefCounted=fresh()
    check(resumed.restore_checkpoint(saved) and resumed.checkpoint()==saved,"Continue preserves exact flight, subtick, target, loot and character")
    for t in range(600):
        check(j.travel(Vector2i.ZERO)==resumed.travel(Vector2i.ZERO) and j.checkpoint()==resumed.checkpoint(),"Continued flight replays the same encounter and state")
        if j.combat!=null:break
    # A moving dragon attacks a stationary knight, without walking into its old D route.
    j=fresh();j.day=9;j.world.position=Vector2i(190,100)
    j.world.dragon.active=true;j.world.dragon.position=Vector2i(200,100)
    check(j.travel(Vector2i.ZERO) and j.combat!=null and j.world.active_lair=="roaming_dragon", "Flight contact enters real Dragon combat even with no movement input")
    check(not j.world.dragon.active and j.world.dragon_hoard==Vector2i(190,100),"Arena reset clears flight and remembers actual treasure location")
    j.combat.simulation.spawn_remaining=0
    for actor in j.combat.simulation.actors.values():
        if actor.team==2:actor.health=0
    check(j.prepare_loot(),"Dragon victory opens its normal loot")
    var after_win: RefCounted=fresh()
    check(after_win.restore_checkpoint(j.checkpoint()) and after_win.loot_open,"Dragon loot continues exactly")
    after_win.return_to_map(false)
    after_win.world.position=definition.start_position
    for t in range(500):after_win.travel(Vector2i.ZERO)
    check(after_win.world.cleared.has("roaming_dragon") and not after_win.world.dragon.active and after_win.character.experience==2,"Defeated dragon never respawns or awards twice")
    after_win.world.position=Vector2i(182,100);after_win.world.entry_lock=""
    for t in range(16):
        after_win.travel(Vector2i.RIGHT)
        if after_win.confirm_location("roaming_dragon"):break
    check(after_win.loot_open and after_win.world.active_lair=="roaming_dragon" and after_win.character.experience==2,"Untaken Dragon hoard can be revisited at the actual encounter without extra combat/XP")
    # Place visits clear a pass; ordinary inventory/menu pauses do not.
    j=fresh();j.day=9;j.travel(Vector2i.ZERO)
    j.world.position=j.town("highwood").position
    check(j.enter_town("highwood") and not j.world.dragon.active,"Town visit ends flight")
    j.leave_town();j.begin_turn();j.travel(Vector2i.ZERO)
    check(j.world.dragon.active and j.world.dragon.position==Vector2i(10,100),"Returning from a place starts a fresh edge pass")
    var malformed: Dictionary=j.checkpoint()
    var unchanged: Dictionary=j.checkpoint()
    for field in ["timer","subtick","target","speed_x","x"]:
        var bad: Dictionary=malformed.duplicate(true);bad.world.dragon[field]=9999
        check(not j.restore_checkpoint(bad) and j.checkpoint()==unchanged,"Invalid flight is rejected before mutation: "+field)
    var early: Dictionary=malformed.duplicate(true);early.day=1
    check(not j.restore_checkpoint(early),"Active pre-trigger flight save is rejected")
    # Actual previous release saves, with and without a defeated dragon, retain
    # their old chest rolls, keys, kit, progression, town and day during migration.
    var old: Dictionary=fresh().checkpoint()
    old.schema=5;old.content="journey.campaign.v3";old.world.schema=1;old.world.content="journey.v6"
    old.world.erase("dragon");old.world.erase("dragon_hoard")
    var before: Dictionary=old.duplicate(true)
    check(j.restore_checkpoint(old) and old==before,"Towns save migration accepts without mutating input")
    check(j.lair_loot==old.lair_loot and j.character.snapshot()==old.character and j.inventory==old.inventory and j.day==old.day and j.owned_keys==old.owned_keys,"Previous exact treasure/kit/clock/keys survive migration")
    old.world.cleared.roaming_dragon=true;old.awarded_lairs.roaming_dragon=true;old.day=15
    check(j.restore_checkpoint(old),"Defeated previous dragon save migrates")
    j.travel(Vector2i.ZERO)
    check(not j.world.dragon.active and j.world.lair("roaming_dragon").position==Vector2i(210,90),"Old defeated dragon remains dead with recoverable old hoard")
    var art: Resource=load("res://assets/classic/world/art.tres")
    check(art.dragon_frames.size()==8 and art.dragon_offsets.size()==8,"Original map dragon frames imported separately from combat art")
    for i in range(8):
        check(art.dragon_frames[i].get_width()>=34 and art.dragon_offsets[i].x==-17,"Original map frame dimensions and anchor retained")
    if failures==0:print("PASS: map Dragon lunar trigger, eight original wing poses/glide, edge flight/reversal, targeted stationary contact, single victory/loot, visits, exact continued replay, legacy migration and invalid-save rejection")
    quit(1 if failures else 0)
