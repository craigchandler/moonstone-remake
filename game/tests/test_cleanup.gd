extends SceneTree

const Journey = preload("res://scripts/session/journey_session.gd")
const Party = preload("res://scripts/session/local_party.gd")
const Store = preload("res://scripts/session/journey_store.gd")
const Definition = preload("res://content/first_journey.tres")
const Rules = preload("res://content/foundation_rules.tres")
var fixtures: Dictionary = {}
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
    checks += 1
    if not ok:
        failures += 1
        push_error(label)

func fresh(all_human: bool = true) -> RefCounted:
    var j: RefCounted = Journey.new(Definition, Rules, 12345)
    var roster: Array = Party.defaults()
    if all_human:
        for row in roster:
            row.human = true
    check(j.start_local_party(roster, 12345), "party starts")
    j.begin_turn()
    return j

func roundtrip(j: RefCounted, label: String) -> void:
    var data: Dictionary = j.checkpoint()
    var fixture: String = label.get_slice(" ", 0)
    if not fixtures.has(fixture):
        fixtures[fixture] = data.duplicate(true)
    var copy: RefCounted = Journey.new(Definition, Rules, 3)
    check(copy.restore_checkpoint(JSON.parse_string(JSON.stringify(data))), label + ": JSON restore")
    check(copy.checkpoint() == data, label + ": exact state")

func win(j: RefCounted) -> void:
    j.combat.simulation.spawn_remaining = 0
    for actor in j.combat.simulation.actors.values():
        if actor.team == 2:
            actor.health = 0
    check(j.prepare_loot(), "victory settles")

func next_human(j: RefCounted, seat: int) -> void:
    for attempt in range(4):
        if j.party.active == seat:
            if j.party.awaiting:
                j.begin_turn()
            return
        if j.party.awaiting:
            j.begin_turn()
        j.rest()
    check(false, "requested human takes its turn")

func quest_loot() -> void:
    for holder in range(4):
        for attacker in range(4):
            if holder == attacker:
                continue
            for stone in [1, 2, 4, 8]:
                var j: RefCounted = fresh()
                next_human(j, holder)
                j.owned_keys = 15
                j.world.position = j.world.lair("valley_guardian").position
                check(j.confirm_location("valley_guardian"), "four-key guardian entry")
                win(j)
                j.acknowledge_moonstone()
                j.return_to_map(false)
                # Cover every legitimate random stone result without making the
                # test oracle depend on the production random generator.
                j.quest.stones = stone
                j.quest.valley_stone = stone
                roundtrip(j, "guardian reward")
                j.rest()
                next_human(j, attacker)
                var row: Dictionary = j.rivals.find(j.party.id_for(holder))
                row.position = j.world.position
                check(j.begin_rival_encounter(row.id, false), "holder challenged")
                win(j)
                check(j.available_loot().stones == stone, "earned stone enters real duel chest")
                roundtrip(j, "unclaimed rival chest %d/%d/%d" % [holder, attacker, stone])
                j.return_to_map(false)
                next_human(j, holder)
                check(j.party.personal[holder].duel.stones == stone, "active hidden chest retains its stone")
                roundtrip(j, "active hidden chest %d/%d/%d" % [holder, attacker, stone])
                var before: Dictionary = j.checkpoint()
                var duplicate: Dictionary = before.duplicate(true)
                duplicate.campaign.quest.stones = stone
                check(not j.restore_checkpoint(duplicate) and j.checkpoint() == before, "duplicate carried/hidden stone rejected atomically")
                j.rest()
                next_human(j, attacker)
                row = j.rivals.find(j.party.id_for(holder))
                j.world.position = row.position
                check(j.begin_rival_encounter(row.id, false) and j.loot_open, "unclaimed chest reopens without another battle")
                check(j.take_loot(j.quest_rules.stone_ids[[1, 2, 4, 8].find(stone)]), "stone collected")
                roundtrip(j, "collected stone %d/%d/%d" % [holder, attacker, stone])
    var j: RefCounted = fresh()
    j.awarded_lairs.valley_guardian = true
    j.world.cleared.valley_guardian = true
    j.quest.valley_stone = 1
    var row: Dictionary = j.rivals.find(j.party.id_for(1))
    row.stones = 1
    row.character.lives = 1
    row.inventory.gold = 149
    row.inventory.items = {"healing_potion": 2}
    row.position = j.world.position
    j.begin_rival_encounter(row.id, false)
    win(j)
    j.take_loot("healing_potion")
    check(j.available_loot().stones == 1 and j.available_loot().items.healing_potion == 1, "partial mixed quest chest retains remainder")
    roundtrip(j, "partial final-defeat chest")

