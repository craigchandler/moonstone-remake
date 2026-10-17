extends Resource

# Native interaction definitions. Source draw holds use six 50 Hz ticks per
# creature step. These clocks still need input-matched original comparison.
@export var spear_impale_ticks: int = 102
@export var balok_lift_ticks: int = 66
@export var balok_shake_ticks: int = 96 # two poses, eight repetitions
@export var balok_eat_a_ticks: int = 150
@export var balok_eat_b_ticks: int = 144
@export var mud_appear_ticks: int = 42
@export var mud_carry_ticks: int = 240 # original 0x28 creature steps
@export var mud_release_ticks: int = 18
@export var mud_swallow_ticks: int = 510 # includes original terminal wait80
@export var mud_quick_ticks: int = 72
@export var knight_flung_ticks: int = 408
# Existing retail weighted death poses: kneeling hold20, six native ticks/pass.
@export var kneeling_windows: Dictionary = {
    "defeat":Vector2i(24,144),"defeat_b":Vector2i(24,144),"hop":Vector2i(54,174)
}
# Retail5920:80FF updates the job AND owner facing. This turn is already
# baked into the kneeling atlas; a new drawing sequence must inherit it once.
@export var kneeling_facing_signs: Dictionary = {"defeat":-1,"defeat_b":-1,"hop":-1}
