extends RefCounted

# Stable seats are 0..3. The existing journey is a projection for the current
# human; its three rival IDs are view-relative, never persistent player IDs.
const Identity=preload("res://scripts/domain/knight_identity.gd")
const Rivals=preload("res://scripts/domain/rival_knights.gd")
const Knight=preload("res://scripts/domain/knight_progression.gd")
const Locations=preload("res://scripts/domain/map_locations.gd")
var players: Array=[]
var personal: Array=[]
var active: int=0
var turn: int=0
var awaiting: bool=true
var game_over: bool=false
var wyrm_target: int=-1
var transaction_depth: int=0
var finish_pending: bool=false

static func defaults() -> Array:
    var result: Array=[]
    for seat in range(4):result.append({"identity":{"kind":seat,"name":Identity.DEFAULT_NAMES[seat]},"human":seat<2,"input":0})
    return result

static func valid_players(value: Variant,integer: Callable) -> bool:
    if typeof(value)!=TYPE_ARRAY or value.size()!=4:return false
    var humans: int=0
    var ports: Array=[]
    for seat in range(4):
        var row: Variant=value[seat]
        if typeof(row)!=TYPE_DICTIONARY or row.size()!=3 or not Identity.valid(row.get("identity")) or row.identity.kind!=seat or typeof(row.get("human"))!=TYPE_BOOL or not integer.call(row.get("input"),0,4):return false
        row.identity.kind=int(row.identity.kind);row.input=int(row.input)
        if row.human:
            humans+=1
            if row.input>0:
                if row.input in ports:return false
                ports.append(row.input)
    return humans>0

func others() -> Array:
    var result: Array=[]
    for seat in range(4):
        if seat!=active:result.append(seat)
    return result

func seat_for(id: String) -> int:
    var index: int=Rivals.IDS.find(id)
    return -1 if index<0 else int(others()[index])

func id_for(seat: int) -> String:
    return "" if seat==active else String(Rivals.IDS[others().find(seat)])

func empty_personal() -> Dictionary:
    return {"recency":0,"frog_days":0,"town_lock":"","henge_lock":false,"entry_lock":"","facing":1,"terrain":0,"revealed":{},"duel":{"gold":0,"items":{},"kind":4,"keys":0,"stones":0},"loot_ready":false}

func configure(j: RefCounted,roster: Array) -> void:
    players=roster.duplicate(true)
    for seat in range(4):personal.append(empty_personal())
    for seat in range(4):
        if players[seat].human:active=seat;break
    turn=active
    j.human_players=players.filter(func(row):return row.human).size()
    j.identity=players[active].identity.duplicate(true)
    j.world.position=start_position(j,active)
    var rows: Array=[]
    for seat in others():
        rows.append({"id":id_for(seat),"position":start_position(j,seat),"character":Knight.new(j.character_rules).snapshot(),"inventory":{"gold":int(j.character_rules.starting_gold),"items":{}},"keys":0,"stones":0,"loot_ready":false})
    j.rivals.records.assign(rows);j.world.rival_records=j.rivals.records
    update_labels(j)
    sync(j)

func update_labels(j: RefCounted) -> void:
    j.world.rival_labels.clear()
    for seat in others():j.world.rival_labels[id_for(seat)]=players[seat].identity.name

func start_position(j: RefCounted,seat: int) -> Vector2i:
    var point: Vector2i=Locations.home(seat).position+Vector2i(4,4)
    return point.clamp(j.world.definition.bounds.position,j.world.definition.bounds.end-Vector2i.ONE)

func encode_lock(id: String) -> String:
    return "knight:"+str(seat_for(id)) if id in Rivals.IDS else id

func decode_lock(id: String) -> String:
    return id_for(int(id.trim_prefix("knight:"))) if id.begins_with("knight:") else id

func sync(j: RefCounted) -> void:
    var p: Dictionary=personal[active]
    p.recency=j.places.recency;p.frog_days=j.places.frog_days;p.town_lock=j.town_lock
    p.henge_lock=j.henge_lock;p.entry_lock=encode_lock(j.world.entry_lock)
    p.facing=j.world.facing;p.terrain=j.world.terrain_counter;p.revealed=j.revealed_lairs.duplicate(true)
    var seats: Array=others()
    for index in range(3):
        personal[seats[index]].duel=j.lair_loot[Rivals.IDS[index]].duplicate(true)
        personal[seats[index]].loot_ready=j.rivals.records[index].loot_ready
    if j.dragon_order>0:wyrm_target=int(seats[j.dragon_order-1])

