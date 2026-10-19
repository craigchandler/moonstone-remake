extends RefCounted

# Detached host values for presentation. There is no command/step/AI API here.
var state: Dictionary = {}
var tick: int = 0
var actors: Dictionary = {}
var projectiles: Array = []
var events: Array = []
var rat_perch: Dictionary = {}
var spawn_remaining: int = 0

func apply(snapshot: Dictionary, feedback: Array) -> void:
    state=snapshot.duplicate(true);tick=state.tick;actors=state.actors
    projectiles=state.projectiles;rat_perch=state.rat_perch;spawn_remaining=state.spawn_remaining
    events=feedback.duplicate(true)

func snapshot() -> Dictionary: return state.duplicate(true)

func outcome() -> String:
    var alive: Array = [false,false]
    for actor in actors.values():
        if actor.health>0: alive[actor.team-1]=true
    return "ongoing" if alive[0] and alive[1] else ("victory" if alive[0] else ("defeat" if alive[1] else "draw"))
