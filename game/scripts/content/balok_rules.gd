extends Resource

# Original distance/decision rules, with a fixed native clock calibrated to film.
@export var profile_id: String = "classic:balok"
@export var content_version: int = 1
@export var step_ticks: int = 5
@export var target_offset: int = 80
@export var maximum_steps: int = 20
@export var retry_calls: int = 5
@export var close_range: int = 70
@export var swipe_range: int = 80
@export var maul_range: int = 120
@export var wait_range: int = 180
