extends SceneTree

const Journey=preload("res://scripts/session/journey_session.gd")
const Session=preload("res://scripts/session/local_session.gd")
var definition: Resource=preload("res://content/first_journey.tres")
var rules: Resource=preload("res://content/foundation_rules.tres")
var moon: Resource=preload("res://content/generated/moonstone_quest.tres")
var failures: int=0
func check(ok: bool,label: String) -> void:
    if not ok:failures+=1;push_error(label)
func fresh() -> RefCounted:return Journey.new(definition,rules,1297043278)
func win(j: RefCounted) -> void:
    j.combat.simulation.spawn_remaining=0
    for actor in j.combat.simulation.actors.values():
        if actor.team==2:actor.health=0
func boss(j: RefCounted) -> void:
    j.owned_keys=15
    j.world.position=Vector2i(152,89)
    for tick in range(64):
        j.travel(Vector2i.DOWN)
        j.confirm_location("valley_guardian")
        if j.combat!=null:return
    check(false,"actual original Valley entry")
func copy(j: RefCounted) -> RefCounted:
    var before: Dictionary=j.checkpoint()
    var restored: RefCounted=fresh()
    check(restored.restore_checkpoint(JSON.parse_string(JSON.stringify(before))) and restored.checkpoint()==before,"serialized exact quest Continue")
    return restored
