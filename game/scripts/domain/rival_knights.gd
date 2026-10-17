extends RefCounted

# Independent native campaign records. The reference solo game uses kind4 for
# all three AI slots: map cels4/9 (inactive/active),33 when out of lives.
const IDS=["roaming_black_knight","rival_knight_2","rival_knight_3"]
const STARTS=[Vector2i(300,100),Vector2i(160,20),Vector2i(160,180)] # LAB_01AE AI slots1..3.
const Knight=preload("res://scripts/domain/knight_progression.gd")
const Math = preload("res://scripts/domain/character_math.gd")
const Roller=preload("res://scripts/domain/loot_roller.gd")
const Locations=preload("res://scripts/domain/map_locations.gd")
const TRANSFER=["sword_of_sharpness","ring_of_protection","scroll_of_acquisition","scroll_of_protection","talisman_of_the_wyrm","scroll_of_the_hawk","scroll_of_the_wyrm","healing_potion","gem_of_seeing","scroll_of_haste"]
var records: Array[Dictionary]=[]
var active: int=0 # 0=human,1..3=rival. Paused intact by encounters and menus.
var spent: int=0
var budget: int=0
var ticks: int=0
var terrain: int=0
var target: String=""
var goal:=Vector2i.ZERO
var walk: Array[int]=[] # dx,dy,x sign,y sign,error,major axis
var random: RefCounted
var rules: Resource

func _init(definition: Resource,character_rules: Resource,loot_rules: Resource,seed: int) -> void:
    rules=character_rules
    random=Roller.new(loot_rules,maxi(2,(seed^0x52495641)&0xffffffff))
    if not definition.rival_turns:return
    for index in range(3):
        var position: Vector2i=STARTS[index]
        position=position.clamp(definition.bounds.position,definition.bounds.end-Vector2i.ONE)
        records.append({"id":IDS[index],"position":position,"character":Knight.new(rules).snapshot(),"inventory":{"gold":int(rules.starting_gold),"items":{}},"keys":0,"stones":0,"loot_ready":false})

func find(id: String) -> Dictionary:
    for row in records:
        if row.id==id:return row
    return {}

func knight(row: Dictionary) -> RefCounted:
    var result: RefCounted=Knight.new(rules)
    for field in row.character:result.set(field,row.character[field].duplicate(true) if typeof(row.character[field])==TYPE_DICTIONARY else row.character[field])
    return result

func snapshot() -> Dictionary:
    var rows: Array=[]
    for row in records:
        var copy: Dictionary=row.duplicate(true)
        copy.position={"x":row.position.x,"y":row.position.y}
        rows.append(copy)
    return {"records":rows,"active":active,"spent":spent,"budget":budget,"ticks":ticks,"terrain":terrain,"target":target,"goal":{"x":goal.x,"y":goal.y},"walk":walk.duplicate(),"seed":random.state,"last_slot":random.last_slot}

func restore(data: Dictionary) -> void:
    records.clear()
    for source in data.records:
        var row: Dictionary=source.duplicate(true)
        row.position=Vector2i(int(row.position.x),int(row.position.y));records.append(row)
    active=int(data.active);spent=int(data.spent);budget=int(data.budget)
    ticks=int(data.ticks);terrain=int(data.terrain);target=data.target
    goal=Vector2i(int(data.goal.x),int(data.goal.y));walk.assign(data.walk)
    random.state=int(data.seed);random.last_slot=int(data.last_slot)

func start() -> void:
    active=1
    clear_path()

func clear_path() -> void:
    spent=0;budget=0;ticks=0;target="";goal=Vector2i.ZERO;walk.clear()

func finish_slot(journey: RefCounted) -> void:
    if journey.party!=null:
        active=0;clear_path();journey.party.next_turn(journey);return
    active+=1
    clear_path()
    if active>3:
        active=0
        journey.complete_round()

