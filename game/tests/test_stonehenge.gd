extends SceneTree

const Journey=preload("res://scripts/session/journey_session.gd")
const Store=preload("res://scripts/session/journey_store.gd")
var failures: int=0
var definition: Resource=preload("res://content/first_journey.tres").duplicate()
var rules: Resource=preload("res://content/foundation_rules.tres")
func check(ok: bool,label: String) -> void:
    if not ok: failures+=1;push_error(label)
func fresh() -> RefCounted:return Journey.new(definition,rules,12)
func enter(j: RefCounted) -> void:
    j.world.position=Vector2i(88,147)
    for step in range(64):
        j.travel(Vector2i.DOWN)
        j.confirm_location("stonehenge")
        if not j.henge.is_empty():return
    check(false,"walk into original Stonehenge node")
func resume(j: RefCounted) -> RefCounted:
    var save: Dictionary=j.checkpoint()
    var copy: RefCounted=fresh()
    check(copy.restore_checkpoint(JSON.parse_string(JSON.stringify(save))) and copy.checkpoint()==save,"exact serialized continuation of "+String(j.henge.get("phase","map")))
    return copy
func _init() -> void:
    definition.rival_turns=false # Isolated historical component fixture.

func _initialize() -> void:
    var j: RefCounted=fresh()
    check(not j.enter_henge(),"distant visit refused")
    enter(j)
    var before: Dictionary=j.checkpoint()
    for tick in range(20):j.travel(Vector2i.RIGHT)
    check(j.henge.phase=="greeting" and j.checkpoint()==before and not j.rest() and not j.upgrade_stat("strength"),"greeting freezes travel/rest/upgrade")
    j=resume(j)
    check(j.advance_henge() and not j.advance_henge(),"greeting advances once")
    check(not j.offer_henge_item("gold") and not j.offer_henge_item("key_forest") and not j.offer_henge_item("healing_potion"),"ordinary belongings/absent magic refused")
    j.character.health=7;j.character.lives=3;j.character.life_loss=2
    var chest: Dictionary=j.lair_loot.duplicate(true)
    check(j.leave_henge_offering() and not j.complete_henge(),"leaving empty offering grants no blessing")
    check(j.character.health==7 and j.character.lives==3 and j.character.life_loss==2,"decline leaves pre-turn health/lives/curse unchanged")
    j=resume(j)
    check(j.leave_henge() and j.turn_pending and j.turn_reason=="stonehenge" and j.day==2 and not j.leave_henge(),"one turn spent, once")
    check(j.lair_loot==chest and j.character.experience==0 and j.henge_lock,"decline never rerolls treasure or awards XP")
    j.begin_turn();j.travel(Vector2i.DOWN)
    check(j.henge.is_empty(),"same entry ring cannot reopen visit")
    for step in range(70):j.travel(Vector2i.RIGHT)
    check(not j.henge_lock,"leaving the entry ring releases its lock")
    # Every magic item is offered as an object, never activated as its usual spell.
    for id in j.loot_rules.items:
        j=fresh();j.inventory.items={id:2};j.inventory.gold=73;j.owned_keys=15
        j.character.health=7;j.character.lives=3;j.character.life_loss=2
        j.character.experience=3
        var old_seed: int=j.reward_seed
        enter(j);j.advance_henge()
        check(j.offer_henge_item(id) and j.inventory.items[id]==1 and j.henge.phase=="prelude" and not j.offer_henge_item(id),"one selected offering: "+id)
        check(not j.haste and j.inventory.gold==73 and j.owned_keys==15 and j.reward_seed==old_seed,"offering does not cast spell/take gold/keys/draw campaign RNG")
        j=resume(j)
        for tick in range(50):j.tick_henge()
        check(j.henge.phase=="ritual" and j.henge.tick==0 and j.character.lives==3,"prelude starts without early blessing")
        for tick in range(271):j.tick_henge()
        j=resume(j)
        for tick in range(256):j.tick_henge()
        check(j.henge.tick==527 and j.character.lives==3,"no reward before final ritual pass")
        j.tick_henge()
        check(j.henge.phase=="temple" and j.character.lives==4 and j.character.health==j.character.maximum(j.inventory.items) and j.character.life_loss==0,"complete blessing and passive maximum: "+id)
        j=resume(j)
        check(not j.complete_henge() and j.character.lives==4,"Continue cannot repeat blessing")
        check(j.upgrade_stat("constitution") and j.character.stats.constitution==2 and j.character.experience==0,"Stonehenge temple spends existing XP")
        check(j.leave_henge() and j.day==2 and j.inventory.items[id]==1,"one offering/turn retained after upgrades")
    j=fresh();j.inventory.items={"ring_of_protection":1};j.character.health=40
    enter(j);j.advance_henge();j.offer_henge_item("ring_of_protection")
    check(j.inventory.items.is_empty() and j.character.health==20,"last passive ring removed and maximum clamped before save")
    check(j.complete_henge() and j.character.lives==5 and j.character.health==20,"skip grants once, life cap respected")
    check(not j.complete_henge(),"repeated skip refused")
    var good: Dictionary=j.checkpoint()
    var mutated: Dictionary=j.snapshot();mutated.henge.phase="offering"
    check(j.checkpoint()==good,"snapshot isolates nested ritual state")
    for patch in [{"phase":"ritual","tick":528,"offered":"ring_of_protection"},{"phase":"ritual","tick":-1,"offered":"ring_of_protection"},{"phase":"ritual","tick":1.5,"offered":"ring_of_protection"},{"phase":"ritual","tick":0,"offered":"key_forest"},{"phase":"greeting","tick":0,"offered":"healing_potion"}]:
        var bad: Dictionary=good.duplicate(true);bad.henge=patch
        check(not j.restore_checkpoint(bad) and j.checkpoint()==good,"malformed visit rejected atomically")
    for field in ["town_id","henge_lock","turn_pending"]:
        var bad: Dictionary=good.duplicate(true);bad[field]="highwood" if field=="town_id" else true
        check(not j.restore_checkpoint(bad),"contradictory visit rejected: "+field)
    var bad: Dictionary=good.duplicate(true);bad.world.position={"x":18,"y":11}
    check(not j.restore_checkpoint(bad),"remote ritual save rejected")
    var old: Dictionary=fresh().checkpoint();old.schema=7;old.content="journey.campaign.v5";old.erase("henge");old.erase("henge_lock");old.character.erase("life_loss")
    check(j.restore_checkpoint(old) and j.henge.is_empty() and j.character.life_loss==0 and j.day==1,"Guardian save migrates without inventing a visit/turn/reward")
    j.inventory.items={"healing_potion":1};enter(j);j.advance_henge();j.offer_henge_item("healing_potion")
    var store: RefCounted=Store.new("user://test-stonehenge.json",j.validate_checkpoint)
    check(store.save_checkpoint(j.checkpoint()),"offering transaction is valid on disk")
    var copy: RefCounted=fresh()
    check(copy.restore_checkpoint(store.load_checkpoint()) and copy.inventory.items.is_empty(),"disk Continue never refunds/redebits selected offering")
    copy.complete_henge();check(store.save_checkpoint(copy.checkpoint()),"completed reward saved with temple phase")
    var again: RefCounted=fresh()
    check(again.restore_checkpoint(store.load_checkpoint()) and not again.complete_henge(),"disk Continue cannot award blessing again")
    if failures==0:print("PASS: original-node entry/locks, all10 one-item offers, passive recalculation, no spell activation, exact phase/tick/disk Continue, one blessing/life cap/curse field, temple XP, one spent turn, legacy migration and atomic invalid-save rejection")
    quit(1 if failures else 0)