func record(j: RefCounted,seat: int) -> Dictionary:
    if seat==active:return {"position":j.world.position,"character":j.character.snapshot(),"inventory":j.inventory.duplicate(true),"keys":j.owned_keys,"stones":j.quest.stones,"loot_ready":personal[seat].loot_ready}
    return j.rivals.find(id_for(seat)).duplicate(true)

func pursuit(j: RefCounted, position: Vector2i) -> Dictionary:
    var result: Dictionary = {}
    var closest: int = 0x7fffffff
    # Stable seat order breaks equal-distance ties without consuming more RNG.
    for seat in range(4):
        if not players[seat].human:
            continue
        var candidate: Dictionary = record(j, seat)
        if candidate.character.lives <= 0:
            continue
        var distance: int = Rivals.distance(position, candidate.position)
        if distance < closest:
            closest = distance
            result = {"target": "knight:" + str(seat), "goal": candidate.position}
    return result

func receive_attack(j: RefCounted, seat: int) -> bool:
    var attacker: int = turn
    if players[attacker].human or not players[seat].human or record(j, seat).character.lives <= 0:
        return false
    if seat != active:
        activate(j, seat)
        awaiting = false
        j.rivals.active = others().find(attacker) + 1
        j.turn_reason = "rest"
    return j.begin_rival_encounter(id_for(attacker), true)

func activate(j: RefCounted,seat: int) -> void:
    sync(j)
    var records: Array=[]
    for index in range(4):records.append(record(j,index))
    active=seat
    var row: Dictionary=records[seat]
    j.character=Knight.new(j.character_rules)
    for field in row.character:j.character.set(field,row.character[field].duplicate(true) if typeof(row.character[field])==TYPE_DICTIONARY else row.character[field])
    j.inventory=row.inventory.duplicate(true);j.owned_keys=row.keys;j.quest.stones=row.stones
    j.identity=players[seat].identity.duplicate(true);j.world.position=row.position
    var p: Dictionary=personal[seat]
    j.places.recency=p.recency;j.places.frog_days=p.frog_days;j.places.visit={}
    j.town_lock=p.town_lock;j.henge_lock=p.henge_lock;j.world.facing=p.facing
    j.world.terrain_counter=p.terrain;j.revealed_lairs=p.revealed.duplicate(true)
    j.rivals.records.clear()
    for other in others():
        var copy: Dictionary=records[other]
        copy.id=id_for(other)
        j.rivals.records.append(copy)
        j.lair_loot[copy.id]=personal[other].duel.duplicate(true)
        j.world.cleared.erase(copy.id)
        if copy.character.lives==0:j.world.cleared[copy.id]=true
    j.world.rival_records=j.rivals.records
    update_labels(j)
    j.world.entry_lock=decode_lock(p.entry_lock);j.world.active_lair="";j.world.last_result=""
    j.dragon_order=others().find(wyrm_target)+1 if wyrm_target>=0 and wyrm_target!=active else -1
    j.travel_spent=0;j.haste=false;j.turn_pending=false;j.turn_reason=""
    j.rivals.active=0;j.rivals.clear_path();j.world.dragon.reset()
    awaiting=true
    j.message=j.identity.name+"'s turn."

func end_turn(j: RefCounted) -> void:
    if transaction_depth>0:finish_pending=true;return
    sync(j);awaiting=false
    next_turn(j)

func finish_transaction(j: RefCounted) -> void:
    transaction_depth=maxi(0,transaction_depth-1)
    if transaction_depth==0 and finish_pending:finish_pending=false;end_turn(j)
    else:j.persist()

func next_turn(j: RefCounted) -> void:
    var living: bool=false
    for seat in range(4):
        if players[seat].human and record(j,seat).character.lives>0:living=true
    if not living:
        game_over=true;turn=active;j.rivals.active=0;j.rivals.clear_path();j.turn_reason="";j.persist();return
    for attempt in range(8):
        turn=(turn+1)%4
        var first: int=0
        for seat in range(4):
            if players[seat].human:first=seat;break
        if turn==first:upkeep(j)
        if record(j,turn).character.lives<=0:continue
        if players[turn].human:activate(j,turn)
        else:
            if j.character.lives<=0:
                for seat in range(4):
                    if players[seat].human and record(j,seat).character.lives>0:activate(j,seat);awaiting=false;break
            j.rivals.active=others().find(turn)+1;j.rivals.clear_path()
            j.turn_reason="rest";j.world.dragon.reset();j.message=players[turn].identity.name+" is taking a turn."
        j.persist();return