func shop_wish(row: Dictionary) -> String:
    var kit: RefCounted=knight(row)
    var gold: int=row.inventory.gold
    if gold>25 and kit.lives<=2:return "life"
    for id in ["battleplate","platemail","chainmail"]:
        if gold>=int(rules.armours[id].price) and int(rules.armours[id].rank)>int(rules.armours[kit.armour].rank):return id
    for id in ["claymore","broad_sword"]:
        if gold>=int(rules.weapons[id].price) and int(rules.weapons[id].rank)>int(rules.weapons[kit.effective_weapon(row.inventory.items)].rank):return id
    if kit.daggers<=5 and gold>=int(rules.dagger_price):return "dagger"
    return ""

func plan(journey: RefCounted,row: Dictionary) -> void:
    var kit: RefCounted=knight(row)
    # LAB_0E23: potion when lives<=3 or HP below a quarter, not free healing.
    if (kit.lives<=3 or kit.health<(kit.maximum(row.inventory.items)>>2)) and int(row.inventory.items.get("healing_potion",0))>0 and kit.heal(row.inventory.items):consume(row,"healing_potion")
    row.character=kit.snapshot()
    var stats: Array=[]
    for stat in kit.stats:
        if kit.stats[stat]<int(rules.stat_limit):stats.append(stat)
    var cost: int=journey.upgrade_cost()
    if not stats.is_empty() and kit.experience>=cost:
        kit.upgrade(stats[random.next_value()%stats.size()],cost,row.inventory.items)
        row.character=kit.snapshot()
    budget=kit.endurance()*int(rules.travel_per_endurance)
    var sites: Array=journey.world.definition.lairs.filter(func(site: Dictionary) -> bool:return not journey.world.cleared.has(site.id) or journey.has_treasure(site.id))
    sites.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
        var da: int=distance(row.position,a.position);var db: int=distance(row.position,b.position)
        return da<db if da!=db else String(a.id)<String(b.id))
    var pursue: bool=sites.is_empty() or (random.next_value()&127)<=25
    if pursue:
        target = "player"
        goal = journey.world.position
        if journey.party != null:
            var destination: Dictionary = journey.party.pursuit(journey, row.position)
            if not destination.is_empty():
                target = destination.target
                goal = destination.goal
        if distance(row.position,goal)>=budget and int(row.inventory.items.get("scroll_of_haste",0))>0:
            consume(row,"scroll_of_haste");budget*=2
    elif not shop_wish(row).is_empty():
        var towns: Array=journey.world.definition.towns.duplicate()
        towns.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:return distance(row.position,a.position)<distance(row.position,b.position))
        target=towns[0].id;goal=towns[0].position
    else:
        # LAB_0DEA selects sorted index1..3, skipping the nearest row.
        var index: int=1+(random.next_value()%3)
        index=mini(index,sites.size()-1)
        target=sites[index].id;goal=sites[index].position
    var delta: Vector2i=goal-row.position
    walk.assign([abs(delta.x),abs(delta.y),signi(delta.x),signi(delta.y),maxi(abs(delta.x),abs(delta.y)),int(abs(delta.y)>abs(delta.x))])

static func distance(a: Vector2i,b: Vector2i) -> int:
    return absi(a.x-b.x)+absi(a.y-b.y)

func consume(row: Dictionary,id: String) -> void:
    row.inventory.items[id]-=1
    if row.inventory.items[id]<=0:row.inventory.items.erase(id)

func advance(journey: RefCounted) -> void:
    if active==0 or journey.combat!=null or not journey.pending_attack.is_empty():return
    var row: Dictionary=records[active-1]
    if row.character.lives<=0:finish_slot(journey);journey.persist();return
    if target.is_empty():plan(journey,row);journey.persist()
    if spent>=budget:finish_slot(journey);journey.persist();return
    ticks+=1
    if ticks%maxi(1,journey.world.definition.ticks_per_step)!=0:return
    if arrived(journey,row):return
    var mask: int=0 if journey.world.definition.travel_rules==null else journey.world.definition.travel_rules.mask_at(row.position)
    if mask!=0:
        terrain=(terrain+1)&65535
        if (terrain&mask)!=0:return
    var direction:=Vector2i.ZERO
    # LAB_0E0C..15 line walk. Terrain delays don't advance the error or budget.
    if walk[5]==0:
        direction.x=walk[2];walk[4]-=walk[1]
        if walk[4]<0:walk[4]+=walk[0];direction.y=walk[3]
    else:
        direction.y=walk[3];walk[4]-=walk[0]
        if walk[4]<0:walk[4]+=walk[1];direction.x=walk[2]
    row.position=(row.position+direction).clamp(journey.world.definition.bounds.position,journey.world.definition.bounds.end-Vector2i.ONE)
    spent+=1
    if arrived(journey,row):return
    if ticks%50==0:journey.persist()

