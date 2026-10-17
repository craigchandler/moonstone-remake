extends Resource

@export var atlas: Texture2D
@export var music: AudioStream
@export var palettes: Dictionary={}
@export var runs: Array[Dictionary]=[]
@export var frames: int=0
@export var total_ticks: int=0
@export var music_tick: int=0
@export var moon_tick: int=0
@export var columns: int=8
@export var sections: Array[Dictionary]=[]

func pose_at(tick: int) -> Dictionary:
    for run in runs:
        if tick<run.start+run.ticks:return run
    return runs[-1]
