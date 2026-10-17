extends "res://scripts/gameplay/hold_behavior.gd"

@export var throw_damage: int = 5
@export var escape_clip: String = "rat_escape"
@export var escape_ticks: int = 30
@export var flight_ticks: int = 102
@export var lethal_clip: String = "rat_throw_finish"
@export var lethal_ticks: int = 96

func decide(context: Dictionary) -> Dictionary:
    # LAB_0264 checks fire+down BEFORE the ride timer, unlike Mudman carry.
    if context.release_requested:
        return {"operation":"release","clip":escape_clip,"ticks":escape_ticks}
    if context.remaining > 1:
        return {"operation":"wait"}
    return {"operation":"throw","damage":throw_damage,"flight_ticks":flight_ticks,
        "clip":lethal_clip,"ticks":lethal_ticks}
