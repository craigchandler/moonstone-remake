extends SceneTree

const Journey=preload("res://scripts/session/journey_session.gd")
const Store=preload("res://scripts/session/journey_store.gd")
var definition: Resource=preload("res://content/first_journey.tres").duplicate()
var rules: Resource=preload("res://content/foundation_rules.tres")
var failures: int=0
class RefusingStore extends RefCounted:
    func save_checkpoint(_data: Dictionary) -> bool:return false
func check(ok: bool,label: String) -> void:
    if not ok:failures+=1;push_error(label)
func fresh() -> RefCounted:return Journey.new(definition,rules,12)
func win(j: RefCounted) -> void:
    j.combat.simulation.spawn_remaining=0
    for actor in j.combat.simulation.actors.values():
        if actor.team==2:actor.health=0
    check(j.prepare_loot(),"actual victory opens loot")
func completed(enabled: bool) -> RefCounted:
    var j: RefCounted=fresh();j.revisit_battles=enabled
    var id: String=definition.lairs[0].id
    j.world.position=definition.lairs[0].position
    j.lair_loot[id]={"kind":3,"gold":12,"keys":0,"items":{"healing_potion":2}}
    check(j.confirm_location(id),"first encounter entry")
    win(j)
    check(j.character.experience==1,"first victory awards1XP")
    j.take_loot("gold");j.take_loot("healing_potion")
    j.return_to_map(false)
    return j
func press(key: Key) -> void:
    var event:=InputEventKey.new();event.keycode=key;event.physical_keycode=key;event.pressed=true
    Input.parse_input_event(event);Input.flush_buffered_events();event=event.duplicate();event.pressed=false;Input.parse_input_event(event);Input.flush_buffered_events()
func click(point: Vector2) -> void:
    var event:=InputEventMouseButton.new();event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true
    root.push_input(event,true);event=event.duplicate();event.pressed=false;root.push_input(event,true)
func _init() -> void:
    definition.rival_turns=false # Isolated historical component fixture.

