extends SceneTree

const Frame=preload("res://scripts/presentation/graphics/combat_frame.gd")
const Renderer=preload("res://scripts/presentation/graphics/classic_combat_renderer.gd")
const Recorder=preload("res://tests/support/draw_recorder.gd")
const Cases=preload("res://tests/support/graphics_cases.gd")
const Expected=preload("res://tests/support/classic_draw_baseline.json")
var frame: RefCounted=Frame.new()
var renderer: RefCounted=Renderer.new(Cases.Art)
var recorder: RefCounted=Recorder.new()
var failures: int=0

func _initialize() -> void:
    var results: Dictionary=Cases.new().run_cases(draw_frame)
    for key in Expected.data:
        if results.get(key)!=Expected.data[key]:
            failures+=1;push_error("Classic drawing changed: "+key)
    if results.size()!=Expected.data.size():failures+=1;push_error("Drawing case coverage changed")
    if failures==0:print("PASS: 49 classic drawing traces (including restored Balok hit blood): placement, source regions, layering, palettes, gore, projectiles, holds, composite deaths and remains")
    quit(1 if failures else 0)

func draw_frame(session: RefCounted, animator: RefCounted, effects: RefCounted, tick: int) -> Array:
    frame.capture(session.simulation,animator,effects,Cases.Rules,session.simulation.encounter,
        tick%2==0,tick%5,{2:2,10:3} if tick%3==0 else {},{})
    recorder.commands.clear();renderer.render(recorder,frame)
    return recorder.commands