func _initialize() -> void:
    var clock: Array=[45,46,47,48,49,48,47,46]
    check(moon.moon_frames==clock and moon.quest_frames==[49,45,47,47] and moon.damage_frames==[47,45,49,47],"verified retail cycle and distinct gates")
    for mask in range(16):
        for phase in range(8):
            var quest_match: bool=false
            var damage_match: bool=false
            for bit in range(4):
                if mask&(1<<bit):
                    quest_match=quest_match or clock[phase]==[49,45,47,47][bit]
                    damage_match=damage_match or clock[phase]==[47,45,49,47][bit]
            check(moon.matches(mask,phase)==quest_match and moon.matches(mask,phase,true)==damage_match,"all mask/phase quest and sword gates")
            var route: RefCounted=fresh()
            route.quest.stones=mask;route.day=phase*4+1;route.world.active_lair="grassland_west"
            route.start_site_combat()
            check(route.combat.simulation.actors[1].moon_damage_shift==(1 if damage_match else 0),"journey applies the carried stone and current phase to actual combat entry")
    for kind in range(4):
        for pair in [[45,4],[47,1],[49,2]]:check(moon.ending_code(pair[0],kind)==(128|pair[1]|[16,32,64,8][kind]),"all four knight/three phase ending encodings")
    var j: RefCounted=fresh()
    check(not j.award_moonstone() and j.quest.stones==0,"no earned victory means no reward")
    var chests: Dictionary=j.lair_loot.duplicate(true)
    boss(j)
    var seed: int=j.quest.seed
    win(j);j.prepare_loot()
    check(j.quest.stones in [1,2,4,8] and j.quest.valley_stone==j.quest.stones and j.quest.seed!=seed and j.quest.notice,"single random carried stone on actual victory")
    check(j.character.experience==3 and j.owned_keys==0 and j.lair_loot==chests,"Valley3XP, all four keys consumed, other chests unchanged")
    check(j.available_loot().gold==0 and j.available_loot().items.is_empty() and not j.return_to_map(),"new Valley has no invented chest; source reward message precedes return")
    var earned: Dictionary=j.checkpoint()
    j=copy(j)
    check(not j.award_moonstone() and j.checkpoint()==earned,"continued reward cannot reroll/duplicate XP/stone")
    check(j.acknowledge_moonstone() and j.return_to_map(false) and not j.acknowledge_moonstone(),"acknowledge and return once")
    j=copy(j)
    var stone: int=j.quest.stones
    for phase in range(8):
        j=fresh();j.quest.stones=stone;j.day=phase*4+1;j.world.position=j.Henge.POSITION
        check(j.enter_henge(),"Stonehenge entry")
        if moon.matches(stone,phase):
            check(j.henge.is_empty() and j.quest.ending.stage=="message" and not j.enter_ending(),"matching stone chooses quest before item offering, with source wait")
            var held: Dictionary=j.snapshot()
            j.travel(Vector2i.RIGHT)
            check(j.snapshot()==held and not j.rest() and not j.use_item("healing_potion"),"victory freezes map/services/items")
            for tick in range(19):j.tick_quest()
            check(not j.enter_ending(),"confirm cannot bypass20-tick source wait")
            j=copy(j);j.tick_quest()
            check(j.enter_ending() and not j.enter_ending() and j.quest.stones==stone,"saved single ending handoff preserves stone")
            j=copy(j)
        else:check(j.henge.phase=="greeting" and j.quest.ending.is_empty(),"wrong phase keeps ordinary Danu offering; stone is not lost")
    # Previous Guardian wins receive the owed object, consume their old keys,
    # and preserve any existing unclaimed chest/XP/character/turn.
    j=fresh();var old: Dictionary=j.checkpoint()
    old.schema=8;old.content="journey.campaign.v6";old.erase("quest")
    old.world.cleared.valley_guardian=true;old.awarded_lairs.valley_guardian=true
    old.owned_keys=15;old.character.experience=3
    old.lair_loot.valley_guardian={"kind":1,"gold":23,"items":{},"keys":0}
    var unmodified: Dictionary=old.duplicate(true)
    check(j.restore_checkpoint(old) and old==unmodified and j.quest.stones!=0 and j.owned_keys==0 and j.character.experience==3 and j.lair_loot.valley_guardian.gold==23,"legacy earned reward filled once without a chest reroll or extra XP")
    j=copy(j)
    var good: Dictionary=j.checkpoint()
    for bad_quest in [{"seed":1},{"stones":16},{"valley_stone":3},{"valley_stone":0},{"notice":"yes"},{"ending":{"stage":"ready","tick":20,"frame":49,"knight_kind":0,"code":146}}]:
        var bad: Dictionary=good.duplicate(true)
        bad.quest.merge(bad_quest,true)
        check(not j.restore_checkpoint(bad) and j.checkpoint()==good,"invalid or contradictory quest save rejects atomically")
    var lost: RefCounted=fresh();boss(lost);seed=lost.quest.seed
    lost.combat.simulation.actors[1].health=0;lost.settle_battle()
    check(lost.quest.stones==0 and lost.quest.seed==seed and lost.owned_keys==15 and lost.character.experience==0,"loss awards nothing, keeps keys and does not draw quest RNG")
    var party: RefCounted=fresh();party.mode=&"cooperative";boss(party)
    party.combat.simulation.actors[1].health=0;win(party);party.prepare_loot()
    check(party.character.lives==2 and party.character.health==20 and party.quest.stones!=0 and party.character.experience==3,"AI party victory keeps fallen leader's existing life loss, then rewards the living campaign record")
    party=copy(party)
    check(party.acknowledge_moonstone() and party.return_to_map(false),"co-op victory cannot clear Valley without its quest reward")
    old=unmodified.duplicate(true);old.awarded_lairs.erase("valley_guardian");old.character.experience=0
    check(j.restore_checkpoint(old) and j.quest.stones!=0 and j.character.experience==3,"old cleared co-op Valley receives its owed XP/object exactly once")
    # Real sword contact receives one doubling after strength/sword/heavy;
    # thrown daggers remain their original projectile damage.
    for shift in [0,1]:
        for action in ["swing","heavy","lunge","reverse","upward","dagger"]:
            var session: RefCounted=Session.new(rules)
            session.knight_profile={"moon_damage_shift":shift,"damage_bonus":2}
            session.start(&"competitive",&"duel")
            var sim: RefCounted=session.simulation
            var a: Dictionary=sim.actors[1];var b: Dictionary=sim.actors[2]
            a.x=120;a.y=150;b.x={"reverse":105,"heavy":190,"lunge":210,"dagger":220}.get(action,145);b.y=150;b.health=200;b.maximum=200
            for tick in range(180):session.command(1,1,Vector2i.ZERO,action if tick==0 else "idle");sim.advance()
            var expected: int=3 if action=="dagger" else (int(rules.moves[action].damage)+2*(2 if action=="heavy" else 1))*(1<<shift)
            check(b.health==200-expected,"actual sword/projectile contact damage, shift%d %s" % [shift,action])
        var rat_session: RefCounted=Session.new(rules)
        rat_session.knight_profile={"moon_damage_shift":shift,"damage_bonus":2}
        rat_session.start(&"competitive",&"rat_lair")
        var holder: Dictionary=rat_session.simulation.actors[10]
        holder.health=30;holder.maximum=30
        rat_session.simulation.start_rat_hold(holder,rat_session.simulation.actors[1],"squeeze",600)
        for tick in range(30):rat_session.simulation.advance_rat_hold(holder,rat_session.simulation.actors[1],true)
        check(holder.health==30-(7<<shift),"Ratman sword counter retains carried moonstone damage")
    if failures==0:print("PASS: retail phase/bit matrix, all ending flags, actual Valley victory/loss, one saved RNG/object/XP/key transaction, legacy owed reward, wrong/matched-phase visits, saved ending handoff, atomic invalid saves and real sword-versus-dagger contacts")
    quit(1 if failures else 0)
