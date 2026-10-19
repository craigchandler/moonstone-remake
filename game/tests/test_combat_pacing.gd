extends SceneTree
const Model = preload("res://scripts/domain/combat_simulation.gd")
const Animator = preload("res://scripts/presentation/actor_animator.gd")
const Cues = preload("res://scripts/presentation/combat_sound_cues.gd")
const Sounds = preload("res://assets/classic/audio/sounds.tres")
var rules: Resource = preload("res://content/foundation_rules.tres")
var art: Resource = preload("res://content/classic_art.tres")
var failures: int = 0
var checks: int = 0
func check(ok: bool, message: String) -> void:
    checks+=1
    if not ok: failures+=1;push_error(message)
func send(m: RefCounted,id: int,action: String,direction: Vector2i=Vector2i.ZERO) -> void:
    check(m.submit(m.actors[id].owner,{"actor":id,"sequence":m.tick+1,"tick":m.tick,"dx":direction.x,"dy":direction.y,"action":action}),"owned pacing input accepted")
func fresh(move: String,facing: int=1,outcome: String="miss") -> RefCounted:
    var m: RefCounted=Model.new(rules)
    var spear: bool=move=="spear_thrust"
    m.start(&"competitive",2,&"spear_lair" if spear else &"duel",{"count":1,"concurrent":1})
    var source: Dictionary=m.actors[10 if spear else 1]
    var target: Dictionary=m.actors[1 if spear else 2]
    source.x=160;source.y=166;source.facing=facing;source.entering=false;source.cooldown_remaining=0
    target.x=160+facing*({"swing":45,"heavy":80,"reverse":-35,"lunge":80,"dagger":110,"spear_thrust":130}.get(move,45))
    target.y=139 if outcome=="miss" else 166
    target.facing=facing if move=="reverse" else -facing;target.health=1 if outcome=="lethal" else 1000;target.maximum=target.health
    return m
