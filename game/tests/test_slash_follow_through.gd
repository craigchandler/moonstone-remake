extends SceneTree
const Session=preload("res://scripts/session/local_session.gd")
const Animator=preload("res://scripts/presentation/actor_animator.gd")
const Sampler=preload("res://scripts/presentation/graphics/classic_pose_sampler.gd")
const Timing=preload("res://scripts/domain/weighted_frames.gd")
const Cues=preload("res://scripts/presentation/combat_sound_cues.gd")
const Rules=preload("res://content/foundation_rules.tres")
const Flat=preload("res://content/classic_art.tres")
const Layers=preload("res://content/generated/classic_layered_art.tres")
const Sounds=preload("res://assets/classic/audio/sounds.tres")
var checks:int=0
var failures:int=0
func check(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;push_error(label)
func _initialize()->void:
 var animation:Resource=Flat.animation_for("knight")
 # Real contacts against different body sizes, using the production hit branch.
 for kind in ["balok","trogg_axe","trogg_spear","trogg_hammer","giant_troll","ratman","guardian","dragon","black_knight"]:
  for facing in [1,-1]:
   var s:RefCounted=Session.new(Rules);s.start(&"competitive",&"balok_lair",{"count":1,"concurrent":1})
   var m:RefCounted=s.simulation
   m.actors[1].x=160;m.actors[1].facing=facing
   m.actors[10]=m.make_actor(10,0,2,StringName(kind),Vector2i(160+45*facing,166),-facing)
   m.actors[10].health=1000;m.actors[10].maximum=1000
   var flat:RefCounted=Animator.new();var layered:RefCounted=Animator.new();var sounds:RefCounted=Cues.new()
   var visited:Array=[];var expected:Array=[];var contacts:int=0;var tail_ticks:int=0;var finished:bool=false
   s.command(1,1,Vector2i.ZERO,"swing")
   for n in 60:
    m.advance();var state:Dictionary=m.snapshot();flat.update(m.actors,Rules,Flat);layered.update(m.actors,Rules,Layers)
    var audio:Dictionary=sounds.collect(m,layered.poses,Layers,Sounds)
    check(state==m.snapshot(),"follow-through rendering and audio leave authority unchanged")
    check(flat.poses[1].index==layered.poses[1].index,"flat/layered knight select the same follow-through")
    for e in m.events:
     if e.type=="damage" and e.actor==10:contacts+=1
    var actor:Dictionary=m.actors[1]
    if actor.attack_flow.get("branch","")=="contact" and actor.remaining>0:
     if expected.is_empty():
      var impact:Dictionary=animation.sample("swing",actor.attack_flow.impact_elapsed,Rules.moves.swing.active,"active")
      expected=animation.clips.swing.frames.slice(animation.clips.swing.frames.find(impact.index))
     var pose:Dictionary=layered.poses[1]
     if visited.is_empty() or visited[-1]!=pose.index:visited.append(pose.index)
     check(pose.phase==("active" if actor.remaining>15 else "follow_through"),"impact beat precedes complete follow-through")
     check(pose.get("silent_transition",false),"visual continuation cannot restart sword audio")
     check(audio.cues.all(func(c:Dictionary)->bool:return c.actor!=1),"no duplicate sword cues in continuation")
     tail_ticks+=1
    elif tail_ticks>0 and actor.remaining==0:
     finished=true;check(layered.poses[1].clip=="idle","finished slash settles to idle")
   check(contacts==1 and m.actors[10].health==995,"follow-through does not add another hit "+kind)
   check(visited==expected,"every remaining swing pose draws once in order "+kind+str(facing)+str(visited))
   check(tail_ticks==20 and finished,"follow-through retains five impact ticks and the15-tick visible follow-through")
 # Start at every possible active contact age: never rewind the blade, including
 # late contacts. The final readying pose must be visible before returning idle.
 for active_age in 15:
  var impact:Dictionary=animation.sample("swing",active_age,15,"active")
  var expected:Array=animation.clips.swing.frames.slice(animation.clips.swing.frames.find(impact.index))
  var seen:Array=[]
  for age in 15:
   var motion:Dictionary={"clip":"swing","phase":"follow_through","elapsed":age,"duration":15,"from_active":active_age,"active_duration":15,"silent_transition":true}
   var pose:Dictionary=Sampler.sample(animation,motion)
   if seen.is_empty() or seen[-1]!=pose.index:seen.append(pose.index)
  check(seen==expected,"early/late contact never skips or rewinds the remaining blade poses")
 if failures==0:print("PASS: ",checks," real-contact follow-through checks across nine monsters/both facings, every active contact age, flat/layer parity,20-tick contact path, single damage and presentation/audio isolation")
 quit(1 if failures else 0)
