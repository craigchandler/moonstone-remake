extends SceneTree
const Journey=preload("res://scripts/session/journey_session.gd")
const Identity=preload("res://scripts/domain/knight_identity.gd")
const ART=preload("res://assets/classic/knight_selection/art.tres")
var definition: Resource=preload("res://content/first_journey.tres")
var rules: Resource=preload("res://content/foundation_rules.tres")
var failures: int=0
var checks: int=0
func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failures+=1;push_error(label)
func fresh() -> RefCounted:return Journey.new(definition,rules,0x4d4f4f4e)
func press(key: Key,unicode: int=0,ctrl: bool=false) -> void:
    var e:=InputEventKey.new();e.keycode=key;e.physical_keycode=key;e.unicode=unicode;e.ctrl_pressed=ctrl;e.pressed=true
    root.push_input(e,true);e=e.duplicate();e.pressed=false;root.push_input(e,true)
func click(point: Vector2) -> void:
    var e:=InputEventMouseButton.new();e.position=point;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=true
    root.push_input(e,true);e=e.duplicate();e.pressed=false;root.push_input(e,true)
func _initialize() -> void:run.call_deferred()
func run() -> void:
    var first: Dictionary={}
    var combat_state: Dictionary={}
    for kind in range(4):
        var j: RefCounted=fresh()
        check(j.restart(1234,false,{"kind":kind,"name":Identity.DEFAULT_NAMES[kind]}),"confirmed identity accepted")
        check(j.world.position==j.Locations.home(kind).position.clamp(definition.bounds.position,definition.bounds.end-Vector2i.ONE) and j.character.health==20 and j.character.experience==0,"selected home position; equal starting stats")
        var state: Dictionary=j.checkpoint()
        var normal: Dictionary=state.duplicate(true);normal.identity=Identity.initial();normal.world.position={"x":0,"y":0}
        if first.is_empty():first=normal
        check(normal==first,"colour does not change chest, market, rival or quest RNG")
        var restored: RefCounted=fresh()
        check(restored.restore_checkpoint(JSON.parse_string(JSON.stringify(state))) and restored.checkpoint()==state,"identity JSON Continue exact")
        for other in range(4):
            j.world.position=j.Locations.PLACES[other].position
            check(j.arrivals().any(func(row: Dictionary) -> bool:return row.id=="home")== (kind==other),"only chosen home is enterable")
        j.world.position=j.Locations.home(kind).position.clamp(definition.bounds.position,definition.bounds.end-Vector2i.ONE);j.character.lives=2
        check(j.confirm_location("home") and j.character.lives==3 and j.world.inside_lair(j.town("home")),"chosen home opens sheet and grants one capped life")
        state=j.checkpoint()
        check(restored.restore_checkpoint(state) and restored.checkpoint()==state,"saved selected home validates without healing again")
        check(not j.enter_town("home") and j.checkpoint()==state,"home cannot grant twice while open")
        j=fresh();j.restart(1234,false,{"kind":kind,"name":"CraigChandler"})
        for pair in [[1,17],[2,1],[4,9]]:
            j.quest.stones=pair[0];j.day=pair[1];j.world.position=j.Henge.POSITION
            check(j.enter_henge() and j.quest.ending.knight_kind==kind and ART!=null,"ending uses selected knight")
            var code: int=j.quest_rules.ending_code(j.quest.ending.frame,kind)
            check(j.quest.ending.code==code and preload("res://assets/classic/ending_complete/art.tres").palettes.has(code),"all twelve original ending palettes reachable")
            state=j.checkpoint();check(restored.restore_checkpoint(state),"selected ending checkpoint validates")
            j.quest.ending={}
        j=fresh();j.restart(1234,false,{"kind":kind,"name":"Knight"})
        j.world.position=definition.lairs[0].position;j.confirm_location(definition.lairs[0].id)
        for i in range(100):j.combat.advance(Vector2i.ZERO,"guard")
        var battle: Dictionary=j.combat.simulation.snapshot()
        if combat_state.is_empty():combat_state=battle
        check(battle==combat_state,"colour cannot change combat state or cadence")
    var j: RefCounted=fresh();j.character.experience=11
    var current: Dictionary=j.checkpoint()
    var old: Dictionary=current.duplicate(true);old.schema=15;old.content="journey.campaign.v13";old.erase("identity")
    check(j.restore_checkpoint(old) and j.checkpoint()==current,"v15 migration changes only schema and default identity")
    for identity in [{},{"kind":4,"name":"Knight"},{"kind":1.5,"name":"Knight"},{"kind":0,"name":""},{"kind":0,"name":"too long a name"},{"kind":0,"name":" Knight"},{"kind":0,"name":"A\nB"},{"kind":0,"name":"Knight","extra":true}]:
        var bad: Dictionary=current.duplicate(true);bad.identity=identity
        check(not j.restore_checkpoint(bad) and j.checkpoint()==current,"invalid identity rejects atomically")
        if not identity.is_empty():check(not j.restart(456,true,identity) and j.checkpoint()==current,"invalid new identity cannot reset progress")
    for path in ART.variants:
        for variant in ART.variants[path]:check(ResourceLoader.exists(variant),"native palette dependency exists")
    check(not ART.variants.has("res://assets/classic/town_locations/gift.png"),"Math's fixed portrait palette is never recoloured")
    for i in range(15):check(not ART.variants.has("res://assets/classic/town_locations/wizard_%d.png"%i),"Math's fixed animated palette is never recoloured")
    # Source-derived spots, independent of an RGB substitution: knight register6
    # at its first pose, and Hammer register10 at its first pose. Both atlases
    # contain dark blue, but only the original class register may change.
    for kind in range(4):
        var hero: Image=ART.coloured(load("res://assets/classic/knight/blue.png"),kind).get_image()
        if hero.is_compressed():hero.decompress()
        check(hero.get_pixel(124,68).to_html()==["0000aaff","ff8800ff","88cc66ff","ff2222ff"][kind],"original knight register6 has chosen class colour")
        var hammer: Image=ART.coloured(load("res://assets/classic/trogg_hammer/gore.png"),kind).get_image()
        if hammer.is_compressed():hammer.decompress()
        check(hammer.get_pixel(75,67).to_html()=="000044ff","same RGB at fixed Hammer register10 is preserved")
        ART.colour_cache.clear()
    var host: Node=load("res://scenes/main.tscn").instantiate();host.saving_enabled=false;root.add_child(host);host.set_physics_process(false)
    await process_frame
    host.journey.character.experience=9;host.show_menu(host.journey.checkpoint())
    var before: Dictionary=host.journey.checkpoint();var saved: Dictionary=host.menu_view.saved.duplicate(true)
    press(KEY_N)
    check(host.selection_view!=null and host.menu_view!=null and not host.menu_view.visible,"New opens original selection above paused menu")
    press(KEY_RIGHT);press(KEY_RIGHT);press(KEY_RIGHT);press(KEY_RIGHT)
    check(host.selection_view.selected==3,"selection clamps at final original portrait")
    press(KEY_ENTER);press(KEY_A,0,true);press(KEY_BACKSPACE)
    for ch in "CraigChandler":press(KEY_NONE,ch.unicode_at(0))
    press(KEY_NONE,88)
    check(host.selection_view.name_value=="CraigChandler","name editor retains thirteen-character original bound")
    press(KEY_ESCAPE);press(KEY_ESCAPE)
    check(host.selection_view==null and host.menu_view.visible and host.menu_view.saved==saved and host.journey.checkpoint()==before,"cancel preserves live campaign and Continue without RNG/reset")
    press(KEY_N);click(Vector2(353,225))
    check(host.selection_view.selected==2 and host.selection_view.editing,"original green portrait mouse hit box")
    press(KEY_A,0,true)
    for ch in "Green Knight":press(KEY_NONE,ch.unicode_at(0))
    click(Vector2(520,350))
    check(host.selection_view==null and host.menu_view==null and host.journey.identity=={"kind":2,"name":"Green Knight"},"confirmed name/colour starts one new campaign")
    check(host.journey.character.experience==0 and host.journey.world.position==Vector2i(12,187),"new game commits once at the selected green home")
    host.show_menu(host.journey.checkpoint());press(KEY_C)
    check(host.selection_view==null and host.menu_view==null and host.journey.identity.kind==2,"Continue bypasses picker and keeps colour")
    host.queue_free();await process_frame;ART.colour_cache.clear()
    if failures==0:print("PASS: ",checks," selection/identity checks; four homes, colours, names, original defaults, deterministic rules/RNG, legacy saves, exact Continue, twelve endings, safe cancel and keyboard/mouse commit")
    quit(1 if failures else 0)
