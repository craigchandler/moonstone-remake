extends RefCounted
# Explicit positions/HP, followed by real input, contact and native state clocks.
var choice:String="beast_same"
var mirror:bool=false
var tick:int=0
var checked:Dictionary={}
var seen:Dictionary={}
func length()->int:
    return 440 if choice=="beast_opposite" else (480 if choice=="beast_same" else 220)
func reset(session:RefCounted)->void:
    session.start(&"competitive",&"beast_lair",{"count":1,"concurrent":1})
    var m:RefCounted=session.simulation
    var v:Dictionary=m.actors[1];var b:Dictionary=m.actors[10]
    v.x=160;v.y=166;v.health=5 if choice in ["beast_same","beast_opposite"] else 20
    v.facing=1 if choice in ["beast_same","beast_hit_rear"] else -1
    b.x=100;b.y=166;b.facing=1;b.cooldown_remaining=0
    if choice=="beast_exit":b.x=-60;v.y=139
    if choice=="beast_hurt":v.facing=1;b.x=205;b.facing=-1;b.cooldown_remaining=10000;b.beast_pass=1
    if choice.begins_with("beast_die_"):
        v.x=160;v.facing=1;b.x=240 if choice=="beast_die_chop" else 205
        b.facing=-1;b.cooldown_remaining=10000
        b.health=10 if choice=="beast_die_chop" else 5 # full beast vs an already wounded one
    if mirror:
        for a in m.actors.values():a.x=320-a.x;a.facing=-a.facing
    if choice=="beast_hurt" or choice.begins_with("beast_die_"):
        session.command(1,1,Vector2i.ZERO,"heavy" if choice=="beast_die_chop" else "swing",v.facing)
    else:session.command(10,0,Vector2i.ZERO,"beast_charge",b.facing)
func advance(session:RefCounted)->void:
    if tick==0:reset(session)
    var m:RefCounted=session.simulation
    var b:Dictionary=m.actors[10];var v:Dictionary=m.actors[1]
    m.advance()
    if not b.special_clip.is_empty():seen[b.special_clip]=true
    for e in m.events:
        if e.type=="beast_eject":seen.eject=true
        if e.type=="damage":seen.damage=true
    if v.defeat_clip=="ejected" and v.hidden_by==0:seen.falling=true
    if b.x>=392 or b.x<=-72:seen.outside=true
    tick+=1
func verify(session:RefCounted)->bool:
    var m:RefCounted=session.simulation;var b:Dictionary=m.actors[10];var v:Dictionary=m.actors[1]
    if choice=="beast_same":
        checked.kill=seen.get("execution_same",false) and v.health==0
        checked.eject=seen.get("eject",false) and seen.get("falling",false) and v.hidden_by==0 and v.down_remaining==0
        checked.retreat=seen.get("impact",false) and seen.get("outside",false)
    elif choice=="beast_opposite":
        checked.kill=seen.get("execution_opposite",false) and v.health==0
        checked.complete=b.terminal_clip=="execution_opposite" and b.special_remaining==0 and v.down_remaining==0
    elif choice=="beast_hurt":
        checked.survived=b.health==5 and v.health==20
        checked.turned=seen.get("hurt_b",false) and seen.get("impact",false)
        checked.exit=seen.get("outside",false)
    elif choice in ["beast_hit","beast_hit_rear"]:
        checked.damage=v.health==15
        checked.turn_exit=seen.get("impact",false) and seen.get("outside",false)
    elif choice.begins_with("beast_die_"):
        checked.death=b.health==0 and b.down_remaining==0
        checked.branch=b.defeat_clip==("defeat_a" if choice=="beast_die_chop" else "defeat")
    elif choice=="beast_exit":
        checked.safe=v.health==20
        checked.exit=seen.get("outside",false)
    for key in checked:
        if not checked[key]:push_error("War beast reference fixture failed: "+choice+"/"+key);return false
    return not checked.is_empty()
