extends RefCounted

# Reproduce the reported transition with ordinary commands and live AI. Initial
# positions skip entry walking; clocks, collision, damage and assets are normal.
const Session=preload("res://scripts/session/local_session.gd")
const Rules=preload("res://content/foundation_rules.tres")
var choice:String="ratground_natural"
var mirror:bool=false
var tick:int=0
var checked:Dictionary={}
var rows:Array=[]
var events:Array=[]
var final_state:Dictionary={}
var saw_tree:bool=false
var tree_landing:int=-1
var departure:int=-1
var landing:int=-1
var first_attack:int=-1
var first_hit:int=-1
func length()->int:return 780
func setup(session:RefCounted)->void:
    session.start(&"competitive",&"rat_lair",{"count":1,"concurrent":1})
    var m:RefCounted=session.simulation;var foe:Dictionary=m.actors[10];var knight:Dictionary=m.actors[1]
    foe.x=280 if mirror else 40;foe.y=166;foe.facing=-1 if mirror else 1;foe.cooldown_remaining=0;foe.entering=false
    knight.x=160;knight.y=166;knight.facing=-foe.facing
func advance(session:RefCounted)->void:
    if tick==0:setup(session)
    var m:RefCounted=session.simulation;var foe:Dictionary=m.actors[10];var knight:Dictionary=m.actors[1]
    var direction:Vector2i=Vector2i.ZERO
    # Once the tree departure is committed, sidestep its aimed landing point
    # horizontally and wait in melee range before the Ratman touches ground.
    if saw_tree and not foe.rat_tree:
        var target_x:int=foe.leap_to_x+35*(-1 if mirror else 1)
        direction.x=signi(target_x-knight.x) if abs(target_x-knight.x)>1 else 0
    var old_height:int=foe.height
    session.advance(direction,"idle")
    if foe.rat_tree:saw_tree=true
    if foe.rat_tree and foe.rest_height==-98 and tree_landing<0:tree_landing=tick
    if saw_tree and not foe.rat_tree and departure<0:departure=tick
    if saw_tree and not foe.rat_tree and old_height<0 and foe.height==0 and landing<0:landing=tick
    for e in m.events:
        if e.type in ["attack","damage"]:
            var row:Dictionary=e.duplicate(true);row.tick=tick;events.append(row)
            if landing>=0 and e.type=="attack" and e.actor==10 and e.move in ["rat_strike","rat_bite"] and first_attack<0:first_attack=tick
            if e.type=="damage" and e.actor==1 and first_hit<0:first_hit=tick
    rows.append({"tick":tick,"x":foe.x,"y":foe.y,"height":foe.height,"remaining":foe.remaining,"action":foe.action,"tree":foe.rat_tree,"knight_hp":knight.health})
    tick+=1
func verify(session:RefCounted)->bool:
    checked={"tree_route":saw_tree and tree_landing>=0 and departure>tree_landing,"perch_retained":departure-tree_landing==181,"landed":landing>departure,"prompt_ground_attack":first_attack>landing and first_attack-landing<=2,"no_flight_contact":first_hit>first_attack,"ordinary_damage":session.simulation.actors[1].health<20 and session.simulation.actors[1].health>0}
    final_state=session.simulation.snapshot()
    return not checked.values().has(false)
func report()->Dictionary:
    return {"choice":choice,"mirror":mirror,"checks":checked,"final_state":final_state,"tree_landing":tree_landing,"departure":departure,"landing":landing,"first_ground_attack":first_attack,"first_hit":first_hit,"events":events,"rows":rows}
static func batch(host:Node)->void:
    var reports:Array=[];var ok:bool=true
    for mirrored in [false,true]:
        var fixture:RefCounted=load("res://debug/fixtures/ratman_ground_fixture.gd").new();fixture.mirror=mirrored
        var session:RefCounted=Session.new(Rules)
        for n in fixture.length():fixture.advance(session)
        ok=fixture.verify(session) and ok;reports.append(fixture.report())
    print("RATMAN_GROUND=",JSON.stringify(reports));host.get_tree().quit(0 if ok else 1)
