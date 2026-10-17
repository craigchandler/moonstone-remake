extends RefCounted
const Places=preload("res://scripts/domain/town_locations.gd")
const Roller=preload("res://scripts/domain/loot_roller.gd")
var results: Dictionary={}
func key(host: Node,code: Key) -> void:
    var e:=InputEventKey.new();e.keycode=code;e.pressed=true
    host.get_viewport().push_input(e,true);e=e.duplicate();e.pressed=false;host.get_viewport().push_input(e,true)
func click(host: Node,point: Vector2) -> void:
    var e:=InputEventMouseButton.new();e.position=point;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=true
    host.get_viewport().push_input(e,true);e=e.duplicate();e.pressed=false;host.get_viewport().push_input(e,true)
func seed_for(j: RefCounted,kind: String) -> int:
    for i in range(2,10000):
        var seed: int=(i*0x9e3779b9)&0xffffffff
        var rng: RefCounted=Roller.new(j.loot_rules,seed)
        var value: int=rng.percent()
        if kind=="item" and value<=30 or kind=="stat" and value>30 and value<=70 or kind=="gold" and value>70 and value<=90 or kind=="frog" and value>90:return seed
    return 2
func dice_seed(j: RefCounted,won: bool) -> int:
    for i in range(2,10000):
        var seed: int=(i*0x9e3779b9)&0xffffffff
        var rng: RefCounted=Roller.new(j.loot_rules,seed);var dice: Array=[]
        for n in range(3):
            for attempt in range(100):
                var face: int=rng.next_value()&7
                if face<6:dice.append(face);break
        dice.sort();var match_row: bool=false
        for row in Places.DICE:
            if dice==row.slice(0,3):match_row=true;break
        if won==match_row:return seed
    return 2
func advance(host: Node) -> void:
    var j: RefCounted=host.journey;var mode: String=host.locations_demo
    if host.elapsed==1:
        j.inventory.gold=100;j.character.experience=3
        var town: String="wizard" if mode.begins_with("wizard-") else "waterdeep" if mode=="waterdeep" else "highwood"
        j.world.position=j.town(town).position;j.enter_town(town)
        if town=="wizard":j.places.seed=seed_for(j,mode.trim_prefix("wizard-"))
        if mode=="highwood":j.character.health=4;j.character.lives=4;j.places.market.items={"ring_of_protection":1,"healing_potion":2}
        host.show_town();results.initial=j.checkpoint()
        if mode.begins_with("tavern-"):
            click(host,host.town_view.button_rect(1).get_center());j.places.seed=dice_seed(j,mode=="tavern-win")
    if mode.begins_with("wizard-"):
        if host.elapsed in [70,210,300,370]:key(host,KEY_ESCAPE if host.elapsed==370 else KEY_SPACE)
        if host.elapsed==100:results.gift=j.checkpoint()
        if host.elapsed==320:key(host,KEY_TAB) # Save the personal pack as well as the applied gift.
        if host.elapsed==330:results.sheet=j.checkpoint()
    elif mode.begins_with("tavern-"):
        if host.elapsed==70:click(host,host.inventory_view.service_screen.row_rect(2).get_center());results.rolling=j.checkpoint()
        if host.elapsed==160:results.revealed=j.checkpoint()
        if host.elapsed==220:key(host,KEY_SPACE)
        if host.elapsed==260:key(host,KEY_ESCAPE)
    elif mode=="highwood":
        if host.elapsed==70:click(host,host.town_view.button_rect(0).get_center())
        if host.elapsed==100:click(host,host.inventory_view.row_rect(0).get_center())
        if host.elapsed==150:key(host,KEY_ENTER)
        if host.elapsed==200:click(host,host.town_view.button_rect(2).get_center())
        if host.elapsed==250:key(host,KEY_SPACE)
        if host.elapsed==275:
            key(host,KEY_2)
            for n in range(10):key(host,KEY_RIGHT)
        if host.elapsed==300:key(host,KEY_SPACE);results.healed=j.checkpoint()
        if host.elapsed==350:key(host,KEY_SPACE)
        if host.elapsed==400:click(host,host.town_view.button_rect(3).get_center())
        if host.elapsed==450:
            var view: Node=host.inventory_view
            for slot in view.buy_slots():
                if slot.id=="ring_of_protection":click(host,slot.rect.get_center());break
            results.bought=j.checkpoint()
        if host.elapsed==500:click(host,host.inventory_view.row_rect(0).get_center());results.upgraded=j.checkpoint()
        if host.elapsed==550:key(host,KEY_ESCAPE)
        if host.elapsed==600:click(host,host.town_view.button_rect(4).get_center())
    elif mode=="waterdeep":
        if host.elapsed==70:click(host,host.town_view.button_rect(3).get_center())
        if host.elapsed==140:key(host,KEY_SPACE)
        if host.elapsed==180:key(host,KEY_2)
        if host.elapsed==200:key(host,KEY_SPACE);results.reading=j.checkpoint()
        if host.elapsed==280:key(host,KEY_SPACE)
        if host.elapsed==340:click(host,host.town_view.button_rect(1).get_center())
        if host.elapsed==400:click(host,host.inventory_view.service_screen.row_rect(0).get_center());results.rolling=j.checkpoint()
        if host.elapsed==490:results.revealed=j.checkpoint()
        if host.elapsed==540:key(host,KEY_SPACE)
        if host.elapsed==580:key(host,KEY_ESCAPE)
        if host.elapsed==620:click(host,host.town_view.button_rect(4).get_center())
func finish(host: Node) -> void:
    var j: RefCounted=host.journey;var mode: String=host.locations_demo
    results.final=j.checkpoint();var valid: bool=not j.validate_checkpoint(results.final).is_empty()
    var copy: RefCounted=load("res://scripts/session/journey_session.gd").new(host.definition,host.rules,2)
    for name in results:
        var cp: Dictionary=results[name]
        if not copy.restore_checkpoint(JSON.parse_string(JSON.stringify(cp))) or copy.checkpoint()!=cp:valid=false
    if mode.begins_with("wizard-"):
        valid=valid and results.gift.places.visit.result==mode.trim_prefix("wizard-") and results.sheet.places.visit.phase=="sheet" and results.gift.inventory==results.sheet.inventory and j.town_id==""
    elif mode.begins_with("tavern-"):
        valid=valid and results.rolling.inventory==results.revealed.inventory and results.revealed.places.visit.phase=="dice" and (results.revealed.places.visit.payout>0)==(mode=="tavern-win") and host.inventory_view==null
    elif mode=="highwood":valid=valid and results.healed.character.health==20 and results.healed.character.lives==5 and results.bought.inventory.items.get("ring_of_protection",0)==1 and j.character.stats.strength==2 and j.town_id==""
    else:valid=valid and results.reading.inventory.gold==85 and results.rolling.inventory==results.revealed.inventory and j.town_id==""
    if not valid:push_error("Location fixture failed: "+JSON.stringify(results));host.get_tree().quit(1);return
    print("LOCATIONS_STATE=",JSON.stringify(results));print("PASS: Math and town production fixture: ",mode);host.get_tree().quit()