func upkeep(j: RefCounted) -> void:
    sync(j);j.day+=1
    var humans: Array=[]
    for seat in others():
        if players[seat].human:humans.append(id_for(seat))
    j.rivals.upkeep(j.day-1,humans)
    j.character.rest(j.inventory.items)
    for seat in range(4):
        personal[seat].recency=maxi(0,int(personal[seat].recency)-10)
        personal[seat].frog_days=maxi(0,int(personal[seat].frog_days)-1)
    j.places.recency=personal[active].recency;j.places.frog_days=personal[active].frog_days
    j.travel_spent=0;j.haste=false

func begin_turn(j: RefCounted) -> bool:
    if not awaiting or game_over:return false
    awaiting=false
    if j.places.frog_days>0:next_turn(j)
    j.persist();return true

func configure_combat(j: RefCounted) -> void:
    j.combat.human_actors={1:active+1}
    j.combat.simulation.actors[1].owner=active+1
    var seat: int=seat_for(j.world.active_lair)
    if seat<0 or not players[seat].human:return
    for id in j.combat.simulation.actors.keys():
        var old: Dictionary=j.combat.simulation.actors[id]
        if old.team!=2 or old.kind!="black_knight":continue
        var actor: Dictionary=j.combat.simulation.make_actor(id,seat+1,2,"knight",Vector2i(old.x,old.y),old.facing)
        for field in j.combat.rival_profile:actor[field]=j.combat.rival_profile[field]
        j.combat.simulation.actors[id]=actor;j.combat.human_actors[id]=seat+1

func wrap(j: RefCounted,campaign: Dictionary) -> Dictionary:
    sync(j)
    var saved_personal: Array=personal.duplicate(true)
    saved_personal[active].entry_lock=encode_lock(campaign.world.entry_lock)
    return {"schema":17,"content":"journey.local_party.v1","campaign":campaign,"party":{"version":1,"players":players.duplicate(true),"personal":saved_personal,"active":active,"turn":turn,"awaiting":awaiting,"game_over":game_over,"wyrm_target":wyrm_target}}

func restore(data: Dictionary) -> void:
    for field in ["players","personal"]:set(field,data[field].duplicate(true))
    for field in ["active","turn","awaiting","game_over","wyrm_target"]:set(field,data[field])