func dragon_catches() -> void:
    for last_life in [false, true]:
        var j: RefCounted = fresh(false)
        j.day = 9
        var target: String = j.party.id_for(2)
        if last_life:
            j.rivals.find(target).character.lives = 1
        j.inventory.items.scroll_of_the_wyrm = 1
        check(j.use_item("scroll_of_the_wyrm", target), "Wyrm scroll accepted")
        j.rest()
        j.begin_turn()
        j.rest()
        var row: Dictionary = j.rivals.records[j.rivals.active - 1]
        j.world.dragon.active = true
        j.world.dragon.target = j.rivals.active
        j.world.dragon.position = row.position + Vector2i(1, 0)
        roundtrip(j, "before AI Dragon contact")
        j.advance_rival_turn()
        check(j.party.wyrm_target == -1 and j.dragon_order == -1, "catch clears both orders before next turn")
        check(j.party.record(j, 2).character.lives == (0 if last_life else 4), "catch loses exactly one life")
        roundtrip(j, "after AI Dragon contact")

func ai_targets() -> void:
    for seat in [0, 1]:
        var j: RefCounted = fresh(false)
        j.rest()
        j.begin_turn()
        j.rest()
        var row: Dictionary = j.rivals.records[j.rivals.active - 1]
        var destination: Vector2i = row.position + Vector2i(1, 0)
        if seat == j.party.active:
            j.world.position = destination
        else:
            j.rivals.find(j.party.id_for(seat)).position = destination
        j.rivals.random.state = 2
        j.rivals.plan(j, row)
        check(j.rivals.target == "knight:" + str(seat) and j.rivals.goal == destination, "AI considers every living human")
        roundtrip(j, "saved stable pursuit")
        var copy: RefCounted = Journey.new(Definition, Rules, 3)
        check(copy.restore_checkpoint(j.checkpoint()), "pursuit Continue")
        var attacker: int = j.party.turn
        j.rivals.arrived(j, row)
        var restored_row: Dictionary = copy.rivals.records[copy.rivals.active - 1]
        copy.rivals.arrived(copy, restored_row)
        check(j.party.active == seat and not j.party.awaiting and j.combat != null, "right human receives AI attack")
        check(j.party.turn == attacker and j.world.active_lair == j.party.id_for(attacker), "attacking AI keeps stable identity")
        check(j.checkpoint() == copy.checkpoint(), "continued pursuit reaches identical defender")
        roundtrip(j, "incoming AI encounter entrance")
    var protected: RefCounted = fresh(false)
    protected.rest()
    protected.begin_turn()
    protected.rest()
    var row: Dictionary = protected.rivals.records[protected.rivals.active - 1]
    var defender: Dictionary = protected.rivals.find(protected.party.id_for(0))
    defender.position = row.position
    defender.inventory.items.scroll_of_protection = 1
    protected.rivals.random.state = 2
    protected.rivals.plan(protected, row)
    protected.rivals.arrived(protected, row)
    check(protected.party.active == 0 and protected.attack_notice and protected.combat == null, "inactive human receives its own Protection choice")
    roundtrip(protected, "redirected Protection prompt")
    check(protected.resolve_pending_attack(true) and not protected.inventory.items.has("scroll_of_protection"), "redirected defender consumes its own scroll")
    roundtrip(protected, "redirected Protection resolution")

func malformed_saves() -> void:
    var j: RefCounted = Journey.new(Definition, Rules, 12345)
    var before: Dictionary = j.checkpoint()
    fixtures["legacy-solo"] = before.duplicate(true)
    for value in [null, "invalid", 3, true, [], [1, 2], {"stones": "invalid"}, {"stones": []}]:
        var bad: Dictionary = before.duplicate(true)
        bad.quest = value
        check(not j.restore_checkpoint(bad) and j.checkpoint() == before, "malformed quest rejected without mutation")
    var store: RefCounted = Store.new("user://unit-cleanup.json", j.validate_checkpoint)
    check(store.save_checkpoint(before) and store.save_checkpoint(before), "valid primary and backup written")
    var bad: Dictionary = before.duplicate(true)
    bad.quest = "invalid"
    var body: String = JSON.stringify(bad)
    var file := FileAccess.open(store.path, FileAccess.WRITE)
    file.store_string(JSON.stringify({"format": "moonstone.journey", "version": 1, "data": body, "sha256": body.sha256_text()}))
    file.close()
    check(store.load_checkpoint() == before and store.last_source.ends_with(".bak"), "rehashed malformed quest recovers backup without script errors")

func write_fixtures() -> void:
    for argument in OS.get_cmdline_user_args():
        if not argument.begins_with("--fixture-dir="):
            continue
        var folder: String = argument.trim_prefix("--fixture-dir=")
        check(DirAccess.make_dir_recursive_absolute(folder) == OK, "create acceptance fixture directory")
        for name in fixtures:
            var body: String = JSON.stringify(fixtures[name])
            var file := FileAccess.open(folder.path_join(name + ".json"), FileAccess.WRITE)
            check(file != null, "create acceptance fixture")
            if file != null:
                file.store_string(JSON.stringify({"format": "moonstone.journey", "version": 1, "data": body, "sha256": body.sha256_text()}))
                file.close()

func _initialize() -> void:
    quest_loot()
    dragon_catches()
    ai_targets()
    malformed_saves()
    if failures == 0:
        write_fixtures()
    if failures == 0:
        print("PASS: ", checks, " cleanup regression checks: quest loot ownership, Dragon order settlement, stable AI targets, malformed-save recovery")
    quit(0 if failures == 0 else 1)
