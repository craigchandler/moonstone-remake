extends RefCounted
const Roller=preload("res://scripts/domain/loot_roller.gd")
const ITEMS=["healing_potion","gem_of_seeing","sword_of_sharpness","ring_of_protection","talisman_of_the_wyrm","scroll_of_haste","scroll_of_the_hawk","scroll_of_acquisition","scroll_of_the_wyrm","scroll_of_protection"]
const BANDS=[25,35,45,55,65,75,85,80,94,100] # source slots12/14 are Hawk/Acquisition.
const STATS=["strength","endurance","constitution","endurance","strength","endurance","constitution","constitution","strength"]
const PRICES=[20,32,52,40,52,36,52,52,40,24]
const DICE=[[0,0,1,4],[0,0,2,5],[0,0,4,6],[0,0,3,8],[0,0,5,10],[2,2,2,12],[4,4,4,14],[3,3,3,16],[5,5,5,18],[1,1,1,20],[0,0,0,30]]
static func visit(kind: String) -> Dictionary:
    return {"kind":kind,"phase":"tavern" if kind=="tavern" else "greeting","tick":0,"result":"","subject":"","amount":0,"row":0,"bet":0,"dice":[],"payout":0,"donation":0}
static func initial(j: RefCounted) -> Dictionary:
    return initial_from(j.reward_seed,j.loot_rules)
static func initial_from(seed: int,loot_rules: Resource) -> Dictionary:
    var state: Dictionary={"seed":maxi(2,(seed^0x544f574e)&0xffffffff),"last_slot":-1,"item_cycle":0,"gold_cycle":0,"recency":0,"frog_days":0,"market":{"items":{},"keys":0,"stones":0},"visit":{}}
    var rng: RefCounted=Roller.new(loot_rules,state.seed)
    for n in range(6):gift(rng,state,state.market.items)
    state.market.items.talisman_of_the_wyrm=int(state.market.items.get("talisman_of_the_wyrm",0))+2
    state.seed=rng.state
    return state
static func gift(rng: RefCounted,state: Dictionary,items: Dictionary) -> String:
    for attempt in range(4096):
        var roll: int=rng.percent()
        var id: String="scroll_of_protection"
        var order: Array=[0,1,2,3,4,5,7,6,8,9]
        for index in order:
            if roll<=BANDS[index]:id=ITEMS[index];break
        var slot: int=ITEMS.find(id)*2
        if state.last_slot==slot:continue
        state.last_slot=slot
        if id=="sword_of_sharpness" and int(items.get(id,0))>0:continue
        if int(items.get(id,0))>=255:continue
        items[id]=int(items.get(id,0))+1
        return id
    return ""
static func pick_stat(j: RefCounted,rng: RefCounted) -> Dictionary:
    if j.character.stats.values().all(func(v: int) -> bool:return v>=5):return {}
    for attempt in range(4096):
        var row: int=rng.next_value()&15
        if row>8:row-=7
        var stat: String=STATS[row]
        if j.character.stats[stat]<5:return {"stat":stat,"row":row}
    return {}
static func change_stat(j: RefCounted,stat: String,delta: int) -> void:
    var old: int=j.character.stats[stat]
    j.character.stats[stat]=clampi(old+delta,1,5)
    if stat=="constitution":j.character.health=clampi(j.character.health+(j.character.stats[stat]-old)*10,1,j.character.maximum(j.inventory.items))
static func wizard_roll(j: RefCounted) -> void:
    var s: Dictionary=j.places;var v: Dictionary=s.visit
    var rng: RefCounted=Roller.new(j.loot_rules,s.seed)
    for attempt in range(4096):
        var roll: int=(rng.percent()+int(s.recency))&255
        if roll<=30:
            var id: String=gift(rng,s,j.inventory.items)
            if id.is_empty():continue
            if id=="ring_of_protection":j.character.health+=20
            s.item_cycle=(int(s.item_cycle)+1)&3
            v.result="item";v.subject=id;v.row=s.item_cycle;break
        elif roll<=70:
            var picked: Dictionary=pick_stat(j,rng)
            if picked.is_empty():continue
            change_stat(j,picked.stat,1);v.result="stat";v.subject=picked.stat;v.row=picked.row;break
        elif roll<=90:
            var amount: int=rng.gold()
            j.inventory.gold=mini(150,int(j.inventory.gold)+amount)
            s.gold_cycle=(int(s.gold_cycle)+1)%3
            v.result="gold";v.amount=amount;v.row=s.gold_cycle;break
        else:
            s.frog_days=3;v.result="frog";break
    s.seed=rng.state
    v.phase="gift";v.tick=0