static func validate(raw: Variant,validator: Callable,integer: Callable) -> Dictionary:
    if typeof(raw)!=TYPE_DICTIONARY or raw.size()!=4 or raw.get("schema")!=17 or raw.get("content")!="journey.local_party.v1" or typeof(raw.get("party"))!=TYPE_DICTIONARY:return {}
    var d: Dictionary=raw.duplicate(true)
    var p: Dictionary=d.party
    if p.size()!=8 or p.get("version")!=1 or not valid_players(p.get("players"),integer) or not integer.call(p.get("active"),0,3) or not integer.call(p.get("turn"),0,3) or not integer.call(p.get("wyrm_target"),-1,3):return {}
    p.version=1
    for field in ["active","turn","wyrm_target"]:p[field]=int(p[field])
    if typeof(p.get("awaiting"))!=TYPE_BOOL or typeof(p.get("game_over"))!=TYPE_BOOL or not p.players[p.active].human or typeof(p.get("personal"))!=TYPE_ARRAY or p.personal.size()!=4:return {}
    var current: Variant = p.personal[p.active]
    if typeof(current) != TYPE_DICTIONARY:
        return {}
    # The active knight's unclaimed duel chest is not one of the three visible
    # rival chests. Include it in whole-campaign ownership checks, without
    # replacing any real chest or changing the serialized campaign shape.
    var c: Dictionary = validator.call(d.get("campaign"), [current.get("duel")], true)
    if c.is_empty() or c.human_players!=p.players.filter(func(row):return row.human).size() or c.identity!=p.players[p.active].identity or c.turn_pending or c.mode!="competitive":return {}
    var seats: Array=[]
    for seat in range(4):
        if seat!=p.active:seats.append(seat)
    var expected: int=0 if p.players[p.turn].human else seats.find(p.turn)+1
    if c.rivals.active!=expected or (expected==0 and p.turn!=p.active):return {}
    var pursuit_seat: int = Rivals.target_seat(c.rivals.target)
    if pursuit_seat >= 0:
        if not p.players[pursuit_seat].human:
            return {}
        var lives: int = c.character.lives if pursuit_seat == p.active else c.rivals.records[seats.find(pursuit_seat)].character.lives
        if lives <= 0:
            return {}
    if p.awaiting and (c.character.lives<=0 or c.phase!="map" or c.town_id!="" or not c.henge.is_empty() or c.quest.notice or not c.quest.ending.is_empty() or expected!=0):return {}
    var ids: Array=c.lair_loot.keys()
    for seat in range(4):
        var extra: Variant=p.personal[seat]
        if typeof(extra)!=TYPE_DICTIONARY or extra.size()!=10:return {}
        if not integer.call(extra.get("recency"),0,70) or not integer.call(extra.get("frog_days"),0,3) or not integer.call(extra.get("terrain"),0,65535) or not integer.call(extra.get("facing"),-1,1) or extra.facing==0:return {}
        for field in ["recency","frog_days","terrain","facing"]:extra[field]=int(extra[field])
        if typeof(extra.get("henge_lock"))!=TYPE_BOOL or typeof(extra.get("loot_ready"))!=TYPE_BOOL or extra.get("town_lock") not in ["","highwood","waterdeep","home","wizard"] or typeof(extra.get("entry_lock"))!=TYPE_STRING:return {}
        if extra.entry_lock!="" and extra.entry_lock not in ids and extra.entry_lock not in ["knight:0","knight:1","knight:2","knight:3"]:return {}
        if typeof(extra.get("revealed"))!=TYPE_DICTIONARY:return {}
        for id in extra.revealed:
            if id not in ids or typeof(extra.revealed[id])!=TYPE_BOOL or not extra.revealed[id]:return {}
        var pile: Variant=extra.get("duel")
        if typeof(pile)!=TYPE_DICTIONARY or pile.size()!=5 or not integer.call(pile.get("gold"),0,150) or not integer.call(pile.get("kind"),0,4) or not integer.call(pile.get("keys"),0,15) or not integer.call(pile.get("stones"),0,15) or typeof(pile.get("items"))!=TYPE_DICTIONARY:return {}
        for field in ["gold","kind","keys","stones"]:pile[field]=int(pile[field])
        for id in pile.items:
            if not integer.call(pile.items[id],1,255):return {}
            pile.items[id]=int(pile.items[id])
        # The archive checks the hidden chest's item IDs and all possession
        # locations together. Other chest copies must match the campaign.
        if seat!=p.active:
            var index: int=seats.find(seat)
            if pile!=c.lair_loot[Rivals.IDS[index]] or extra.loot_ready!=c.rivals.records[index].loot_ready:return {}
    current = p.personal[p.active]
    var lock: String=c.world.entry_lock
    if lock in Rivals.IDS:lock="knight:"+str(seats[Rivals.IDS.find(lock)])
    if current.recency!=c.places.recency or current.frog_days!=c.places.frog_days or current.henge_lock!=c.henge_lock or current.town_lock!=c.town_lock or current.entry_lock!=lock or current.facing!=c.world.facing or current.terrain!=c.world.terrain_counter or current.revealed!=c.revealed_lairs:return {}
    var keys: int=c.owned_keys|c.places.market.keys
    var stones: int=c.quest.stones|c.places.market.stones
    var living: bool=c.character.lives>0
    for index in range(3):
        keys|=int(c.rivals.records[index].keys);stones|=int(c.rivals.records[index].stones)
        if p.players[seats[index]].human and c.rivals.records[index].character.lives>0:living=true
    for pile in c.lair_loot.values():keys|=int(pile.get("keys",0));stones|=int(pile.get("stones",0))
    if (keys&int(current.duel.keys))!=0 or (stones&int(current.duel.stones))!=0 or p.game_over==living or p.game_over and p.awaiting:return {}
    if p.wyrm_target>=0:
        var alive: bool=c.character.lives>0 if p.wyrm_target==p.active else c.rivals.records[seats.find(p.wyrm_target)].character.lives>0
        if not alive or c.world.cleared.has("roaming_dragon"):return {}
    var view_target: int=seats.find(p.wyrm_target)+1 if p.wyrm_target>=0 and p.wyrm_target!=p.active else -1
    if c.dragon_order!=view_target:return {}
    d.schema=17
    d.campaign=c
    return d
