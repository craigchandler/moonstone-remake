class_name MapDragon
extends RefCounted

var rules: Resource
var active: bool = false
var position: Vector2i
var speed_x: int
var facing: int = 3
var phase: int = 0
var timer: int
var subtick: int = 0
# Slot0 is the human/party;1..3 are the independent solo rival records.
var target: int = 0

func _init(settings: Resource) -> void:
    rules = settings
    reset()

func reset() -> void:
    active = false
    position = rules.origin
    speed_x = rules.speed.x
    facing = 3
    phase = 0
    timer = rules.cycle
    subtick = 0
    target = 0

func advance(completed_rounds: int, target_position: Vector2i, alive: bool, current_knight: int = 0) -> bool:
    if not alive:
        reset()
        return false
    if not active:
        if completed_rounds < rules.spawn_counter * rules.rounds_per_counter: return false
        var selected: int=target
        reset()
        target=selected
        active = true
        return touches(target_position,current_knight)
    subtick += 1
    if subtick < rules.step_ticks: return touches(target_position,current_knight)
    subtick = 0
    timer -= 1
    if timer < 0: timer = rules.cycle
    position.x += speed_x
    if timer > rules.glide_threshold:
        position.y += signi(target_position.y - position.y) * int(rules.speed.y)
        # Gliding deliberately bypasses the boundary checks. The dragon can
        # leave the visible map before turning on the next flapping passage.
        if position.x > rules.right_limit:
            position.x = rules.right_return
            facing ^= 2
            speed_x = -speed_x
        if position.x <= rules.left_limit:
            position.x = rules.left_return
            facing ^= 2
            speed_x = -speed_x
        if position.y > rules.vertical_wrap: position.y = 0
        if position.y < 0: position.y = rules.vertical_wrap
        phase = (phase + 1) & 15
    return touches(target_position,current_knight)

func frame() -> int:
    return rules.glide_frame if timer <= rules.glide_threshold else phase / 2

func touches(knight: Vector2i, knight_id: int = 0) -> bool:
    if not active or target != knight_id: return false
    # Classic scan uses mi.c frame20's rectangle at dragon.x-10, not the wings.
    var a := Rect2i(position - Vector2i(10, 0), rules.contact_size)
    var b := Rect2i(knight, rules.knight_size)
    return a.position.x <= b.end.x and b.position.x <= a.end.x and a.position.y <= b.end.y and b.position.y <= a.end.y

func snapshot() -> Dictionary:
    return {"active": active, "x": position.x, "y": position.y,
        "speed_x": speed_x, "facing": facing, "phase": phase, "timer": timer,
        "subtick": subtick, "target": target}

func restore(data: Dictionary) -> void:
    active = data.active
    position = Vector2i(data.x, data.y)
    for field in ["speed_x", "facing", "phase", "timer", "subtick", "target"]:
        set(field, int(data[field]))
