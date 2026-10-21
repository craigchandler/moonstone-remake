extends Node

# Independent authority clock, shared by the dedicated and in-game host.
const Host=preload("res://scripts/session/duel_host.gd")
var host: RefCounted
func _init(rules: Resource) -> void:
    host=Host.new(rules)
    process_mode=Node.PROCESS_MODE_ALWAYS
func _ready() -> void:Engine.physics_ticks_per_second=int(host.rules.tick_rate)
func _physics_process(_delta: float) -> void:
    host.poll();host.advance()
func stop(message: String="SERVER STOPPED") -> void:
    set_physics_process(false);host.close(message)
func _exit_tree() -> void:host.close()
