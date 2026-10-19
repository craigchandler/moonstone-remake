extends Resource

# Simulation-only source policy. Six native ticks approximate one retail handler
# pass; no artwork or animation callback supplies these clocks.
@export var profile_id:String="classic:ratman"
@export var api_version:int=1
@export var content_version:int=1
@export var decision_ticks:int=6
@export var hit_wait_steps:int=15
@export var perch_ticks:int=180
@export var strike_range:int=40
@export var bite_range:int=50
