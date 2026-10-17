extends "res://scripts/content/intro_art.gd"

@export var portraits: Array[Texture2D]=[]
@export var highlight: Texture2D
@export var life_icons: Array[Texture2D]=[]
@export var tokens: Array[Texture2D]=[]
@export var active_tokens: Array[Texture2D]=[]
@export var frogs: Array[Texture2D]=[]
@export var variants: Dictionary={}
var colour_cache: Dictionary={}

func coloured(texture: Texture2D,kind: int) -> Texture2D:
    if texture==null:return texture
    var choices: Array=variants.get(texture.resource_path,[])
    if choices.is_empty():return texture
    var path: String=choices[clampi(kind,0,choices.size()-1)]
    if path==texture.resource_path:return texture
    if not colour_cache.has(path):colour_cache[path]=load(path)
    return colour_cache[path]
