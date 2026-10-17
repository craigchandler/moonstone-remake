extends RefCounted

# Review-only setup: staged health/positions, followed by real AI or submitted
# commands and ordinary collision. This is not an original-game comparison.
var choice: String="correct_axe"
var mirror: bool=false
var tick: int=0
var checked: Dictionary={}
var saved: Dictionary={}
var downs: int=0
var executions: int=0
var damage: int=0
var captured: int=-1
var escaped: int=-1
var pose_indices: Dictionary={}
var animator: RefCounted=preload("res://scripts/presentation/actor_animator.gd").new()
var art: Resource=preload("res://content/classic_art.tres")

func length() -> int:return 900 if choice=="correct_mud_expiry" else 360

func setup(session: RefCounted) -> void:
    var encounter: StringName=&"axe_lair"
    if choice=="correct_knight" or choice=="correct_human":encounter=&"black_knight_fight"
    if choice=="correct_ride":encounter=&"rat_lair"
    if choice.begins_with("correct_mud"):encounter=&"mud_lair"
    session.start(&"competitive",encounter,{"count":1,"concurrent":1})
    var m: RefCounted=session.simulation
    var foe: Dictionary=m.actors[10];var knight: Dictionary=m.actors[1]
    foe.interaction={};foe.visual_kind="";foe.entering=false
    foe.x=80;foe.y=166;foe.facing=1;foe.cooldown_remaining=0
    knight.x=155;knight.y=166;knight.facing=-1
    if choice=="correct_axe":knight.health=3
    if choice=="correct_knight":knight.health=4;foe.last_attack="heavy"
    if choice=="correct_human":
        knight.x=80;knight.facing=1;foe.x=120;foe.facing=-1;foe.health=5
        foe.cooldown_remaining=9999
    if choice=="correct_ride":
        m.rat_perch.owner=99 # ground-flight fixture; the tree is unavailable
        foe.x=40;knight.x=160;foe.health=13;foe.maximum=13
    if mirror:
        for a in m.actors.values():a.x=320-a.x;a.facing=-a.facing

func advance(session: RefCounted) -> void:
    if tick==0:setup(session)
    var m: RefCounted=session.simulation
    var foe: Dictionary=m.actors[10];var knight: Dictionary=m.actors[1]
    if choice in ["correct_axe","correct_knight"]:
        session.advance(Vector2i.ZERO,"idle")
    elif choice=="correct_human":
        if tick in [0,50]:session.command(1,1,Vector2i.ZERO,"swing")
        m.advance()
    else:
        if tick==0:session.command(10,0,Vector2i.ZERO,"rat_leap" if choice=="correct_ride" else "mud_reach",foe.facing)
        if choice=="correct_ride" and captured>=0 and tick==captured+12:session.command(1,1,Vector2i.DOWN,"block")
        if choice.begins_with("correct_mud") and not foe.interaction.is_empty() and foe.interaction.stage=="carry":
            var deadline: int=foe.interaction.duration-(1 if choice=="correct_mud_expiry" else 2)
            if foe.interaction.elapsed==deadline:session.command(1,1,Vector2i.DOWN,"block")
        m.advance()
    animator.update(m.actors,m.rules,art)
    for e in m.events:
        if e.type=="hold" and captured<0:captured=tick
        if e.type=="escape":escaped=tick
        if e.type=="down":downs+=1
        if e.type=="execution":executions+=1
        if e.type=="damage" and e.actor==1:damage+=e.amount
    var victim: Dictionary=foe if choice=="correct_human" else knight
    if victim.defeat_clip=="defeat_gory":pose_indices[animator.poses[victim.id].index]=true
    if choice=="correct_ride" and foe.special_clip=="rat_escape":pose_indices[animator.poses[10].index]=true
    if tick%30==0:saved[str(tick)]=m.snapshot()
    tick+=1

func verify(session: RefCounted) -> bool:
    var m: RefCounted=session.simulation
    var foe: Dictionary=m.actors[10];var knight: Dictionary=m.actors[1]
    if choice in ["correct_axe","correct_knight","correct_human"]:
        var victim: Dictionary=foe if choice=="correct_human" else knight
        checked={"one_down":downs==1,"one_execution":executions==1,
            "full_frames":pose_indices.size()==14,"settled":victim.health==0 and victim.down_remaining==0 and victim.defeat_clip=="defeat_gory",
            "no_extra_damage":damage==(3 if choice=="correct_axe" else (4 if choice=="correct_knight" else 0))}
    elif choice=="correct_ride":
        checked={"real_capture":captured>=0,"escaped":escaped==captured+12,
            "full_frames":pose_indices.size()==4,"holder_unhurt":foe.health==13,
            "victim_free":knight.health==20 and knight.hidden_by==0 and knight.grab_remaining==0}
    elif choice.begins_with("correct_mud"):
        var expiry: bool=choice=="correct_mud_expiry"
        checked={"real_capture":captured>=0,"deadline":escaped<0 if expiry else escaped>=0,
            "health":knight.health==0 if expiry else knight.health==18,
            "holder_damage":foe.health==foe.maximum if expiry else foe.health==foe.maximum-1,
            "settled":knight.down_remaining==0 and knight.hidden_by==0}
    else:return false
    for key in checked:
        if not checked[key]:push_error(choice+" failed: "+key)
    return not checked.values().has(false)
