extends Resource

@export var moon_frames: Array[int]=[]
@export var quest_frames: Array[int]=[]
@export var damage_frames: Array[int]=[]
@export var winner_flags: Array[int]=[]
@export var stone_ids: Array[String]=[]
@export var stone_names: Array[String]=[]
@export var guardian_message: Array[Dictionary]=[]
@export var victory_message: Array[Dictionary]=[]

func matches(mask: int, phase: int, combat: bool=false) -> bool:
    var frame: int=moon_frames[posmod(phase,8)]
    var checks: Array[int]=damage_frames if combat else quest_frames
    for bit in range(4):
        if mask & (1<<bit) and checks[bit]==frame:return true
    return false

func ending_code(frame: int, knight_kind: int) -> int:
    var phase_flag: int={47:1,45:4,49:2}.get(frame,0)
    return (phase_flag | winner_flags[knight_kind] | 128) if phase_flag!=0 and knight_kind in range(4) else 0

func name_for(mask: int) -> String:
    for bit in range(4):
        if mask==(1<<bit):return stone_names[bit]
    return "Moonstones"
