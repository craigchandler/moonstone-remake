extends Resource

# Numeric original decision policy. The six-tick handler cadence is a native
# mapping of the fight frame budget, independent of artwork and attack clocks.
@export var profile_id:String="classic:knight_ai"
@export var api_version:int=1
@export var content_version:int=1
@export var decision_ticks:int=6
@export var swing_range:int=90
@export var heavy_range:int=95
@export var lunge_range:int=100
@export var guard_range:int=120
@export var keep_distance:int=80
@export var depth:int=4
@export var odds:PackedInt32Array=PackedInt32Array([50,40,30,30,20,10,8,6])
