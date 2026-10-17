extends RefCounted
# Explicit reproducible visual fixtures. Positions and entry health are staged;
# damage, contacts, escape commands, death clocks and art use ordinary game code.
var tick:int=0
var checked:Dictionary={}
func reset(session:RefCounted)->void:
    var encounter:StringName=session.simulation.encounter
    session.start(&"competitive",encounter,{"count":1,"concurrent":1})
    var m:RefCounted=session.simulation
    m.actors[1].health=1000;m.actors[1].maximum=1000
    m.actors[1].x=245;m.actors[1].facing=-1
    m.actors[10].x=90;m.actors[10].cooldown_remaining=0
func advance(session:RefCounted)->void:
    var dragon:bool=session.simulation.encounter==&"dragon_fight"
    if tick==0:reset(session)
    var m:RefCounted=session.simulation
    var victim:Dictionary=m.actors[1]
    var foe:Dictionary=m.actors[10]
    if dragon:
        if tick==0:
            victim.health=1
            session.command(10,0,Vector2i.ZERO,"dragon_claw",1)
        if tick==130:
            checked.burn=victim.health==0 and victim.visual_kind=="dragon_victim"
            reset(session);m=session.simulation;victim=m.actors[1];foe=m.actors[10]
            victim.x=155
            session.command(10,0,Vector2i.ZERO,"dragon_flight",1)
        if tick==230:
            checked.rear=foe.height==-70 and foe.x==100
            foe.cooldown_remaining=0
            session.command(10,0,Vector2i.ZERO,"dragon_breath",1)
        if tick==240:checked.fire=not m.projectiles.is_empty()
        if tick==400:
            reset(session);m=session.simulation;victim=m.actors[1];foe=m.actors[10]
            foe.x=100;foe.rest_height=-70;foe.height=-70;foe.dragon_raised=true
            victim.x=125;victim.health=1
            session.command(10,0,Vector2i.ZERO,"dragon_bite",1)
        if tick==430:checked.bite=victim.health==0 and foe.special_clip=="execution_bite"
    elif m.encounter==&"beast_lair":
        if tick==0:
            foe.x=-60;victim.x=160;victim.health=20
            session.command(10,0,Vector2i.ZERO,"beast_charge",1)
        if tick==60:checked.impact=victim.health==15 and victim.visual_kind=="war_beast"
        if tick==100:
            checked.offscreen=foe.x<=-72 and foe.facing==-1
            foe.cooldown_remaining=0;victim.y=139
            session.command(10,0,Vector2i.ZERO,"beast_charge",-1)
        if tick==125:checked.lane=foe.y>=139 and foe.y<=167
        if tick==200:
            reset(session);m=session.simulation;victim=m.actors[1];foe=m.actors[10]
            foe.x=100;victim.x=160;victim.health=5;victim.facing=1
            session.command(10,0,Vector2i.ZERO,"beast_charge",1)
        if tick==235:checked.same=foe.special_clip=="execution_same" and victim.health==0
        if tick==500:
            reset(session);m=session.simulation;victim=m.actors[1];foe=m.actors[10]
            foe.x=220;victim.x=160;victim.health=5;victim.facing=1
            session.command(10,0,Vector2i.ZERO,"beast_charge",-1)
        if tick==535:checked.opposite=foe.special_clip=="execution_opposite" and victim.health==0
    else:
        if tick==0:
            victim.x=280;victim.y=177;foe.x=-50
            session.command(10,0,Vector2i.ZERO,"rat_leap",1)
        if tick==100:
            checked.perch=foe.rat_tree and foe.rest_height==-98 and m.rat_perch.owner==10
            victim.x=160;victim.y=157;victim.health=4
        if tick==130:checked.anchor=foe.held_target==1 and foe.rest_height==-98 and m.rat_perch.owner==10
        if tick==190:checked.squeeze=victim.health==0 and foe.special_clip=="rat_squeeze_finish"
        if tick==280:
            reset(session);m=session.simulation;victim=m.actors[1];foe=m.actors[10]
            # Occupied slot is explicit staging for the ordinary ground route.
            m.rat_perch.owner=99
            victim.x=170;foe.x=35
            session.command(10,0,Vector2i.ZERO,"rat_leap",1)
        if tick==388:
            checked.ride=victim.grab_remaining>0
            session.command(1,1,Vector2i.DOWN,"block")
        if tick==395:checked.counter=victim.hidden_by==0 and victim.grab_remaining==0 and victim.health==1000
        if tick==430:
            reset(session);m=session.simulation;victim=m.actors[1];foe=m.actors[10]
            m.rat_perch.owner=99
            victim.x=170;victim.health=5;foe.x=35
            session.command(10,0,Vector2i.ZERO,"rat_leap",1)
        if tick==585:checked.finish=victim.health==0 and foe.special_clip=="rat_throw_finish"
    m.advance();tick+=1
func verify()->bool:
    for key in checked:
        if not checked[key]:push_error("Combat reference fixture failed: "+key);return false
    return checked.size()>=4
