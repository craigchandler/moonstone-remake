extends RefCounted

# Numeric drawing contract, usable without a display or GPU. Resource paths are
# recorded instead of instance IDs so independent runs produce the same digest.
var commands: Array = []

func draw_texture_rect(texture: Texture2D, rect: Rect2, tile: bool, tint: Color=Color.WHITE) -> void:
    commands.append(["texture",texture.resource_path,rect,tile,tint])

func draw_texture_rect_region(texture: Texture2D, rect: Rect2, region: Rect2, tint: Color=Color.WHITE) -> void:
    commands.append(["region",texture.resource_path,rect,region,tint])

func draw_set_transform(point: Vector2, rotation: float=0.0, scale: Vector2=Vector2.ONE) -> void:
    commands.append(["transform",point,rotation,scale])

func draw_polygon(points: PackedVector2Array, colours: PackedColorArray, uvs: PackedVector2Array, texture: Texture2D) -> void:
    commands.append(["polygon",texture.resource_path,points,uvs,colours])

func draw_circle(point: Vector2, radius: float, colour: Color) -> void:
    commands.append(["circle",point,radius,colour])

func draw_arc(point: Vector2, radius: float, start: float, end: float, count: int, colour: Color, width: float) -> void:
    commands.append(["arc",point,radius,start,end,count,colour,width])

func draw_line(start: Vector2, end: Vector2, colour: Color, width: float) -> void:
    commands.append(["line",start,end,colour,width])

func draw_string(_font: Font, point: Vector2, value: String, alignment: int, width: float, size: int, colour: Color) -> void:
    commands.append(["text",point,value,alignment,width,size,colour])

func digest() -> String:
    return var_to_str(commands).sha256_text()