func _initialize() -> void:
    var totals: Dictionary={"swing":40,"heavy":50,"reverse":35,"lunge":55,"dagger":25,"spear_thrust":25}
    for move in totals:
        for facing in [1,-1]:
            # No contact must preserve every authored attack pose and full clock.
            var m: RefCounted=fresh(move,facing)
            var source: int=10 if move=="spear_thrust" else 1
            var animator: RefCounted=Animator.new();var seen: Dictionary={}
            send(m,source,move);m.advance()
            for age in range(totals[move]):
                animator.update(m.actors,rules,art);seen[animator.poses[source].index]=true
                check(m.actors[source].remaining==totals[move]-age,"full per-move tick allocation "+move)
                m.advance()
            check(m.actors[source].remaining==0,"full attack ends on configured tick "+move)
            var animation: Resource=art.animation_for(m.actors[source].kind)
            for pose in animation.clips[move].frames:check(seen.has(pose),"full path retains drawing "+move+":"+str(pose))
            if move=="dagger":continue
            for outcome in ["contact","block","lethal"]:
                m=fresh(move,facing,outcome);animator=Animator.new()
                var scheduler: RefCounted=Cues.new();var damage_count: int=0;var branch_at: int=-1
                var impact: int=-1;var completed: int=-1;var return_cues: int=0
                send(m,source,move);m.advance()
                for age in range(totals[move]+20):
                    if outcome=="block":send(m,1 if source==10 else 2,"block")
                    m.advance();animator.update(m.actors,rules,art)
                    var state: Dictionary=m.snapshot()
                    var cues: Dictionary=scheduler.collect(m,animator.poses,art,Sounds)
                    check(m.snapshot()==state,"audio/animation cannot change clocks or outcomes")
                    for event in m.events:
                        if event.type=="damage":damage_count+=1
                    var actor: Dictionary=m.actors[source]
                    if actor.attack_flow.get("branch","")=="contact" and actor.remaining>0:
                        if branch_at<0:branch_at=age;impact=animator.poses[source].index
                        var p: Dictionary=rules.attack_timing.moves[move]
                        if move=="swing":
                            check(animator.poses[source].phase==("active" if actor.remaining>p.contact_hold+p.contact_return else "follow_through") and animator.poses[source].index>=impact,"successful slash continues without rewinding")
                            for cue in cues.cues:
                                if cue.actor==source:return_cues+=1
                        elif actor.remaining>p.contact_return:
                            check(animator.poses[source].index==impact,"retained contact drawing")
                        elif animator.poses[source].get("silent_transition",false):
                            for cue in cues.cues:
                                if cue.actor==source:return_cues+=1
                    if actor.remaining==0:completed=age;break
                check(damage_count==(0 if outcome=="block" else 1),"one damage transaction across outcome tail "+move)
                if outcome=="contact":
                    var p: Dictionary=rules.attack_timing.moves[move]
                    check(branch_at>=0 and completed-branch_at==int(p.get("contact_impact",0))+p.contact_hold+p.contact_return,"contact continuation has its own finite clock")
                    check(return_cues==0,"ready pose cannot replay skipped sword sounds")
                else:
                    check(branch_at==-1,"blocked/lethal hits retain their existing full choreography")
    # Heavy's high damage now has real commitment, with a finite late release.
    for move in ["swing","heavy","lunge","reverse","dagger"]:
        var p: Dictionary=rules.attack_timing.moves[move];var definition: Dictionary=rules.moves[move]
        for age in range(totals[move]):
            for action in ["idle","block"]:
                var m: RefCounted=fresh(move)
                send(m,1,move);m.advance()
                for t in range(age):m.advance()
                var y: int=m.actors[1].y
                var allowed: bool=p.cancel_windup if age<definition.windup else (age>=definition.windup+definition.active+p.recovery_lock)
                send(m,1,action,Vector2i.DOWN if action=="idle" else Vector2i.ZERO);m.advance()
                check((m.actors[1].y!=y if action=="idle" else m.actors[1].guarding)==allowed,"every-age defensive commitment "+move)
    # Dagger: release after 0.40s, half-second throw, same hit while guarding.
    for facing in [1,-1]:
        var m: RefCounted=fresh("dagger",facing,"contact")
        var ammo: int=m.actors[1].daggers;var release: int=-1;var hits: int=0
        send(m,1,"dagger");m.advance()
        for age in range(1,70):
            send(m,2,"block");m.advance()
            for event in m.events:
                if event.type=="dagger":release=age
                if event.type=="damage":
                    hits+=1
                    check(not event.blocked and event.amount==3,"original dagger contact bypasses guard with unchanged damage")
                    check(m.actors[2].reaction=="hurt_b" and m.actors[2].reaction_remaining==30,"dagger hit uses complete six-hold knight reaction")
        check(release==20 and hits==1 and m.actors[1].daggers==ammo-1,"one projectile and ammo spend at measured release")
    # Mixed simultaneous contacts keep the lethal path regardless of target ID.
    for lethal_id in [2,3]:
        var mixed: RefCounted=fresh("swing",1,"contact")
        mixed.actors[3]=mixed.make_actor(3,0,2,"knight",Vector2i(205,166),-1)
        mixed.actors[2].health=1000;mixed.actors[3].health=1000
        mixed.actors[lethal_id].health=1
        send(mixed,1,"swing");mixed.advance()
        for age in range(11):mixed.advance()
        check(mixed.actors[lethal_id].health==0 and mixed.actors[1].attack_flow.branch=="full","simultaneous lethal contact cannot inherit a survivor's short tail")
    # Resource changes are bounded and state manifest records the chosen content.
    var custom: Resource=rules.duplicate(true)
    custom.attack_timing.moves.heavy.cancel_windup=true
    var m: RefCounted=Model.new(custom);m.start(&"competitive",2)
    send(m,1,"heavy");m.advance();send(m,1,"idle",Vector2i.UP);m.advance()
    check(m.actors[1].remaining==0,"content can replace preparation policy without changing engine")
    custom.attack_timing.moves.heavy.contact_hold=-1
    m.start(&"competitive",2);m.actors[1].action="heavy"
    check(m.AttackFlow.policy(custom,m.actors[1]).is_empty(),"malformed policy is rejected before applying a tail")
    check(m.snapshot().schema==25 and m.snapshot().attack_timing_versions=={"classic:combat_pacing":{"api":1,"version":5}},"explicit branch state versions combat independently of campaign")
    if failures==0:print("PASS: ",checks," pacing checks; full/contact/block/lethal clocks, mirrored poses, damage once, risk, dagger hit/guard, silent returns and bounded content")
    quit(1 if failures else 0)
