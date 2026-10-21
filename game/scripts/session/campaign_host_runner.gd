extends Node
const Host=preload("res://scripts/session/campaign_host.gd")
var host: RefCounted
func _init(count: int=2,seed: int=1,save_path: String="") -> void:
    host=Host.new(count,seed,save_path);process_mode=Node.PROCESS_MODE_ALWAYS
func _ready() -> void:Engine.physics_ticks_per_second=50
func _physics_process(_delta: float) -> void:host.poll();host.advance()
func stop() -> void:set_physics_process(false);host.close()
func _exit_tree() -> void:host.close()
