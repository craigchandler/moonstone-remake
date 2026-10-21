extends RefCounted

const RULES=preload("res://content/packs/classic/campaign/moonstone_quest.tres")
const HENGE=preload("res://scripts/domain/stonehenge_visit.gd")
const ENDING_TICKS: int=4062

static func initial(seed: int) -> Dictionary:
    return {"seed":maxi(2,(seed^0x53544f4e)&0xffffffff),"stones":0,"valley_stone":0,"notice":false,"ending":{}}

static func migrate(data: Dictionary, loot_rules: Resource) -> void:
    data.quest=initial(int(data.reward_seed))
    var unawarded_win: bool=not data.awarded_lairs.has("valley_guardian") and data.character.lives>0 and (data.world.cleared.has("valley_guardian") or (data.phase=="loot" and data.world.active_lair=="valley_guardian"))
    if unawarded_win:
        # Earlier AI co-op could clear the Valley after its leader fell without
        # awarding the still-living campaign record. Do not leave that run stuck.
        data.awarded_lairs.valley_guardian=true
        data.character.experience=mini(65535,int(data.character.experience)+3)
    if not data.awarded_lairs.has("valley_guardian"):return
    # Prior builds awarded Guardian XP without its original quest object.
    # Fulfil that earned reward once; retain every existing chest/XP/day value.
    var roller: RefCounted=preload("res://scripts/domain/loot_roller.gd").new(loot_rules,data.quest.seed)
    data.quest.valley_stone=1<<(roller.next_value()&3)
    data.quest.seed=roller.state
    data.quest.stones=data.quest.valley_stone
    data.owned_keys=0
    data.quest.notice=data.phase=="loot" and data.world.active_lair=="valley_guardian"

static func valid(data: Dictionary, integer: Callable, definition: Resource, extra_stones: int = 0) -> bool:
    var q: Variant=data.get("quest")
    if typeof(q)!=TYPE_DICTIONARY or q.size()!=5:return false
    if not integer.call(q.get("seed"),2,0xffffffff) or not integer.call(q.get("stones"),0,15) or not integer.call(q.get("valley_stone"),0,8):return false
    for name in ["seed","stones","valley_stone"]:q[name]=int(q[name])
    if q.valley_stone not in [0,1,2,4,8] or typeof(q.get("notice"))!=TYPE_BOOL or typeof(q.get("ending"))!=TYPE_DICTIONARY:return false
    var won: bool=data.awarded_lairs.has("valley_guardian")
    if won!=(q.valley_stone!=0):return false
    var held_stones: int = q.stones | extra_stones
    if data.has("rivals"):
        for row in data.rivals.records:held_stones|=int(row.stones)
        for pile in data.lair_loot.values():held_stones|=int(pile.get("stones",0))
    if data.has("places"):held_stones|=int(data.places.market.stones)
    if won and (data.owned_keys!=0 or not(held_stones&q.valley_stone)):return false
    if q.notice:
        if not won or data.character.lives<=0 or data.phase not in ["map","loot"] or data.town_id!="" or not data.henge.is_empty() or data.turn_pending:return false
        if data.phase=="loot" and data.world.active_lair!="valley_guardian":return false
    if q.ending.is_empty():return true
    var e: Dictionary=q.ending
    if e.size()!=5 or e.get("stage") not in ["message","ready","complete"] or not integer.call(e.get("tick"),0,ENDING_TICKS):return false
    if not integer.call(e.get("knight_kind"),0,3) or e.knight_kind!=data.identity.kind or not integer.call(e.get("frame"),45,49) or not integer.call(e.get("code"),128,255):return false
    for name in ["tick","knight_kind","frame","code"]:e[name]=int(e[name])
    if e.stage=="message" and e.tick>20:return false
    if e.stage=="ready" and e.tick>=ENDING_TICKS:return false
    if e.stage=="complete" and e.tick!=ENDING_TICKS:return false
    var phase: int=((int(data.day)-1)/int(definition.dragon_rules.rounds_per_counter))%8
    if e.frame!=RULES.moon_frames[phase] or not RULES.matches(q.stones,phase) or e.code!=RULES.ending_code(e.frame,e.knight_kind):return false
    if q.notice or data.phase!="map" or data.town_id!="" or not data.henge.is_empty() or data.turn_pending or data.character.lives<=0:return false
    var p:=Vector2i(int(data.world.position.x),int(data.world.position.y))
    var inside: bool=preload("res://scripts/domain/map_locations.gd").touches(p,HENGE.POSITION,Vector2i(18,12)) if definition.confirm_entry else p.distance_squared_to(HENGE.POSITION)<=definition.entry_radius*definition.entry_radius
    return inside and not data.world.dragon.active
