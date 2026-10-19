extends RefCounted

const Host=preload("res://scripts/domain/entry_placement_host.gd")
const Model=preload("res://scripts/domain/combat_simulation.gd")
const Journey=preload("res://scripts/session/journey_session.gd")
var rules: Resource=preload("res://content/foundation_rules.tres")
var checks: int=0
var failures: Array[String]=[]

func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failures.append(label)

func run_checks(path: String) -> Dictionary:
    var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
    if not data is Dictionary or not data.has_all(["cases","sites"]):return {"checks":0,"failures":["Missing numeric entry reference"]}
    for row in data.cases:
        var state: Dictionary={"profile":"classic:beast_entry","api":1,"version":1,"low_edge":int(row.low_edge),"counter":int(row.counter)}
        var depth: int=Host.next(rules,state)
        check(depth==int(row.expected_depth) and state.counter==int(row.expected_counter),"independent original depth/counter "+str(row))
    var sites: Array=[]
    for site in data.sites:
        for mode in [&"competitive",&"cooperative"]:
            var edge: int=int(data.sites[site].low_edge)
            var expected: Array=[edge+(200-edge)/4+5,edge+(200-edge)/2+5,edge+(200-edge)/2+((200-edge)/2)/2+5]
            var m: RefCounted=Model.new(rules)
            m.start(mode,0,&"beast_lair",{"count":9,"concurrent":3,"arena_site":site})
            var first: Array=[]
            var consumed: int=1 if mode==&"competitive" else 2
            for id in range(10,13):
                var actor: Dictionary=m.actors[id]
                var wanted: int=int(expected[(id-10+consumed-1)%3])
                first.append(actor.y)
                check(actor.y==wanted and actor.leap_from_y==wanted and actor.leap_to_y==wanted,"initial lane and factory anchors")
                check(actor.x==(-60 if id%2==0 else 360) and actor.cooldown_remaining==50 and actor.health==10,"offscreen x, entry wait and health retained")
            check(first[0]!=first[2] and m.actors[1].y==166,"same-side entrants separated; current knight setup retained")
            check(m.entry_state.low_edge==edge,"actual site chooses its obstacle edge")
            for n in range(6):
                m.actors[10+n].health=0;m.fill_wave_slots()
                var id: int=13+n
                check(m.actors[id].y==int(expected[(id-10+consumed-1)%3]),"replacement advances shared entry cursor")
            check(m.spawn_remaining==0 and m.actors.size()==(10 if mode==&"competitive" else 11),"nine entrants only; no wave mutation")
            var snap: Dictionary=m.snapshot();snap.entry_state.counter=99
            check(m.entry_state.counter!=99,"snapshot cursor is copied")
            # Re-aiming uses the knight's current position only after a full pass.
            var a: Dictionary=m.actors[18];a.beast_pass=0;a.x=-60
            var lane: int=a.y
            m.actors[1].y=139
            if m.actors.has(2):m.actors[2].y=139
            m.begin_beast_pass(a)
            check(a.y==lane,"opening charge cannot home on a moved player")
            a.x=392;m.begin_beast_pass(a)
            check(a.x==380 and a.facing==-1 and a.y==139,"return charge still samples target after clearing edge")
            sites.append({"site":site,"mode":String(mode),"edge":edge,"first_depths":first,"total":9})
    var j: RefCounted=Journey.new(preload("res://content/first_journey.tres"),rules,0x4d4f4f4e)
    j.character.stats.strength=4;j.character.stats.constitution=5;j.character.health=60;j.character.weapon="claymore"
    j.character.experience=11;j.inventory.gold=71
    j.world.active_lair="grassland_east";j.start_site_combat()
    check(j.combat.simulation.actors[10].y==147 and j.combat.simulation.actors[11].y==166 and j.combat.simulation.actors[12].y==185,"real journey passes correct site and scaled slots")
    var before: Dictionary=j.checkpoint()
    var resumed: RefCounted=Journey.new(preload("res://content/first_journey.tres"),rules,1)
    check(resumed.restore_checkpoint(before),"current Continue remains loadable")
    check(resumed.character.snapshot()==j.character.snapshot() and resumed.inventory==j.inventory and resumed.lair_loot==j.lair_loot,"Continue retains character, XP, gold and rolls")
    resumed.world.active_lair="grassland_east";resumed.start_site_combat()
    check(resumed.combat.simulation.entry_state==j.combat.simulation.entry_state,"entrance checkpoint produces same cursor")
    var a: RefCounted=preload("res://scripts/session/local_session.gd").new(rules)
    var b: RefCounted=preload("res://scripts/session/local_session.gd").new(rules)
    a.start(&"competitive",&"beast_lair");b.start(&"competitive",&"beast_lair")
    for n in range(300):a.advance(Vector2i.ZERO,"idle");b.advance(Vector2i.ZERO,"idle")
    check(a.simulation.snapshot()==b.simulation.snapshot(),"fixed command replay includes entry cursor")
    check(j.checkpoint().schema==16 and j.combat.simulation.snapshot().schema==25,"campaign unchanged; combat cursor versioned")
    return {"checks":checks,"failures":failures,"reference_cases":data.cases.size(),"sites":sites,"combat_schema":24,"campaign_schema":16}

func report(host: Node,path: String) -> void:
    var result: Dictionary=run_checks(path)
    print("ENTRY_LANES_STATE=",JSON.stringify(result))
    if result.failures.is_empty():print("PASS:",result.checks," entry arithmetic, actual setup/refills, replay and Continue checks")
    else:print("FAIL:",JSON.stringify(result.failures.slice(0,8)))
    host.get_tree().quit(0 if result.failures.is_empty() else 1)
