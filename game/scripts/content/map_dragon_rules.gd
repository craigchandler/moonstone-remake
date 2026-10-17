class_name MoonstoneMapDragonRules
extends Resource

# Native values verified against retail MOG and the reference overworld/clock.
# A classic lunar-counter increment takes four complete knight rounds.
@export var spawn_counter: int = 2
@export var rounds_per_counter: int = 4
@export var step_ticks: int = 2 # Original map frame budget: two 50 Hz ticks.
@export var origin: Vector2i = Vector2i(10, 100)
@export var speed: Vector2i = Vector2i(2, 1)
@export var cycle: int = 100
@export var glide_threshold: int = 60
@export var left_limit: int = -20
@export var left_return: int = -10
@export var right_limit: int = 350
@export var right_return: int = 345
@export var vertical_wrap: int = 200
@export var glide_frame: int = 3
@export var contact_size: Vector2i = Vector2i(9, 5)
@export var knight_size: Vector2i = Vector2i(8, 10)
