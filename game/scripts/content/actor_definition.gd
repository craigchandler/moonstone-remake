class_name MoonstoneActorDefinition
extends Resource

@export var actor_id: StringName
@export var display_name: String = ""
@export var dragon_damage_shift: int = 0
@export var maximum_health: int = 20
@export var movement_per_tick: int = 2
@export var allowed_moves: PackedStringArray = PackedStringArray(["swing", "heavy", "lunge", "reverse", "upward", "dagger"])
@export var can_block: bool = true
@export var can_cancel_attacks: bool = true
@export var maximum_daggers: int = 10
@export var hurt_box: Rect2 = Rect2(-13, -61, 33, 61)
@export var reaction_ticks: int = 24
@export var stagger_ticks: int = 8
@export var walk_pose_ticks: int = 5
@export var defeat_ticks: int = 46
@export var ai_move: String = "swing"
@export var ai_secondary_move: String = ""
@export var ai_close_range: int = 0
@export var ai_preferred_range: int = 33
@export var ai_style: StringName = &"chase"
@export var ai_keep_distance: int = 0
@export var ai_depth: int = 5
@export var attack_cooldown_ticks: int = 0
@export var entry_attack_delay_ticks: int = 0
@export var reaction_clips: Dictionary = {}
@export var defeat_clips: Dictionary = {"heavy": "defeat_gory"}
@export var defeat_durations: Dictionary = {"defeat_gory": 90}
@export var hold_behavior_ids: Dictionary = {}
@export var execution_vulnerable: bool = false
@export var execution_moves: PackedStringArray = PackedStringArray()
@export var execution_clip: String = ""
@export var execution_ai_move: String = ""
@export var execution_ai_range: int = 0

func defeat_duration(clip: String) -> int:
    return int(defeat_durations.get(clip, defeat_ticks))