func _initialize() -> void:run.call_deferred()
func run() -> void:
    var id: String=definition.lairs[0].id
    var j: RefCounted=completed(false)
    check(not j.revisit_battles,"default option off")
    var loot: Dictionary=j.lair_loot.duplicate(true)
    check(j.confirm_location(id) and j.loot_open and j.combat.simulation.outcome()=="victory","off returns directly to old treasure")
    for call in range(3):j.prepare_loot();j.checkpoint()
    check(j.character.experience==1 and j.lair_loot==loot,"off cannot farm XP or reroll")
    j.return_to_map(false)
    j=completed(true)
    loot=j.lair_loot.duplicate(true)
    var keys: int=j.owned_keys
    for victory in range(2,5):
        check(j.confirm_location(id) and not j.loot_open and not j.battle_settled and j.combat.simulation.outcome()=="ongoing","on requires a new full encounter")
        check(j.combat.simulation.encounter_settings.count==j.encounter_options(definition.lairs[0]).count,"repeat uses current original wave scaling")
        var entrance: Dictionary=j.checkpoint()
        var interrupted: RefCounted=fresh()
        check(interrupted.restore_checkpoint(entrance) and interrupted.revisit_battles and interrupted.character.experience==victory-1 and interrupted.combat==null,"interrupted repeat saves entrance without XP")
        check(interrupted.confirm_location(id) and interrupted.combat.simulation.outcome()=="ongoing","Continue cannot bypass repeat encounter")
        win(j)
        for call in range(3):j.prepare_loot();j.settle_battle();j.checkpoint()
        check(j.character.experience==victory and j.lair_loot==loot and j.owned_keys==keys,"exactly1XP per new win, unchanged treasure and keys")
        var resumed: RefCounted=fresh()
        check(resumed.restore_checkpoint(JSON.parse_string(JSON.stringify(j.checkpoint()))) and resumed.revisit_battles and resumed.loot_open,"settled victory/option Continue")
        resumed.prepare_loot();resumed.settle_battle()
        check(resumed.character.experience==victory,"Continue at treasure cannot repeat XP")
        check(resumed.return_to_map(false) and resumed.has_treasure(id),"leaving one object retains lair")
        j=resumed
    # Full chest can be inaccessible because the purse is full; it still permits
    # intentional repeat fights, with no additional gold or item generation.
    j=completed(true);j.inventory.gold=j.character_rules.gold_limit
    j.lair_loot[id]={"kind":1,"gold":1,"keys":0,"items":{}}
    j.confirm_location(id);win(j)
    check(not j.take_loot("gold") and j.lair_loot[id].gold==1,"purse limit retains original gold")
    j.return_to_map(false)
    check(j.confirm_location(id) and j.combat.simulation.outcome()=="ongoing","gold alone keeps repeatable lair")
    j.return_to_map(false)
    j=completed(true);j.mode=&"cooperative";j.confirm_location(id);win(j)
    check(j.character.experience==2,"co-op surviving leader earns one repeat XP")
    j.return_to_map(false)
    j=completed(true);j.travel_spent=j.travel_allowance()-1
    for tick in range(16):
        j.travel(Vector2i.RIGHT)
        if j.combat!=null:break
    check(j.combat!=null and not j.loot_open and j.combat.simulation.outcome()=="ongoing" and not j.turn_pending,"last-step forced revisit requires battle when enabled")
    j.return_to_map(false);j.begin_turn()
    # Loss and retreat never award another XP; a defeated site/key stays recorded.
    var xp: int=j.character.experience
    j.confirm_location(id);j.return_to_map(false)
    check(j.character.experience==xp and j.has_treasure(id),"retreat retains chest without XP")
    j.confirm_location(id);j.combat.simulation.actors[1].health=0
    var lives: int=j.character.lives
    j.return_to_map(false)
    check(j.character.experience==xp and j.character.lives==lives-1 and j.world.cleared.has(id) and j.has_treasure(id),"loss costs one life without removing first clear/treasure or giving XP")
    # All-region rewards remain first-clear-only, including a key left as loot.
    j=completed(true)
    for site in definition.lairs:
        if site.region==definition.lairs[0].region:j.awarded_lairs[site.id]=true;j.world.cleared[site.id]=true
    j.offer_region_key(id)
    var key_pile: Dictionary=j.lair_loot.duplicate(true)
    j.confirm_location(id);win(j);j.prepare_loot()
    check(j.character.experience==2 and j.lair_loot==key_pile and j.lair_loot[id].keys==8,"repeat victory cannot duplicate regional key")
    j.return_to_map(true)
    check(not j.has_treasure(id) and not j.arrivals().any(func(row: Dictionary) -> bool:return row.id==id) and not j.confirm_location(id),"taking last gold/item/key removes lair and farming route")
    # Special encounters never respawn or give repeat rewards through this option.
    j=fresh();j.revisit_battles=true
    for special in definition.special_encounters:
        j.world.cleared[special.id]=true
        check(not j.repeat_lair_battle(special.id),"special excluded: "+special.id)
    j=completed(true);j.character.experience=65535;j.confirm_location(id);win(j)
    check(j.character.experience==65535 and not j.validate_checkpoint(j.checkpoint()).is_empty(),"XP cap remains saveable")
    var good: Dictionary=j.checkpoint()
    for bad_options in [null,{}, {"revisit_battles":1},{"revisit_battles":"true"},{"revisit_battles":true,"unknown":false}]:
        var bad: Dictionary=good.duplicate(true);bad.options=bad_options
        check(not j.restore_checkpoint(bad) and j.checkpoint()==good,"invalid option rejected atomically")
    var old: Dictionary=good.duplicate(true);old.schema=10;old.content="journey.campaign.v8";old.erase("options")
    var migrated: RefCounted=fresh()
    check(migrated.restore_checkpoint(old) and not migrated.revisit_battles and migrated.character.snapshot()==j.character.snapshot() and migrated.lair_loot==j.lair_loot,"old save migrates with off and unchanged rewards/character")
    j.restart(12);check(not j.revisit_battles,"new session defaults off")
    # Real disk/menu: edit only the saved option, preserving all journey progress.
    var host: Node=load("res://scenes/main.tscn").instantiate();host.saving_enabled=false
    host.definition=definition;root.add_child(host);host.set_physics_process(false);await process_frame
    var path: String="user://unit-revisit-menu.json"
    var store: RefCounted=Store.new(path,host.journey.validate_checkpoint)
    var existing: RefCounted=completed(false);existing.inventory.gold=73
    var before: Dictionary=existing.checkpoint()
    host.save_store=store;check(store.save_checkpoint(before),"staged real saved journey")
    host.show_menu(store.load_checkpoint());press(KEY_O)
    check(host.menu_view.options_open and not host.menu_view.revisit_battles,"keyboard opens off option")
    click(host.menu_view.button_rect(0).get_center())
    var saved: Dictionary=store.load_checkpoint();var expected: Dictionary=before.duplicate(true);expected.options.revisit_battles=true
    check(saved==expected and host.menu_view.saved==expected,"toggle saves only option, not new-run progress")
    press(KEY_ESCAPE);press(KEY_C)
    check(host.menu_view==null and host.journey.checkpoint()==expected,"Continue restores enabled option and original progress")
    press(KEY_R);press(KEY_O);press(KEY_ENTER)
    check(not store.load_checkpoint().options.revisit_battles,"keyboard toggle saves off")
    press(KEY_ESCAPE);press(KEY_C)
    check(not host.journey.revisit_battles and host.journey.inventory.gold==73,"off continues without reset")
    # Failed persistence restores the toggle; no in-memory/save split.
    host.show_menu(host.journey.checkpoint());host.save_store=RefusingStore.new()
    press(KEY_O);press(KEY_ENTER)
    check(not host.menu_view.revisit_battles and not host.menu_view.saved.options.revisit_battles,"failed save rolls UI back")
    host.save_store=null;host.menu_view.saved={};host.menu_view.revisit_battles=true
    press(KEY_ESCAPE);press(KEY_N);press(KEY_ENTER);press(KEY_ENTER)
    check(host.journey.revisit_battles and host.journey.character.experience==0,"new journey uses selected option")
    host.queue_free();await process_frame
    for suffix in ["",".bak",".tmp"]:
        if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
    if failures==0:print("PASS: optional lair refights/1XP per win, unchanged loot/keys, loss/retreat/exhaustion, interrupted/settled Continue, legacy migration, strict options and actual menu/disk controls")
    quit(1 if failures else 0)
