extends Resource

@export var clocks:Dictionary={}
@export var crush_damage_tick:int=12
@export var crush_release_tick:int=90
@export var crush_damage:int=10
@export var close_min:int=120
@export var close_max:int=140
@export var far_min:int=130
@export var far_max:int=150
@export var release_offset:int=137

func duration(stage:String)->int:return int(clocks[stage])