static func open(j: RefCounted,kind: String) -> void:
    if not j.places.visit.is_empty() and j.places.visit.kind==kind:return
    j.places.visit=visit(kind)
static func advance_wizard(j: RefCounted) -> bool:
    var v: Dictionary=j.places.visit
    if v.get("kind")!="wizard":return false
    if v.phase=="greeting":wizard_roll(j)
    elif v.phase=="gift":v.phase="omen";v.tick=0
    elif v.phase=="omen":v.phase="sheet";v.tick=0;j.places.recency=70;j.service="temple"
    else:return false
    j.persist();return true
static func donate(j: RefCounted,amount: int) -> bool:
    var v: Dictionary=j.places.visit
    if j.town_id.is_empty() or j.service not in ["healer","mystic"] or v.get("kind")!=j.service or v.get("phase")!="donation" or amount<0 or amount>int(j.inventory.gold):return false
    j.inventory.gold-=amount;v.amount=amount;v.donation=0;v.phase="reply";v.tick=0
    if amount==0:v.result="none"
    elif j.service=="healer":
        # The original commits the entire donation. Safe arithmetic avoids its
        # 10..14gp life-price underflow and still clears life-drain at10gp.
        var remaining: int=amount
        v.result="tiny" if amount<10 else "plain"
        if amount>=10:j.character.life_loss=0
        if remaining>=10 and j.character.health<j.character.maximum(j.inventory.items):
            j.character.health=j.character.maximum(j.inventory.items);remaining-=10;v.result="healed"
        while remaining>=15 and j.character.lives<5:j.character.lives+=1;remaining-=15;v.result="healed"
    else:
        var rng: RefCounted=Roller.new(j.loot_rules,j.places.seed)
        var picked: Dictionary=pick_stat(j,rng)
        var bonus: int=20 if amount<=9 else 10 if amount<=19 else 0 if amount<=29 else -10 if amount<=39 else -20 if amount<=49 else -30
        var wins: bool=rng.percent()+bonus>=50
        v.result="unchanged" if picked.is_empty() else "raise" if wins else "unchanged" if j.character.stats[picked.stat]==1 else "lower"
        if not picked.is_empty():
            v.subject=picked.stat
            if v.result in ["raise","lower"]:change_stat(j,picked.stat,1 if wins else -1)
        j.places.seed=rng.state
    j.persist();return true
static func wager(j: RefCounted,bet: int) -> bool:
    var v: Dictionary=j.places.visit
    if j.town_id.is_empty() or j.service!="tavern" or v.get("kind")!="tavern" or v.get("phase")!="tavern" or bet<1 or bet>5 or bet>int(j.inventory.gold):return false
    var rng: RefCounted=Roller.new(j.loot_rules,j.places.seed)
    var dice: Array=[]
    for n in range(3):
        for attempt in range(4096):
            var face: int=rng.next_value()&7
            if face<6:dice.append(face);break
    var sorted: Array=dice.duplicate();sorted.sort();var multiplier: int=0
    for row in DICE:
        if sorted==row.slice(0,3):multiplier=row[3];break
    j.inventory.gold=mini(150,int(j.inventory.gold)-bet+bet*multiplier)
    j.places.seed=rng.state
    v.bet=bet;v.dice=dice;v.payout=bet*multiplier;v.phase="rolling";v.tick=0
    j.persist();return true
static func price(j: RefCounted,id: String) -> int:
    if j.REGIONAL_KEYS.has(id):return 12
    if id in j.quest_rules.stone_ids:return 20
    return PRICES[ITEMS.find(id)] if id in ITEMS else 0
static func trade(j: RefCounted,id: String,buy: bool) -> bool:
    if not j.on_map() or j.town_id!="highwood" or j.service!="temple":return false
    var market: Dictionary=j.places.market
    var source: Dictionary=market if buy else {"items":j.inventory.items,"keys":j.owned_keys,"stones":j.quest.stones}
    var target: Dictionary={"items":j.inventory.items,"keys":j.owned_keys,"stones":j.quest.stones} if buy else market
    var cost: int=price(j,id)
    if cost<=0 or (buy and j.inventory.gold<cost) or (not buy and int(j.inventory.gold)>=150):return false
    if j.REGIONAL_KEYS.has(id) or id in j.quest_rules.stone_ids:
        var field: String="keys" if j.REGIONAL_KEYS.has(id) else "stones"
        var bit: int=j.REGIONAL_KEYS[id].bit if field=="keys" else 1<<j.quest_rules.stone_ids.find(id)
        if not(int(source[field])&bit) or int(target[field])&bit:return false
        source[field]=int(source[field])&~bit;target[field]=int(target[field])|bit
    else:
        if int(source.items.get(id,0))<1 or int(target.items.get(id,0))>=255:return false
        source.items[id]-=1
        if source.items[id]==0:source.items.erase(id)
        target.items[id]=int(target.items.get(id,0))+1
        if id=="ring_of_protection":j.character.health=mini(j.character.health+20,j.character.maximum(j.inventory.items)) if buy else mini(j.character.health,j.character.maximum(j.inventory.items))
    var human: Dictionary=target if buy else source
    j.owned_keys=human.keys;j.quest.stones=human.stones
    j.inventory.gold=mini(150,int(j.inventory.gold)-cost if buy else int(j.inventory.gold)+(cost>>1))
    j.message="Bought "+id.replace("_"," ")+"." if buy else "Sold "+id.replace("_"," ")+"."
    j.persist();return true