static func target_seat(id: String) -> int:
    return ["knight:0", "knight:1", "knight:2", "knight:3"].find(id)

func arrived(journey: RefCounted,row: Dictionary) -> bool:
    var seat: int = target_seat(target)
    var pursuing: bool = target == "player" or seat >= 0
    var size := Vector2i(8, 10) if pursuing else Locations.size_for(journey.town(target) if target in ["highwood", "waterdeep"] else journey.world.lair(target))
    if not Locations.touches(row.position,goal,size):return false
    spent=budget
    if seat >= 0 and journey.party != null:
        journey.party.receive_attack(journey, seat)
    elif target=="player":
        journey.begin_rival_encounter(row.id,true)
    else:
        if target in ["highwood","waterdeep"]:shop(row)
        # Original aiArrival ends at the roam lair; it never calls fightCreature.
        finish_slot(journey)
    journey.persist()
    return true

func shop(row: Dictionary) -> void:
    var id: String=shop_wish(row)
    if id.is_empty():return
    var kit: RefCounted=knight(row)
    var before: int=kit.maximum(row.inventory.items)
    if id=="life":row.inventory.gold-=25;kit.lives=mini(int(rules.life_limit),kit.lives+1);kit.health=before
    elif rules.armours.has(id):row.inventory.gold-=int(rules.armours[id].price);kit.armour=id;kit.health+=kit.maximum(row.inventory.items)-before
    elif rules.weapons.has(id):row.inventory.gold-=int(rules.weapons[id].price);kit.weapon=id
    else:
        var amount: int=mini(int(rules.dagger_limit)-kit.daggers,int(row.inventory.gold)/int(rules.dagger_price))
        row.inventory.gold-=amount*int(rules.dagger_price);kit.daggers+=amount
    row.character=kit.snapshot()

func upkeep(completed_rounds: int,human_ids: Array=[]) -> void:
    for row in records:
        if row.character.lives<=0:continue
        var kit: RefCounted=knight(row)
        # LAB_0030 invokes Math only at the four-round lunar turnover.
        if completed_rounds%4==0 and row.id not in human_ids:
            for attempt in range(1024):
                var roll: int=(random.percent()+255)&255
                if roll<=30:
                    var id: String=random.item(row.inventory.items)
                    if int(row.inventory.items[id])>255:row.inventory.items[id]=255
                    if id=="ring_of_protection":kit.health+=int(rules.protection_health)
                    break
                if roll<=70:
                    var available: Array=[]
                    for stat in kit.stats:
                        if kit.stats[stat]<int(rules.stat_limit):available.append(stat)
                    if available.is_empty():continue
                    var stat: String=available[random.next_value()%available.size()]
                    kit.stats[stat]+=1
                    if stat=="constitution":kit.health+=int(rules.constitution_health)
                    break
                if roll<=90:row.inventory.gold=mini(int(rules.gold_limit),int(row.inventory.gold)+random.gold());break
                # Original AI recency255 rerolls the frog outcome.
        kit.rest(row.inventory.items)
        row.character=kit.snapshot()

