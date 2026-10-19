extends SceneTree
const Session=preload("res://scripts/session/local_session.gd")
const Animator=preload("res://scripts/presentation/actor_animator.gd")
const Rules=preload("res://content/foundation_rules.tres")
const Art=preload("res://content/generated/classic_layered_art.tres")
var failures: int=0
var checks: int=0
func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failures+=1;push_error(label)
func fresh(distance: int=60,depth: int=0,facing: int=1) -> RefCounted:
    var session: RefCounted=Session.new(Rules)
    session.start(&"competitive",&"balok_lair",{"count":1,"concurrent":1})
    var m: RefCounted=session.simulation
    m.actors[10].x=40 if facing==1 else 280;m.actors[10].y=166
    m.actors[10].facing=facing;m.actors[10].entering=false;m.actors[10].cooldown_remaining=0
    m.actors[1].x=m.actors[10].x+distance*facing;m.actors[1].y=166-depth
    return session
func _initialize() -> void:run.call_deferred()
func run() -> void:
    var oracle: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/balok_flight.json"))
    for expected in oracle.cases:
        var session: RefCounted=fresh(int(expected.distance),0,int(expected.facing))
        var m: RefCounted=session.simulation
        var actor: Dictionary=m.actors[10]
        session.command(10,0,Vector2i.ZERO,"balok_hop" if expected.distance<=70 else "balok_pounce")
        var seen_steps: int=0;var airborne_poses: int=0;var landed: int=-1;var done: int=-1
        var animator: RefCounted=Animator.new()
        for tick in 180:
            m.advance();var before: Dictionary=m.snapshot();animator.update(m.actors,Rules,Art)
            check(m.snapshot()==before,"layer sampling never drives flight")
            var flight: Dictionary=actor.get("balok",{}).get("flight",{})
            var step: int=flight.get("step",0)
            if step>seen_steps:
                seen_steps=step
                var point: Array=expected.poses[step-1]
                check([actor.x,actor.y,actor.height]==[int(point[0]),int(point[1]),0 if step==int(expected.steps) else int(point[2])],"source fixed-point flight vector "+str(expected.distance)+" step "+str(step))
                if step==int(expected.steps):landed=tick
            if animator.motions[10].get("phase","")=="active":airborne_poses+=1
            if tick>0 and actor.remaining==0:done=tick;break
        check(seen_steps==int(expected.steps),"distance determines original step count")
        check(airborne_poses==(int(expected.steps)-1)*5,"source airborne poses use calibrated five-tick steps")
        check(landed==int(expected.steps)*5,"original landing begins after preparation and flight")
        check(done==(int(expected.steps)+1)*5,"one landing pose completes before next decision")
        check(actor.cooldown_remaining==0,"landing uses conditional retry, no blanket cooldown")
    for facing in [1,-1]:
        for depth in [0,6,10]:
            for distance in [75,100]:
                var s: RefCounted=fresh(distance,depth,facing);s.advance(Vector2i.ZERO,"idle")
                check(s.simulation.actors[10].action==("balok_swipe" if distance==75 else "balok_maul"),"ten-pixel AI decision window permits close melee")
        var s: RefCounted=fresh(140,0,facing);s.simulation.actors[1].daggers=0;s.advance(Vector2i.ZERO,"idle")
        check(s.simulation.actors[10].action=="idle","source waits at midrange when knight has no daggers")
        s=fresh(200,0,facing)
        s.simulation.actors[10]["balok"]={"retry":5,"next_retry":0,"flight":{}}
        var starts: Array=[]
        for tick in 26:
            s.advance(Vector2i.ZERO,"idle")
            for e in s.simulation.events:
                if e.type=="attack" and e.actor==10:starts.append(tick)
        check(starts==[20],"five retry decisions delay only a far jump")
        for distance in [50,75,100]:
            s=fresh(distance,0,facing);s.simulation.actors[10]["balok"]={"retry":5,"next_retry":0,"flight":{}}
            s.advance(Vector2i.ZERO,"idle")
            check(s.simulation.events.any(func(e: Dictionary)->bool:return e.type=="attack" and e.actor==10),"close jump/melee bypasses far-jump retry")
    # Real repeated basic slashes. Target has enough HP to avoid a lethal branch;
    # no AI is advanced, and no visual clock can influence attack readiness.
    for facing in [1,-1]:
        for tapped in [false,true]:
            var session: RefCounted=fresh(45,0,facing)
            var m: RefCounted=session.simulation
            m.actors[1].x=160;m.actors[1].facing=facing
            m.actors[10].x=160+45*facing;m.actors[10].health=1000;m.actors[10].maximum=1000
            var starts: Array=[];var hits: int=0;var return_poses: Dictionary={}
            var animator: RefCounted=Animator.new()
            for tick in 150:
                session.command(1,1,Vector2i.ZERO,"idle" if tapped and tick%2 else "swing")
                m.advance();animator.update(m.actors,Rules,Art)
                for event in m.events:
                    if event.type=="attack" and event.actor==1:starts.append(tick)
                    if event.type=="damage" and event.actor==10:hits+=1
                if m.actors[1].attack_flow.get("branch","")=="contact" and m.actors[1].remaining>0:return_poses[animator.poses[1].index]=true
            check(starts.size()>=4 and hits==starts.size(),"held/tapped slashes repeat with exactly one hit each")
            for i in range(1,starts.size()):check(starts[i]-starts[i-1]>=31,"repeat retains the impact beat and three-pass contact return")
            check([14,15,16,17,18,19].all(func(index:int)->bool:return return_poses.has(index)),"successful slash shows the complete remaining blade path")
            check(m.actors[10].health==1000-hits*5,"slower repeat preserves per-hit damage")
    # Source hurt-list omissions are explicit gameplay policy. A sword already
    # active during a hurt window cannot restart it or add damage. It may hit
    # after that window; this is not permanent armour or a release-to-swing gate.
    for kind in ["balok","trogg_axe","trogg_spear","trogg_hammer","ratman","guardian","dragon","mudman","black_knight"]:
        for facing in [1,-1]:
            var session: RefCounted=fresh(45,0,facing)
            var m: RefCounted=session.simulation
            m.actors[1].x=160;m.actors[1].facing=facing
            m.actors[10]=m.make_actor(10,0,2,StringName(kind),Vector2i(160+45*facing,166),-facing)
            var foe: Dictionary=m.actors[10]
            foe.health=100;foe.maximum=100;foe.reaction="hurt_a";foe.reaction_remaining=30;foe.reaction_duration=30;foe.stagger_remaining=30
            session.command(1,1,Vector2i.ZERO,"swing")
            for n in 25:m.advance()
            check(foe.health==100 and foe.stagger_remaining==5,"hurt contact cannot restart recovery "+kind)
            m.projectiles.append({"id":99,"actor":1,"team":1,"x":foe.x-8*facing,"y":166,"height":-30,"facing":facing,"ttl":1})
            m.advance()
            check(foe.health==100 and foe.stagger_remaining==4,"dagger also respects the source hurt window "+kind)
            foe.stagger_remaining=0;foe.reaction_remaining=0;foe.reaction=""
            for n in 70:
                session.command(1,1,Vector2i.ZERO,"swing");m.advance()
            check(foe.health<100,"hurt protection ends when gameplay resumes "+kind)
    # The ordinary body remains vulnerable during the axe overhead windup.
    for facing in [1,-1]:
        var session: RefCounted=fresh(45,0,facing);var m: RefCounted=session.simulation
        m.actors[1].x=160;m.actors[1].facing=facing
        m.actors[10]=m.make_actor(10,0,2,&"trogg_axe",Vector2i(160+45*facing,166),-facing)
        m.actors[10].health=100;m.actors[10].maximum=100
        session.command(10,0,Vector2i.ZERO,"axe_chop");session.command(1,1,Vector2i.ZERO,"swing")
        for n in 15:m.advance()
        check(m.actors[10].health==95 and m.actors[10].remaining==0,"axe overhead can still be interrupted")
    check(Rules.attack_timing.moves.swing.contact_hold+Rules.attack_timing.moves.swing.contact_return==15,"basic slash contact return has three five-tick passes")
    check(Rules.moves.swing.windup+Rules.moves.swing.active+Rules.moves.swing.recovery==40,"full miss slash clock is retained")
    check(Rules.attack_timing.moves.heavy.contact_return==5 and Rules.moves.upward.active==30,"other knight attacks retain their clocks")
    check(fresh().simulation.snapshot().schema==25,"new flight state versions combat independently of campaign")
    if failures==0:print("PASS: ",checks," original Balok flight vectors, variable jump/landing clocks, melee and retry boundaries, held/tapped slash return and layer isolation")
    quit(1 if failures else 0)
