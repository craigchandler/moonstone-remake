extends "res://scripts/presentation/arena_view.gd"
var connection: RefCounted
var source_fight: RefCounted
var shown_tick: int=-1
var painted: Dictionary={}
func input_kind() -> String:return "arena_view"
func _physics_process(_delta: float) -> void:render_frame()
func render_frame() -> void:
    if source_fight==null or source_fight.simulation.actors.is_empty():return
    var model: RefCounted=source_fight.simulation
    session.simulation.apply(model.snapshot(),model.events)
    # Only presentation positions are predicted. Confirmed actors, clocks, damage,
    # RNG, hit testing and campaign state remain untouched in the source replica.
    for id in session.simulation.actors:
        var actor: Dictionary=session.simulation.actors[id]
        if actor.owner==connection.seat+1 and actor.health>0 and actor.remaining==0 and actor.stagger_remaining==0 and actor.special_remaining==0 and actor.hidden_by==0:
            var count: int=0
            for input in connection.pending_inputs:
                if input.action!="idle" or count>=8:break
                var speed: int=int(rule_set.actor_definitions[actor.kind].movement_per_tick)
                actor.x=clampi(actor.x+input.direction.x*speed,22,298)
                actor.y=clampi(actor.y+input.direction.y*speed,139,177)
                count+=1
        elif painted.has(id) and actor.health>0 and not actor.entering:
            var previous: Vector2=painted[id]
            if previous.distance_to(Vector2(actor.x,actor.y))<24:
                var point: Vector2=previous.lerp(Vector2(actor.x,actor.y),0.7)
                actor.x=roundi(point.x);actor.y=roundi(point.y)
        painted[id]=Vector2(actor.x,actor.y)
    if shown_tick!=model.tick:
        animator.update(session.simulation.actors,rule_set,art,maxi(1,model.tick-shown_tick) if shown_tick>=0 else 1)
        hit_effects.update(session.simulation,art);advance_sound();shown_tick=model.tick
    queue_redraw()
func _unhandled_key_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_G:
        gore_enabled=not gore_enabled;queue_redraw();get_viewport().set_input_as_handled()
