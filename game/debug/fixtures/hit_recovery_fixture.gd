extends RefCounted

# Staged positions and, for Dragon contacts, an upgraded60HP knight. All damage
# and recoveries come through ordinary commands/contact resolution.
var choice:String="recover_hammer~lunge"
var mirror:bool=false
var tick:int=0
var checked:Dictionary={}
var seen:Dictionary={}
var target:int=10
var initial_health:int=0
var recovery_y:int=166
var hit_tick:int=-1
var recovered_tick:int=-1
var expected_clip:String=""
var expected_family:String=""
var recovery_duration:int=0

func length()->int:return 180

func reset(session:RefCounted)->void:
    var parts:PackedStringArray=choice.trim_prefix("recover_").split("~")
    var kind:String=parts[0];var move:String=parts[1]
    var enc:String={"hammer":"hammer_lair","rat":"rat_lair","troll":"troll_lair","balok":"balok_lair","guardian":"guardian_fight","guardian_release":"guardian_fight","dragon":"dragon_fight","fire":"dragon_fight"}[kind]
    session.start(&"competitive",StringName(enc),{"count":1,"concurrent":1,"moon_phase":4})
    var sim:RefCounted=session.simulation;sim.spawn_remaining=0
    var knight:Dictionary=sim.actors[1];var enemy:Dictionary=sim.actors[10]
    for actor in sim.actors.values():actor.entering=false;actor.cooldown_remaining=10000
    knight.x=160;knight.y=166;knight.facing=1
    enemy.x=205;enemy.y=166;enemy.facing=-1
    if kind in ["hammer","rat"]:
        target=10
        enemy.x=240 if move=="heavy" else (125 if move=="reverse" else (260 if move=="dagger" else 205))
        expected_family=enemy.kind
        expected_clip=sim.rules.actor_definitions[enemy.kind].reaction_clips.get(move,"hurt_a")
        if kind=="rat":
            if move=="lunge":enemy.x=240
            # The small Ratman is reached by an upward sword while airborne;
            # the dagger lane also needs the ordinary small depth offset.
            if move=="upward":enemy.height=-30;enemy.rest_height=-30
            if move=="dagger":knight.y+=3
    else:
        target=1;knight.facing=-1;enemy.facing=1
        enemy.x=20 if kind=="troll" else (85 if kind=="balok" else 35)
        expected_family="knight_finishes";expected_clip="hop"
        if kind in ["dragon","fire"]:
            knight.health=60;knight.maximum=60
            enemy.rest_height=0;enemy.height=0;enemy.x=75
            if kind=="dragon":knight.x=120
        if kind=="guardian_release":enemy.x=25;knight.x=150
    if mirror:
        for actor in sim.actors.values():actor.x=320-actor.x;actor.facing=-actor.facing
    # The original Dragon feet occupy the fixed left-hand body, independent of
    # the knight's facing. They do not acquire a mirrored right-hand body.
    if kind=="dragon":knight.x=120;enemy.x=75;enemy.facing=1
    initial_health=sim.actors[target].health
    if kind=="fire":
        sim.release_fire(enemy,sim.rules.moves.dragon_breath)
        # Put the knight on a real first-frame contact of the stationary flame.
        var points:Array=sim.rules.geometry.dragon.points_for("ground_fire",1,144)
        knight.x=sim.projectiles[0].x+int(points[0][0]);knight.y=sim.projectiles[0].y
    else:
        var attacker:int=1 if target==10 else 10
        sim.actors[attacker].cooldown_remaining=0
        session.command(attacker,sim.actors[attacker].owner,Vector2i.ZERO,move)
    recovery_y=sim.actors[target].y

func advance(session:RefCounted)->void:
    if tick==0:reset(session)
    var sim:RefCounted=session.simulation
    var actor:Dictionary=sim.actors[target]
    # A held movement/attack input must not cut a committed recovery short.
    if hit_tick>=0 and recovered_tick<0:
        session.command(target,actor.owner,Vector2i.UP,"idle")
    elif recovered_tick>=0 and tick<recovered_tick+8:
        session.command(target,actor.owner,Vector2i.UP,"idle")
    sim.advance()
    for event in sim.events:
        if event.type=="hold" and event.actor==target:
            seen.hold=true
            if hit_tick<0:hit_tick=tick
        if event.type=="damage" and event.actor==target:
            seen.damage=int(seen.get("damage",0))+1
            if hit_tick<0:hit_tick=tick
    if actor.reaction==expected_clip and actor.reaction_remaining>0:
        if recovery_duration==0:recovery_duration=actor.reaction_duration
        seen.reaction=true
    elif seen.get("reaction",false) and recovered_tick<0:
        recovered_tick=tick
    tick+=1

func verify(session:RefCounted)->bool:
    var actor:Dictionary=session.simulation.actors[target]
    checked.damage=(seen.get("hold",false) and seen.get("damage",0)==0 and actor.health==initial_health) if choice=="recover_guardian_release~guardian_grab" else (seen.get("damage",0)==1 and actor.health>0 and actor.health<initial_health)
    checked.reaction=seen.get("reaction",false)
    checked.complete=recovered_tick>hit_tick and actor.reaction_remaining==0 and actor.visual_kind.is_empty()
    checked.duration=recovery_duration==session.simulation.rules.recovery.duration(expected_family,expected_clip,0)
    for key in checked:
        if not checked[key]:push_error("Hit/recovery fixture failed "+choice+"/"+key);return false
    return true
