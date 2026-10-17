extends SceneTree

const Journey = preload("res://scripts/session/journey_session.gd")
var failures: int = 0

func check(condition: bool, label: String) -> void:
    if not condition:
        failures += 1
        push_error(label)

func _initialize() -> void:
    var definition: Resource = load("res://scripts/content/world_definition.gd").new()
    var journey: RefCounted = Journey.new(definition, load("res://content/foundation_rules.tres"), 12)
    check(definition.lairs.size() == 24 and definition.towns.size() == 2, "expanded layout has twenty-four lairs and two towns")
    var ids: Dictionary = {}
    var regions: Dictionary = {}
    for site in definition.lairs:
        check(not ids.has(site.id) and definition.bounds.has_point(site.position), "unique reachable lair IDs/coordinates")
        ids[site.id] = true
        regions[site.region] = int(regions.get(site.region, 0)) + 1
        for other in definition.lairs:
            if site.id != other.id: check(site.position.distance_squared_to(other.position) > definition.entry_radius * definition.entry_radius * 4, "entrance circles do not overlap")
    check(regions.size() == 4 and regions.values().all(func(count: int) -> bool: return count == 6), "six lairs per region")
    check(definition.lairs.size() * journey.character_rules.lair_experience / journey.upgrade_cost() == 8, "run supports eight naturally earned solo upgrades")
    journey.character.experience = 3
    journey.inventory.gold = 150
    check(not journey.buy_equipment("broad_sword") and not journey.upgrade_stat("strength") and not journey.buy_healing("heal_health"), "map shortcuts cannot bypass town services")
    check(not journey.enter_town("highwood") and not journey.open_service("smith"), "distant or absent town rejected")
    journey.world.position = Vector2i(74,28)
    for tick in range(20):
        journey.travel(Vector2i.RIGHT)
        if not journey.town_id.is_empty(): break
    check(journey.town_id == "highwood" and journey.combat == null, "walking into Highwood starts a visit, not combat")
    var position: Vector2i = journey.world.position
    for tick in range(20): journey.travel(Vector2i.RIGHT)
    check(journey.world.position == position, "town visit freezes travel")
    check(journey.open_service("smith") and journey.buy_equipment("broad_sword") and journey.inventory.gold == 140, "town smith uses actual equipment transaction")
    check(not journey.upgrade_stat("constitution"), "smith cannot spend temple experience")
    check(journey.open_service("temple") and journey.upgrade_stat("constitution") and journey.character.health == 30 and journey.character.experience == 0, "High Temple spends XP on actual stat/health")
    check(journey.open_service("healer"), "town healer can be visited")
    journey.character.health = 9
    journey.character.lives = 3
    check(not journey.buy_healing("heal_life") and journey.inventory.gold == 140, "full health required before buying lives")
    check(journey.buy_healing("heal_health") and journey.character.health == 30 and journey.inventory.gold == 130, "ten gold fully heals")
    check(not journey.buy_healing("heal_health") and journey.inventory.gold == 130, "full health is not charged again")
    check(journey.buy_healing("heal_life") and journey.character.lives == 4 and journey.inventory.gold == 115, "fifteen gold buys one life")
    journey.inventory.gold = 0
    check(not journey.buy_healing("heal_life") and journey.character.lives == 4, "unaffordable healing refuses mutation")
    check(journey.leave_town() and journey.day == 2 and journey.town_lock == "highwood", "town exit ends the day and locks its entry ring")
    journey.begin_turn()
    journey.travel(Vector2i.RIGHT)
    check(journey.town_id.is_empty(), "leaving does not immediately reopen the same town")
    journey.world.position = journey.town("waterdeep").position
    check(journey.enter_town("waterdeep") and not journey.open_service("temple") and journey.open_service("smith"), "Waterdeep has smith/healer; no invented High Temple service")
    var before: int = journey.day
    journey.leave_town()
    check(journey.day == before + 1, "both town exits consume a travel day")
    var art: Resource = load("res://assets/classic/world/art.tres")
    check(art.highwood != null and art.waterdeep != null, "both recovered town backdrops are available")
    if failures == 0: print("PASS: 24 unique disjoint lairs, six per region/eight upgrades, located town entry/freeze/exit, smith/temple/healer prices and locks, Waterdeep service boundary")
    quit(1 if failures else 0)
