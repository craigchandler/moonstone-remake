extends SceneTree

const Classic=preload("res://content/classic_art.tres")
const Layered=preload("res://content/generated/classic_layered_art.tres")
const Review=preload("res://debug/fixtures/layered_graphics_review.gd")
const Renderer=preload("res://scripts/presentation/graphics/classic_combat_renderer.gd")
const Recorder=preload("res://tests/support/draw_recorder.gd")
var failures: int=0

func check(ok: bool,label: String) -> void:
    if not ok:failures+=1;push_error(label)

func _initialize() -> void:run.call_deferred()

func run() -> void:
    var report: Dictionary=Review.new().inspect()
    check(report.failures.is_empty(),"Layer resources and normal combat draw path: "+str(report.failures))
    check(report.families==37 and report.colour_pieces>0,"All combat families and class masks are provisioned")
    for key in Classic.animations:
        var before: Resource=Classic.animations[key]
        var after: Resource=Layered.animations[key]
        check(before.poses==after.poses and before.clips==after.clips,"Preserve every pose anchor, clip and hold: "+key)
        for clip in before.clips:
            for elapsed in [0,1,7,31,150]:
                check(before.sample(clip,elapsed,180)==after.sample(clip,elapsed,180),"Preserve pose selection and logical size: "+key+"/"+clip)
    var renderer: RefCounted=Renderer.new(Layered)
    var recorder: RefCounted=Recorder.new()
    var knight: Resource=Layered.animation_for("knight")
    var idle: Dictionary=knight.sample("idle",0)
    var root:=Vector2(110,140)
    renderer.draw_pose(recorder,knight,idle,"blue",true,0,root)
    var original: Array=recorder.commands.duplicate(true)
    for identity in range(1,5):
        recorder.commands.clear();renderer.draw_pose(recorder,knight,idle,"blue",true,identity,root)
        check(recorder.commands.size()==original.size(),"Colour changes reuse the same pieces")
        var changed: bool=false
        for i in original.size():
            check(recorder.commands[i].slice(0,4)==original[i].slice(0,4),"Colour does not change textures, source bounds or logical placement")
            if recorder.commands[i][4]!=original[i][4]:changed=true
        check(changed,"Each identity recolours only the class pieces")
    recorder.commands.clear();renderer.draw_pose(recorder,knight,idle,"purple",true,0,root)
    var purple: Array=recorder.commands.duplicate(true)
    recorder.commands.clear();renderer.draw_pose(recorder,knight,idle,"purple",true,3,root)
    check(purple==recorder.commands,"Rival purple does not inherit the player's colour")
    if failures==0:print("PASS: layered combat resources, all unchanged clips/anchors, shared colour textures, rival identity and live drawing")
    quit(0 if failures==0 else 1)
