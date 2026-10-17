extends Node2D

const ART=preload("res://assets/classic/ending_complete/art.tres")
var film: Sprite2D
var palette: ShaderMaterial
var region: AtlasTexture
var shown_frame: int=-1
var code: int=-1

func _ready() -> void:
    film=Sprite2D.new()
    film.centered=false;film.scale=Vector2(2,2)
    palette=ShaderMaterial.new()
    palette.shader=preload("res://scripts/presentation/ending_palette.gdshader")
    film.material=palette
    region=AtlasTexture.new();region.atlas=ART.atlas
    film.texture=region
    add_child(film)

func show_tick(tick: int, winner_code: int) -> void:
    if not is_instance_valid(film):return
    var at: int=clampi(tick,0,ART.total_ticks-1)
    var pose: Dictionary=ART.pose_at(at)
    if shown_frame!=int(pose.frame):
        shown_frame=int(pose.frame)
        region.region=Rect2((shown_frame%ART.columns)*320,(shown_frame/ART.columns)*200,320,200)
    if code!=winner_code:
        code=winner_code
        palette.set_shader_parameter("palette",ART.palettes[winner_code])
    palette.set_shader_parameter("row",at)
