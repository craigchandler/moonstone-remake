class_name MoonstoneSoundPack
extends Resource

# Replaceable native assets; the simulation never loads or plays audio.
@export var pack_id: String = ""
@export var streams: Dictionary = {}
@export var timelines: Dictionary = {}
@export var cues: Dictionary = {}
@export var sustained: Array[String] = []
