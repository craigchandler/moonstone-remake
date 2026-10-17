extends SceneTree
const Model=preload("res://scripts/domain/combat_simulation.gd")
const Animator=preload("res://scripts/presentation/actor_animator.gd")
var rules:Resource=preload("res://content/foundation_rules.tres")
var art:Resource=preload("res://content/classic_art.tres")
var failures:int=0
func check(ok:bool,label:String)->void:
    if not ok:failures+=1;push_error(label)
func fresh(encounter:String="beast_lair",phase:int=1)->RefCounted:
    var m:RefCounted=Model.new(rules)
    m.start(&"competitive",0,StringName(encounter),{"count":1,"concurrent":1,"moon_phase":phase})
    # Damage/turn tests stage a common lane; real entry lanes have their own suite.
    for a in m.actors.values():a.cooldown_remaining=10000;a.entering=false;a.y=166
    return m
func command(m:RefCounted,id:int,move:String,facing:int=1)->void:
    m.actors[id].cooldown_remaining=0
    check(m.submit(m.actors[id].owner,{"actor":id,"tick":m.tick,"sequence":m.tick+1,"dx":0,"dy":0,"action":move,"facing":facing}),"valid staged input")
func contact(m:RefCounted,move:String,guard:bool=false)->Array[Dictionary]:
    var foe:Dictionary=m.actors[10];var victim:Dictionary=m.actors[1]
    foe.x=100;foe.y=166;foe.action=move;foe.facing=1
    victim.y=166;victim.facing=-1;victim.guarding=guard
    for elapsed in range(int(rules.moves[move].active)):
        for x in range(-100,451,2):
            victim.x=x
            var hits:Array[Dictionary]=m.collect_hits(foe,rules.moves[move],elapsed)
            if not hits.is_empty():return hits
    return []