static func valid(data: Dictionary,integer: Callable,loot_rules: Resource) -> bool:
    var s: Variant=data.get("places")
    if typeof(s)!=TYPE_DICTIONARY or s.size()!=8:return false
    for field in ["seed","last_slot","item_cycle","gold_cycle","recency","frog_days"]:
        var limits: Array={"seed":[2,0xffffffff],"last_slot":[-1,18],"item_cycle":[0,3],"gold_cycle":[0,2],"recency":[0,70],"frog_days":[0,3]}[field]
        if not integer.call(s.get(field),limits[0],limits[1]):return false
        s[field]=int(s[field])
    if s.last_slot not in [-1,0,2,4,6,8,10,12,14,16,18]:return false
    if typeof(s.get("market"))!=TYPE_DICTIONARY or s.market.size()!=3:return false
    for field in ["keys","stones"]:
        if not integer.call(s.market.get(field),0,15):return false
        s.market[field]=int(s.market[field])
    if typeof(s.market.get("items"))!=TYPE_DICTIONARY:return false
    for id in s.market.items:
        if id not in loot_rules.items or not integer.call(s.market.items[id],1,255):return false
        s.market.items[id]=int(s.market.items[id])
    var v: Variant=s.get("visit")
    if typeof(v)!=TYPE_DICTIONARY:return false
    if v.is_empty():return data.town_id!="wizard"
    if v.size()!=11 or typeof(v.get("kind"))!=TYPE_STRING or v.kind not in ["wizard","healer","mystic","tavern"]:return false
    if data.phase!="map" or data.town_id=="" or data.turn_pending or data.rivals.active!=0:return false
    if v.kind=="wizard":
        if data.town_id!="wizard" or data.service not in (["","temple"] if v.get("phase")=="sheet" else ["temple"]) or v.get("phase") not in ["greeting","gift","omen","sheet"]:return false
    elif data.service!=v.kind or data.town_id not in ["highwood","waterdeep"] or (v.kind=="mystic" and data.town_id!="waterdeep"):return false
    if v.kind!="wizard" and v.get("phase") not in (["tavern","rolling","dice"] if v.kind=="tavern" else ["greeting","donation","reply"]):return false
    for field in ["tick","amount","row","bet","payout","donation"]:
        var cap: int={"tick":1000000,"amount":150,"row":8,"bet":5,"payout":150,"donation":150}[field]
        if not integer.call(v.get(field),0,cap):return false
        v[field]=int(v[field])
    if typeof(v.get("result"))!=TYPE_STRING or v.result not in ["","item","stat","gold","frog","none","tiny","plain","healed","raise","lower","unchanged"]:return false
    if typeof(v.get("subject"))!=TYPE_STRING or v.subject not in ([""]+ITEMS+["strength","constitution","endurance"]):return false
    if typeof(v.get("dice"))!=TYPE_ARRAY or v.dice.size() not in [0,3]:return false
    for i in range(v.dice.size()):
        if not integer.call(v.dice[i],0,5):return false
        v.dice[i]=int(v.dice[i])
    if v.donation>data.inventory.gold:return false
    if v.kind=="wizard" and v.phase in ["gift","omen"] and v.result not in ["item","stat","gold","frog"]:return false
    if v.result=="item" and v.subject not in ITEMS:return false
    if v.result in ["stat","raise","lower"] and v.subject not in ["strength","constitution","endurance"]:return false
    if v.kind=="tavern" and v.phase=="rolling" and (v.bet==0 or v.dice.size()!=3):return false
    if v.kind=="tavern" and v.phase in ["rolling","dice"] and v.bet>0:
        if v.dice.size()!=3:return false
        var ordered: Array=v.dice.duplicate();ordered.sort();var multiplier: int=0
        for row in DICE:
            if ordered==row.slice(0,3):multiplier=row[3];break
        if v.payout!=v.bet*multiplier:return false
    return true
