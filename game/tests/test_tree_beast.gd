extends SceneTree
const Model=preload("res://scripts/domain/combat_simulation.gd")
const Session=preload("res://scripts/session/local_session.gd")
const Animator=preload("res://scripts/presentation/actor_animator.gd")
var rules:Resource=preload("res://content/foundation_rules.tres")
var art:Resource=preload("res://content/classic_art.tres")
var failures:int=0
func check(ok:bool,label:String)->void:
    if not ok: failures+=1;push_error(label)
func fresh(encounter:String,count:int=1)->RefCounted:
    var m:RefCounted=Model.new(rules)
    m.start(&"competitive",0,StringName(encounter),{"count":count,"concurrent":count})
    for a in m.actors.values(): a.cooldown_remaining=0
    m.actors[1].health=1000;m.actors[1].maximum=1000
    return m
func cmd(m:RefCounted,id:int,action:String,facing:int=1)->void:
    check(m.submit(1 if id==1 else 0,{"actor":id,"tick":m.tick,"sequence":m.tick+1,"dx":0,"dy":0,"action":action,"facing":facing}),"command accepted")
func _initialize()->void:
    var m:RefCounted=fresh("rat_lair",2)
    check(m.rat_perch.owner==0 and m.rat_perch.x==160,"independent perch exists before first creature action")
    check(m.actors[10].x<0 and m.actors[11].x>320,"both Ratmen begin outside view")
    check(art.animation_for("ratman").clips.has("tree_anchor"),"original initial leaf object imported")
    m.actors[1].x=280;m.actors[1].y=177
    cmd(m,10,"rat_leap");cmd(m,11,"rat_leap",-1);m.advance()
    check(m.rat_perch.owner==10 and m.actors[10].rat_tree and not m.actors[11].rat_tree,"one shared slot; other Ratman uses opponent route")
    # Move away from the second Ratman's committed landing destination.
    m.actors[1].x=40
    for n in range(98):m.advance()
    check(m.actors[10].rest_height==-98 and m.actors[10].rat_tree,"upward journey ends at elevated anchor")
    check(m.actors[1].grab_remaining==0,"no hanging trap before rope contact")
    m.actors[1].x=160;m.actors[1].y=157;m.advance()
    check(m.actors[1].grabbed_by==10 and m.actors[10].hold_kind=="squeeze","perched rope catches knight using source contacts")
    check(m.rat_perch.owner==10 and m.actors[10].rest_height==-98,"starting hanging hold cannot execute the flight timeout transition")
    for n in range(20):m.advance()
    check(m.actors[10].rest_height==-98 and m.actors[10].height==-98 and m.rat_perch.owner==10,"treetop stays anchored throughout held interaction")
    for n in range(120):
        cmd(m,1,"block");m.pending[1].dy=1;m.advance()
        if m.actors[1].grab_remaining==0:break
    check(m.actors[1].grab_remaining==0 and m.rat_perch.owner==0,"counter frees victim and reservation")
    m=fresh("rat_lair");m.rat_perch.owner=99;m.actors[10].x=40;m.actors[1].x=160
    cmd(m,10,"rat_leap");m.advance();m.actors[1].x=280
    for n in range(100):m.advance()
    m.actors[1].x=160
    for n in range(15):m.advance()
    check(m.actors[1].grab_remaining==0 and m.actors[10].rest_height==0,"ordinary ground landing cannot create tree trap")
    m=fresh("rat_lair");m.actors[1].x=280;m.actors[1].y=177
    cmd(m,10,"rat_leap");m.advance()
    for n in range(277):m.advance()
    check(m.rat_perch.owner==0 and not m.actors[10].rat_tree and m.actors[10].remaining>0,"perch timeout frees slot and launches down toward opponent")
    m=fresh("rat_lair");cmd(m,10,"rat_leap");m.advance()
    m.actors[10].health=0;m.knock_down(m.actors[10],"defeat")
    check(m.rat_perch.owner==0,"death cannot leave shared tree slot occupied")
    # Edge-to-edge passes commit depth. Mid-pass sidesteps remain effective.
    m=fresh("beast_lair");m.actors[1].x=160
    check(m.actors[10].x==-60,"war beast initial source x is off screen")
    cmd(m,10,"beast_charge");m.advance()
    check(m.actors[10].x==-60 and m.actors[10].y==129,"first pass retains original default-arena entry lane")
    m.actors[1].y=150
    for n in range(100):m.advance()
    check(m.actors[10].x>=340 and m.actors[10].y==129 and m.actors[1].health==1000,"pass crosses far edge, never homes; sidestep evades")
    m.actors[1].y=139
    m.actors[10].cooldown_remaining=0;cmd(m,10,"beast_charge");m.advance()
    check(m.actors[10].x==380 and m.actors[10].facing==-1 and m.actors[10].y>=139 and m.actors[10].y<=167,"return starts beyond right edge and re-aims lane")
    m.actors[11]=m.make_actor(11,0,2,"war_beast",Vector2i(-5,166),-1)
    m.actors[11].beast_pass=1
    m.begin_beast_pass(m.actors[11])
    check(m.beast_lane_toggle==0 and m.actors[11].y==139+((2*3+11)%8)*4,"second beast shares the alternating offset toggle")
    for facing in [1,-1]:
        for victim_facing in [1,-1]:
            for hp in [20,5]:
                m=fresh("beast_lair");m.actors[10].x=100 if facing==1 else 220;m.actors[10].y=166
                m.actors[1].x=160;m.actors[1].facing=victim_facing;m.actors[1].health=hp
                cmd(m,10,"beast_charge",facing);m.advance()
                var saw:bool=false
                for n in range(30):
                    m.advance()
                    if m.actors[1].health<hp:saw=true;break
                check(saw,"both crossing directions contact knight")
                var same:bool=facing==victim_facing
                if hp==20:
                    check(m.actors[1].health==15 and m.actors[1].visual_kind=="war_beast" and m.actors[1].reaction==("impact_same" if same else "impact_opposite"),"nonlethal front/rear knight reaction, flat five HP")
                    for n in range(48):m.advance()
                    check(m.actors[1].visual_kind.is_empty(),"living knight recovers own art")
                else:
                    check(m.actors[1].hidden_by==10 and m.actors[10].special_clip==("execution_same" if same else "execution_opposite") and m.actors[1].down_remaining>0,"lethal composite replaces separate victim and waits")
                    var a:RefCounted=Animator.new();a.update(m.actors,rules,art)
                    check(a.poses[10].clip==m.actors[10].special_clip,"finisher selects imported original pose")
    for stroke in ["swing","heavy","lunge"]:
        m=fresh("beast_lair");m.actors[10].x=205;m.actors[10].y=166;m.actors[10].health=1
        m.actors[1].x=160;cmd(m,1,stroke);m.advance()
        for n in range(48):m.advance()
        check(m.actors[10].health==0 and m.actors[10].defeat_clip==("defeat_a" if stroke in ["heavy","upward"] else "defeat"),"real sword strike selects original beast death branch: "+stroke)
    for encounter in ["rat_lair","beast_lair","spear_lair","axe_lair","hammer_lair","troll_lair","balok_lair"]:
        var a:RefCounted=Session.new(rules);a.start(&"cooperative",StringName(encounter))
        var b:RefCounted=Session.new(rules);b.start(&"cooperative",StringName(encounter))
        for n in range(700):
            a.advance(Vector2i.ZERO,"idle");b.advance(Vector2i.ZERO,"idle")
        check(a.simulation.snapshot()==b.simulation.snapshot(),"new entrance/tree/charge state replays: "+encounter)
        var snap:Dictionary=a.simulation.snapshot();snap.rat_perch.owner=999
        check(a.simulation.rat_perch.get("owner",0)!=999,"snapshot does not expose perch state")
    if failures==0: print("PASS: initial perch, exclusive upward route, rope-only hanging trap, ground landing exclusion, timeout/counter/death release, offscreen passes, lane evasion, both impact and finishing directions, co-op replay")
    quit(1 if failures else 0)