static func valid(data: Variant,definition: Resource,character_rules: Resource,loot_rules: Resource,integer: Callable,party_context: bool=false) -> bool:
    if typeof(data)!=TYPE_DICTIONARY or data.size()!=11 or typeof(data.get("records"))!=TYPE_ARRAY:return false
    if data.records.size()!=(3 if definition.rival_turns else 0):return false
    for field in ["active","spent","budget","ticks","terrain","seed","last_slot"]:
        var limits: Array={"active":[0,3 if definition.rival_turns else 0],"spent":[0,1024],"budget":[0,1024],"ticks":[0,100000],"terrain":[0,65535],"seed":[2,0xffffffff],"last_slot":[-1,18]}[field]
        if not integer.call(data.get(field),limits[0],limits[1]):return false
        data[field]=int(data[field])
    if data.last_slot not in [-1,0,2,4,6,8,10,12,14,16,18] or data.spent>data.budget:return false
    if typeof(data.get("goal"))!=TYPE_DICTIONARY or data.goal.size()!=2:return false
    for field in ["x","y"]:
        if not integer.call(data.goal.get(field),0,320 if field=="x" else 200):return false
        data.goal[field]=int(data.goal[field])
    var targets: Array=["","player","highwood","waterdeep"]
    if party_context:
        targets.append_array(["knight:0", "knight:1", "knight:2", "knight:3"])
    for site in definition.lairs:targets.append(site.id)
    if typeof(data.get("target"))!=TYPE_STRING or data.target not in targets:return false
    if typeof(data.get("walk"))!=TYPE_ARRAY or data.walk.size()!=(0 if data.target=="" else 6):return false
    for index in range(data.walk.size()):
        var limits: Array=[[0,320],[0,200],[-1,1],[-1,1],[0,320],[0,1]][index]
        if not integer.call(data.walk[index],limits[0],limits[1]):return false
        data.walk[index]=int(data.walk[index])
    if data.target=="" and (data.budget!=0 or data.spent!=0 or data.ticks!=0 or data.goal!={"x":0,"y":0}):return false
    if data.active==0 and data.target!="":return false
    if data.target!="" and data.budget<1:return false
    for index in range(data.records.size()):
        var row: Variant=data.records[index]
        if typeof(row)!=TYPE_DICTIONARY or row.size()!=7 or row.get("id")!=IDS[index] or typeof(row.get("loot_ready"))!=TYPE_BOOL:return false
        if typeof(row.get("position"))!=TYPE_DICTIONARY or row.position.size()!=2:return false
        for field in ["x","y"]:
            var low: int=definition.bounds.position.x if field=="x" else definition.bounds.position.y
            var high: int=definition.bounds.end.x-1 if field=="x" else definition.bounds.end.y-1
            if not integer.call(row.position.get(field),low,high):return false
            row.position[field]=int(row.position[field])
        if typeof(row.get("inventory"))!=TYPE_DICTIONARY or row.inventory.size()!=2:return false
        var inv: Dictionary=row.inventory
        if not integer.call(inv.get("gold"),0,character_rules.gold_limit) or typeof(inv.get("items"))!=TYPE_DICTIONARY:return false
        inv.gold=int(inv.gold)
        for id in inv.items:
            if not loot_rules.items.has(id) or not integer.call(inv.items[id],1,255):return false
            inv.items[id]=int(inv.items[id])
        for field in ["keys","stones"]:
            if not integer.call(row.get(field),0,15):return false
            row[field]=int(row[field])
        var c: Variant=row.get("character")
        if typeof(c)!=TYPE_DICTIONARY or c.size()!=8 or typeof(c.get("stats"))!=TYPE_DICTIONARY or c.stats.size()!=3:return false
        for stat in ["strength","constitution","endurance"]:
            if not integer.call(c.stats.get(stat),1,character_rules.stat_limit):return false
            c.stats[stat]=int(c.stats[stat])
        if not character_rules.weapons.has(c.get("weapon")) or c.weapon=="sword_of_sharpness" or not character_rules.armours.has(c.get("armour")):return false
        var max_hp: int = Math.maximum_health(character_rules, c.stats.constitution, c.armour, inv.items)
        for field in ["health","lives","daggers","experience","life_loss"]:
            var high: int={"health":max_hp,"lives":character_rules.life_limit,"daggers":character_rules.dagger_limit,"experience":65535,"life_loss":255}[field]
            if not integer.call(c.get(field),0,high):return false
            c[field]=int(c[field])
        if (c.health==0)!=(c.lives==0):return false
    return true
