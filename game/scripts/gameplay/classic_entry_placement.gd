extends "res://scripts/gameplay/entry_placement.gd"

@export var foot_offset: int = 52

func decide(facts: Dictionary) -> Dictionary:
    var counter: int=(int(facts.counter)+1)&3
    if counter==0:counter=1
    var edge: int=int(facts.low_edge)
    var span: int=(200-edge)&65535
    var portion: int=span>>1
    if counter==1:portion+=portion>>1
    elif counter==2:portion=span>>2
    return {"counter":counter,"depth":((edge+portion-47)&65535)+foot_offset}