func _initialize()->void:
    var starting:Dictionary={"swing":5,"heavy":10,"lunge":4,"reverse":3,"upward":4,"dagger":3}
    for name in starting:check(rules.moves[name].damage==starting[name],"retail starting sword/dagger damage: "+name)
    var hp:Dictionary={"spear_lair":15,"axe_lair":20,"hammer_lair":20,"beast_lair":10,"rat_lair":5,"mud_lair":30,"balok_lair":30,"troll_lair":40,"dragon_fight":120,"guardian_fight":140,"black_knight_fight":20}
    for encounter in hp:
        var m:RefCounted=fresh(encounter)
        check(m.actors[10].health==hp[encounter] and m.actors[1].health==20,"original base HP and consistent beginner kit: "+encounter)
    # Actual sword contacts, unmodified full-health beast, both directions.
    for facing in [1,-1]:
        for move in ["swing","heavy","lunge","reverse","upward"]:
            var m:RefCounted=fresh()
            m.actors[1].x=160;m.actors[1].facing=facing
            m.actors[10].x=160+facing*(-35 if move=="reverse" else (80 if move=="heavy" else 45))
            command(m,1,move,facing)
            for n in range(60):m.advance()
            check(m.actors[10].health==(10 if move=="upward" else maxi(0,10-int(starting[move]))),"ground beast: overhead kills, other contacts wound; upward blade passes above: "+move+str(facing))
    # Source enemy damage through actual recovered contact geometry.
    var rows:Dictionary={"spear_lair":{"spear_thrust":3},"axe_lair":{"axe_swing":3,"axe_chop":3},"hammer_lair":{"hammer_swing":2,"hammer_chop":2},"beast_lair":{"beast_charge":5},"troll_lair":{"troll_sweep":7,"troll_smash":7},"balok_lair":{"balok_swipe":5,"balok_maul":5},"mud_lair":{"mud_grab":2,"mud_reach":2},"dragon_fight":{"dragon_claw":30,"dragon_bite":20,"dragon_breath":30,"dragon_foot":34},"guardian_fight":{"guardian_lunge":10}}
    for encounter in rows:
        for move in rows[encounter]:
            var m:RefCounted=fresh(encounter)
            var hits:Array[Dictionary]=contact(m,move)
            check(not hits.is_empty() and hits[0].amount==rows[encounter][move],"original incoming damage: "+move)
    var fire_model:RefCounted=fresh("dragon_fight")
    fire_model.release_fire(fire_model.actors[10],rules.moves.dragon_breath)
    check(fire_model.projectiles[0].damage==34,"Dragon ground-fire object differs from30-damage body contact")
    for phase in [0,1,4]:
        for move in ["rat_bite","rat_strike"]:
            var m:RefCounted=fresh("rat_lair",phase)
            var hits:Array[Dictionary]=contact(m,move,true)
            var amount:int=({0:6,1:3,4:8} if move=="rat_bite" else {0:3,1:1,4:5})[phase]
            check(m.actors[10].health=={0:7,1:5,4:12}[phase] and not hits.is_empty() and hits[0].amount==amount and not hits[0].blocked,"lunar Ratman HP and unblockable strike: "+move+str(phase))
    for direction in [1,-1]:
        # Both impacts and surviving high/low hits turn exactly once and retreat.
        for cause in ["contact","swing","upward"]:
            var m:RefCounted=fresh();var beast:Dictionary=m.actors[10]
            beast.x=160;beast.facing=direction;beast.beast_pass=1
            if cause=="contact":m.Beast.impact(beast)
            else:m.Beast.hurt(beast,cause)
            var wait:int=12 if cause=="contact" else (54 if cause=="upward" else 42)+12
            for n in range(wait):m.advance()
            check(beast.facing==-direction and beast.y==181 and beast.action=="beast_charge","turn after contact/hurt: "+cause+str(direction))
            var before:int=beast.x
            for n in range(15):m.advance()
            check((beast.x-before)*direction<0,"retreat in the direction of entry")
        var m:RefCounted=fresh();var beast:Dictionary=m.actors[10]
        beast.x=-60 if direction==1 else 380;beast.facing=direction
        m.actors[1].y=139
        command(m,10,"beast_charge",direction)
        for n in range(115):m.advance()
        check(beast.x>=392 if direction==1 else beast.x<=-72,"entire run sprite clears viewport before edge pause")
    # Full kill clocks, independently ejected body, final loop, and interruption.
    var clips:Dictionary=art.animation_for("war_beast").clips
    check(clips.execution_opposite.frames.size()==49 and clips.execution_opposite.weights.reduce(func(a,b):return a+b,0)*6==582,"all seven final execution cycles imported")
    for direction in [1,-1]:
        for same in [true,false]:
            var m:RefCounted=fresh();var beast:Dictionary=m.actors[10];var victim:Dictionary=m.actors[1]
            beast.x=160;beast.facing=direction;victim.facing=direction if same else -direction
            victim.health=0;m.knock_down(victim,"defeat");m.beast_finish(beast,victim)
            var duration:int=258 if same else 366
            for n in range(duration-1):
                m.advance()
                if same and n==240:check(victim.hidden_by==0 and victim.visual_kind=="war_beast" and victim.defeat_clip=="ejected","separate thrown knight appears before beast turns")
            check(beast.special_remaining>0,"no early execution cutoff")
            m.advance()
            check(beast.special_clip=="impact" if same else beast.terminal_clip=="execution_opposite","complete execution ending")
            if same:
                for n in range(190):m.advance()
                check(victim.down_remaining==0 and victim.hidden_by==0 and beast.facing==-direction,"settled corpse survives beast departure")
            var before:Dictionary=m.snapshot();var animator:RefCounted=Animator.new();animator.update(m.actors,rules,art)
            check(m.snapshot()==before,"presentation cannot change kill clocks")
    var m:RefCounted=fresh();m.actors[1].health=0;m.beast_finish(m.actors[10],m.actors[1]);m.knock_down(m.actors[10],"defeat")
    check(m.actors[1].hidden_by==0 and m.actors[10].beast.get("death",false),"interrupting beast execution cannot strand victim")
    var co:RefCounted=Model.new(rules)
    co.start(&"cooperative",0,&"beast_lair",{"count":1,"concurrent":1})
    co.actors[10].x=205;co.actors[10].facing=-1
    co.actors[1].health=0;co.actors[1].facing=1
    co.knock_down(co.actors[1],"defeat");co.beast_finish(co.actors[10],co.actors[1])
    check(co.actors[10].beast.duration==582,"co-op retains full repeated list while another knight survives")
    for n in range(180):co.advance()
    co.actors[2].x=160;co.actors[2].y=166
    command(co,2,"swing",1)
    for n in range(15):co.advance()
    check(co.actors[10].health==5 and co.actors[1].hidden_by==0 and co.actors[10].beast.stage=="hurt_b","real co-op sword hit interrupts execution and detaches dead victim")
    for name in ["beast_same","beast_opposite","beast_hurt","beast_hit","beast_exit"]:
        for mirrored in [false,true]:
            var session:RefCounted=preload("res://scripts/session/local_session.gd").new(rules)
            var fixture:RefCounted=preload("res://debug/fixtures/beast_review_fixture.gd").new()
            fixture.choice=name;fixture.mirror=mirrored
            for n in range(fixture.length()):fixture.advance(session)
            check(fixture.verify(session),"real-contact review scene: "+name+str(mirrored))
    if failures==0:print("PASS: retail HP and damage, full-health beast sword hits, lunar Ratmen, turns and full exits in both directions, complete rear kill and original frontal fight-end delay and detached victim")
    quit(1 if failures else 0)
