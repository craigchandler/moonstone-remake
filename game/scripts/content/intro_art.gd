extends Resource

const Images=preload("res://scripts/presentation/graphics/logical_image.gd")

@export var atlas: Texture2D
@export var palette: Texture2D
@export var music: AudioStream
@export var music_tick: int=0
@export var menu_music: AudioStreamWAV
@export var menu_loop_begin: int=0
@export var menu_loop_end: int=0
@export var background: Texture2D
@export var title: Texture2D
@export var arrow: Texture2D
@export var font_atlas: Texture2D
@export var glyphs: Dictionary={}
@export var runs: Array[Dictionary]=[]
@export var sections: Array[Dictionary]=[]
@export var credits: Array[Dictionary]=[]
@export var columns: int=16
@export var frames: int=0
@export var total_ticks: int=0

func pose_at(tick: int) -> Dictionary:
    var low: int=0
    var high: int=runs.size()-1
    while low<high:
        var mid: int=(low+high+1)/2
        if runs[mid].start<=tick:low=mid
        else:high=mid-1
    return runs[low]

func text_width(value: String) -> int:
    var width: int=0
    for ch in value:width+=int(glyphs.get(ch,glyphs[" "])[2])-2
    return width

func draw_text(view: CanvasItem,value: String,point: Vector2,centered: bool=true) -> void:
    var x: float=point.x-text_width(value) if centered else point.x
    for ch in value:
        var g: Array=glyphs.get(ch,glyphs[" "])
        view.draw_texture_rect_region(font_atlas,Rect2(x,point.y,g[2]*2,g[3]*2),Images.source_rect(font_atlas,Rect2(g[0],g[1],g[2],g[3])))
        x+=(g[2]-2)*2
