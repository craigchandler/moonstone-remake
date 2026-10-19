class_name CombatRules
extends Resource

@export var content_id: StringName = &"encounters.v31"
@export var knight_ai: Resource = preload("res://content/behaviors/classic_knight.tres")
@export var ratman: Resource = preload("res://content/behaviors/classic_ratman.tres")
@export var balok: Resource = preload("res://content/behaviors/classic_balok.tres")
@export var entry_placement: Resource = preload("res://content/generated/classic_beast_entry.tres")
@export var encounter_scaling: Resource = preload("res://content/behaviors/classic_lair_scaling.tres")
@export var attack_timing: Resource = preload("res://content/classic_attack_timing.tres")
@export var guardian: Resource = preload("res://content/generated/guardian.tres")
@export var knockback: Resource = preload("res://content/generated/knockback.tres")
@export var recovery: Resource = preload("res://content/classic_hit_recovery.tres")
@export var death_frames: Resource = preload("res://content/generated/death_frames.tres")
@export var finishes: Resource = preload("res://content/finish_rules.tres")
@export var hold_behaviors: Dictionary = {
    "classic:ratman.back_ride":preload("res://content/behaviors/ratman_ride.tres")
}
@export var tick_rate: int = 50
@export var actor_definitions: Dictionary = {
    "knight": preload("res://content/actors/knight.tres"),
    "troll": preload("res://content/actors/troll.tres"),
    "trogg_spear": preload("res://content/actors/trogg_spear.tres"),
    "trogg_axe": preload("res://content/actors/trogg_axe.tres"),
    "giant_troll": preload("res://content/actors/giant_troll.tres"),
    "balok": preload("res://content/actors/balok.tres"),
    "trogg_hammer": preload("res://content/actors/trogg_hammer.tres"),
    "war_beast": preload("res://content/actors/war_beast.tres"),
    "ratman": preload("res://content/actors/ratman.tres"),
    "mudman": preload("res://content/actors/mudman.tres"),
    "dragon": preload("res://content/actors/dragon.tres"),
    "guardian": preload("res://content/actors/guardian.tres"),
    "black_knight": preload("res://content/actors/black_knight.tres")
}
@export var depth_tolerance: int = 15
@export var geometry: Dictionary = {
    "knight": preload("res://content/generated/classic_collision.tres"),
    "trogg_spear": preload("res://content/generated/spear_collision.tres"),
    "trogg_axe": preload("res://content/generated/axe_collision.tres"),
    "giant_troll": preload("res://content/generated/troll_collision.tres"),
    "balok": preload("res://content/generated/balok_collision.tres"),
    "trogg_hammer": preload("res://content/generated/trogg_hammer_collision.tres"),
    "war_beast": preload("res://content/generated/war_beast_collision.tres"),
    "ratman": preload("res://content/generated/ratman_collision.tres"),
    "mudman": preload("res://content/generated/mudman_collision.tres"),
    "dragon": preload("res://content/generated/dragon_collision.tres"),
    "guardian": preload("res://content/generated/guardian_collision.tres"),
    "black_knight": preload("res://content/generated/classic_collision.tres")
}
@export var moves: Dictionary = {
    "swing": {"windup": 10, "active": 15, "recovery": 15, "range": 38, "damage": 5},
    "heavy": {"windup": 20, "active": 15, "recovery": 15, "range": 42, "damage": 10},
    "lunge": {"windup": 20, "active": 10, "recovery": 25, "range": 62, "damage": 4},
    "reverse": {"windup": 10, "active": 20, "recovery": 5, "range": 55, "damage": 3, "direction": -1},
    # Seven source drawing passes (1/1/4/1), six ticks per pass. Clean local
    # examples span0.82..0.86s; shorter contacts/busy scenes remain separate.
    "upward": {"windup": 6, "active": 30, "recovery": 6, "range": 48, "damage": 4},
    "dagger": {"windup": 20, "active": 1, "recovery": 4, "range": 0, "damage": 3, "unblockable": true},
    "spear_thrust": {"windup": 5, "active": 15, "recovery": 5, "range": 136, "damage": 3,
        "block_scale": 0, "depth_tolerance": 5, "group_spacing": 35},
    # Five-tick drawing cadence; full chop/reference contact-repeat compared.
    # Full swing and Hammer cadence remain source-informed provisional clocks.
    "axe_swing": {"windup": 5, "active": 15, "recovery": 5, "range": 96, "damage": 3,
        "block_scale": 0, "depth_tolerance": 12, "group_spacing": 35},
    "axe_chop": {"windup": 15, "active": 10, "recovery": 10, "range": 157, "damage": 3,
        "block_scale": 0, "depth_tolerance": 12, "group_spacing": 35},
    # Full finite drawing holds use six ticks per source unit; video comparisons
    # support the order, but uninterrupted wall-clock parity remains provisional.
    "troll_sweep": {"windup": 6, "active": 18, "recovery": 0, "range": 98, "damage": 7,
        "unblockable": true, "windup_step": 2, "windup_distance": 32, "depth_tolerance": 5},
    "troll_smash": {"windup": 30, "active": 6, "recovery": 12, "range": 160, "damage": 7,
        "unblockable": true, "depth_tolerance": 5},
    # Provisional native arcs and phases; melee uses recovered original points.
    "balok_swipe": {"windup": 6, "active": 12, "recovery": 36, "range": 78, "damage": 5,
        "unblockable": true, "windup_step": 1, "windup_distance": 12, "turn_away": true, "depth_tolerance": 5},
    "balok_maul": {"windup": 18, "active": 30, "recovery": 18, "range": 109, "damage": 5,
        "unblockable": true, "depth_tolerance": 5},
    "balok_pounce": {"windup": 15, "active": 90, "recovery": 15, "range": 160, "damage": 5,
        "unblockable": true, "leap_range": 160, "leap_peak": 96, "landing_radius": 10, "landing_window": 8, "depth_tolerance": 5},
    "balok_hop": {"windup": 12, "active": 40, "recovery": 12, "range": 100, "damage": 5,
        "unblockable": true, "leap_range": 100, "leap_peak": 42, "landing_radius": 10, "landing_window": 8, "depth_tolerance": 5},
    # Hammer first raised-weapon drawing has high contacts, followed by two
    # empty-contact drawings. Keep all six frames before its final return.
    "hammer_swing": {"windup": 5, "active": 15, "recovery": 5, "range": 95, "damage": 2, "block_scale": 0, "depth_tolerance": 6, "group_spacing": 35},
    "hammer_chop": {"windup": 0, "active": 30, "recovery": 5, "range": 130, "damage": 2, "block_scale": 0, "depth_tolerance": 6, "group_spacing": 35},
    "beast_charge": {"windup": 0, "active": 120, "recovery": 0, "range": 24, "damage": 5, "unblockable": true, "charge_speed": 5, "depth_tolerance": 5},
    # Retail creature frame budget is six 50 Hz ticks. Pauses/arc interpolation
    # are native and remain provisional until an input-matched Amiga comparison.
    "rat_strike": {"windup": 12, "active": 12, "recovery": 18, "range": 42, "damage": 1, "unblockable": true, "depth_tolerance": 5},
    "rat_bite": {"windup": 6, "active": 18, "recovery": 0, "range": 50, "damage": 3, "unblockable": true, "depth_tolerance": 5},
    # Recovery is the tree-perch wait; the Ratman policy gives floor landings0.
    "rat_leap": {"windup": 12, "active": 84, "recovery": 180, "range": 270, "damage": 0, "unblockable": true, "leap_range": 270, "leap_peak": 65, "depth_tolerance": 5, "grab_ticks": 84, "hold_kind": "ride"},
    "rat_retreat": {"windup": 0, "active": 102, "recovery": 0, "range": 0, "damage": 0, "leap_range": 150, "leap_peak": 120, "no_contact": true},
    "mud_reach": {"windup": 12, "active": 18, "recovery": 12, "range": 100, "damage": 2, "unblockable": true, "depth_tolerance": 5, "grab_ticks": 65},
    "mud_grab": {"windup": 26, "active": 10, "recovery": 26, "range": 60, "damage": 2, "unblockable": true, "depth_tolerance": 5, "grab_ticks": 65},
    # Historical dragon_claw ID is original Strike8: the LOW horizontal fire stream.
    "dragon_claw": {"windup": 36, "active": 60, "recovery": 6, "range": 310, "damage": 30, "unblockable": true, "depth_tolerance": 5},
    "dragon_bite": {"windup": 0, "active": 42, "recovery": 0, "range": 105, "damage": 20, "unblockable": true, "depth_tolerance": 5},
    "dragon_breath": {"windup": 0, "active": 60, "recovery": 6, "range": 150, "damage": 30, "ground_fire_damage": 34, "unblockable": true, "depth_tolerance": 5, "ground_fire": true},
    "dragon_flight": {"windup": 0, "active": 78, "recovery": 0, "range": 0, "damage": 0, "leap_range": 0, "leap_peak": 80, "transition_height": -70, "no_contact": true},
    "dragon_lower": {"windup": 0, "active": 54, "recovery": 0, "range": 0, "damage": 0, "leap_range": 0, "leap_peak": 120, "transition_height": -30, "no_contact": true},
    "dragon_foot": {"windup": 12, "active": 30, "recovery": 0, "range": 90, "damage": 34, "unblockable": true, "depth_tolerance": 10},
    "guardian_lunge": {"windup": 6, "active": 18, "recovery": 6, "range": 100, "damage": 10, "unblockable": true, "windup_step": 1, "windup_distance": 28, "turn_away": true, "depth_tolerance": 4},
    "guardian_strike": {"windup": 0, "active": 96, "recovery": 0, "range": 130, "damage": 10, "unblockable": true, "no_contact": true, "depth_tolerance": 4},
    "guardian_grab": {"windup": 0, "active": 30, "recovery": 0, "range": 140, "damage": 8, "unblockable": true, "no_contact": true, "depth_tolerance": 4}
}
@export var encounters: Dictionary = {
    "spear_lair": {"creature": "trogg_spear", "count": 4, "concurrent": 2, "knight_health": 20,
        "display_name": "Spear Trogg lair", "enemy_label": "Spear Troggs"},
    "axe_lair": {"creature": "trogg_axe", "count": 4, "concurrent": 2, "knight_health": 20,
        "display_name": "Axe Trogg lair", "enemy_label": "Axe Troggs"},
    "troll_lair": {"creature": "giant_troll", "count": 1, "concurrent": 1, "knight_health": 20,
        "display_name": "Troll lair", "enemy_label": "Club Troll", "objective": "Dodge the club; guard cannot stop it"},
    "balok_lair": {"creature": "balok", "count": 1, "concurrent": 1, "knight_health": 20,
        "display_name": "Balok lair", "enemy_label": "Balok", "objective": "Evade jumps and claws; guard won't help"},
    "hammer_lair": {"creature": "trogg_hammer", "count": 4, "concurrent": 2, "knight_health": 20, "display_name": "Hammer Trogg lair", "enemy_label": "Hammer Troggs"},
    "beast_lair": {"creature": "war_beast", "count": 3, "concurrent": 1, "knight_health": 20, "entry_profile":"classic:beast_entry", "display_name": "War beast lair", "enemy_label": "War beasts", "objective": "Sidestep the committed charge"},
    "rat_lair": {"creature": "ratman", "count": 6, "concurrent": 2, "knight_health": 20, "display_name": "Ratmen lair", "enemy_label": "Ratmen", "objective": "Evade leaps; guard + down breaks a hold"},
    "mud_lair": {"creature": "mudman", "count": 2, "concurrent": 1, "knight_health": 20, "display_name": "Mudmen lair", "enemy_label": "Mudmen", "objective": "Avoid the reach; guard + down breaks a hold"},
    "dragon_fight": {"creature": "dragon", "count": 1, "concurrent": 1, "knight_health": 20, "display_name": "The roaming Dragon", "enemy_label": "Dragon", "objective": "Evade fire and claws; Wyrm talismans protect"},
    "guardian_fight": {"creature": "guardian", "count": 1, "concurrent": 1, "knight_health": 20, "display_name": "Valley Guardian", "enemy_label": "Guardian", "objective": "Dodge the demon; defeat costs three lives"},
    "black_knight_fight": {"creature": "black_knight", "count": 1, "concurrent": 1, "knight_health": 20, "display_name": "Black Knight", "enemy_label": "Black Knight", "objective": "Rival knight; equipment and stats determine damage"}
}
@export var dagger_speed: int = 8
@export var dagger_lifetime: int = 40
@export var dagger_origin: Vector2i = Vector2i(72, -43)
@export var guard_feedback_ticks: int = 8
