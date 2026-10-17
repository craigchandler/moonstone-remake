extends RefCounted

# Reproducible demonstrations: staged starting health/positions, then real
# commands, collision, damage and interaction clocks. Not an AI playthrough.
var choice: String = "spear"
var mirror: bool = false
var tick: int = 0
var checked: Dictionary = {}
var seen: Dictionary = {}

func length() -> int:
    if choice=="mud_carry": return 850
    if choice in ["troll","balok_a","balok_b","spear"]: return 650
    if choice=="balok_release": return 280
    return 230

func reset(session: RefCounted) -> void:
    var enc: StringName = &"spear_lair"
    if choice.begins_with("balok"): enc=&"balok_lair"
    elif choice.begins_with("mud"): enc=&"mud_lair"
    elif choice.begins_with("guardian"): enc=&"guardian_fight"
    elif choice.begins_with("hammer"): enc=&"hammer_lair"
    elif choice=="dragon_death": enc=&"dragon_fight"
    elif choice=="troll": enc=&"troll_lair"
    session.start(&"competitive",enc,{"count":1,"concurrent":1})
    var model: RefCounted=session.simulation
    var victim: Dictionary=model.actors[1]
    var foe: Dictionary=model.actors[10]
    victim.x=160;victim.y=166;victim.facing=-1
    foe.x=40;foe.y=166;foe.facing=1;foe.entering=false;foe.cooldown_remaining=0
    if choice.begins_with("balok"):
        foe.x=85;victim.health=10 if choice=="balok_release" else 5
        if choice=="balok_b":model.balok_finish_toggle=1
    elif choice=="troll": foe.x=20;victim.health=7
    elif choice=="spear": victim.health=3
    elif choice.begins_with("mud"):
        if choice in ["mud_quick","mud_interrupt"]:foe.x=85
        if choice not in ["mud_quick","mud_interrupt"]:
            foe.interaction={};foe.visual_kind="";foe.special_clip=""
            foe.x=80;victim.health=20
    elif choice.begins_with("guardian"):
        foe.x=25;victim.x=170 if choice=="guardian_far" else 150
        victim.health=100
    if choice.ends_with("death") or choice.begins_with("hammer") or choice=="mud_interrupt":
        if choice!="mud_interrupt":foe.health=1
        victim.x=90;victim.facing=1;foe.x=135;foe.facing=-1
        if choice=="dragon_death":foe.rest_height=0;foe.height=0
    if mirror and choice!="dragon_death":
        for actor in model.actors.values(): actor.x=320-actor.x;actor.facing=-actor.facing
    session.command(10,0,Vector2i.ZERO,"idle")

func advance(session: RefCounted) -> void:
    if tick==0:
        reset(session)
        var action: String="spear_thrust"
        if choice.begins_with("balok"): action="balok_maul"
        elif choice=="troll":action="troll_smash"
        elif choice.begins_with("mud"):action="mud_reach"
        elif choice.begins_with("guardian"):action="guardian_grab"
        if choice.ends_with("death") or choice.begins_with("hammer") or choice=="mud_interrupt":
            session.command(1,1,Vector2i.ZERO,"heavy" if choice=="hammer_a" else ("swing" if choice=="hammer_b" else "lunge"))
        elif choice!="mud_quick": session.command(10,0,Vector2i.ZERO,action)
    var model: RefCounted=session.simulation
    var victim: Dictionary=model.actors[1]
    var foe: Dictionary=model.actors[10]
    if choice=="mud_escape" and foe.special_clip=="carry" and foe.hold_elapsed==30:
        session.command(1,1,Vector2i.DOWN,"block")
    model.advance()
    for event in model.events:
        if event.type=="damage":seen.damage=true
    if not foe.special_clip.is_empty(): seen[foe.special_clip]=true
    if victim.visual_kind in ["knight_finishes","death_knight"] and victim.defeat_clip=="flung": seen.flung=true
    tick+=1

func verify(session: RefCounted) -> bool:
    var model: RefCounted=session.simulation
    var victim: Dictionary=model.actors[1]
    var foe: Dictionary=model.actors[10]
    checked.damage=seen.get("damage",false)
    if choice in ["guardian_close","guardian_far"]:checked.damage=not seen.get("damage",false)
    checked.links_released=victim.hidden_by==0 and victim.grab_remaining==0 and foe.interaction.is_empty()
    if choice.begins_with("balok"):
        checked.lift_shake=seen.get("lift",false) and seen.get("shake",false)
        checked.ending=(victim.health==5 if choice=="balok_release" else seen.get("eat_a" if choice=="balok_a" else "eat_b",false))
    elif choice.begins_with("mud"):
        if choice=="mud_interrupt":
            checked.ending=victim.health>0 and foe.health==26
            checked.interrupted=not seen.get("quick_drag",false)
        else:
            checked.ending=seen.get("release",false) and victim.health==18 if choice=="mud_escape" else victim.vanished
            checked.sequence=seen.get("quick_drag",false) if choice=="mud_quick" else seen.get("carry",false)
    elif choice=="troll":checked.flung=seen.get("flung",false)
    elif choice.begins_with("guardian") and not choice.ends_with("death"):
        checked.grab=seen.get("grab_far" if choice=="guardian_far" else "grab_close",false)
        checked.alive=victim.health==100
    elif choice.ends_with("death") or choice.begins_with("hammer"):
        checked.death=foe.health==0 and foe.down_remaining==0
        if choice=="guardian_death":checked.vanish=foe.vanished
        if choice=="dragon_death":checked.grounded=foe.rest_height==0
        if choice.begins_with("hammer"):checked.branch=foe.defeat_clip==("defeat_a" if choice=="hammer_a" else "defeat_b")
    else:checked.impale=seen.get("impale",false)
    for key in checked:
        if not checked[key]:push_error("Finisher fixture failed: "+choice+"/"+key);return false
    return true
