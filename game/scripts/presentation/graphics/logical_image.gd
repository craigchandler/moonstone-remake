extends RefCounted

# Frozen classic image metrics are content metadata, not dimensions inferred
# from replacement pixels. New artwork may supply explicit logical dimensions.
const METRICS=preload("res://scripts/presentation/graphics/classic_image_sizes.json")
const PREFIX="res://assets/classic/"

static func size(texture: Texture2D, logical_size: Vector2=Vector2.ZERO) -> Vector2:
    if logical_size!=Vector2.ZERO:return logical_size
    var key: String=texture.resource_path.trim_prefix(PREFIX)
    var value: Array=METRICS.data.get(key,[])
    if value.size()==2:return Vector2(value[0],value[1])
    push_error("Artwork requires explicit logical dimensions: "+texture.resource_path)
    return Vector2.ZERO

static func source_rect(texture: Texture2D, logical_rect: Rect2, logical_size: Vector2=Vector2.ZERO) -> Rect2:
    var scale: Vector2=texture.get_size()/size(texture,logical_size)
    return Rect2(logical_rect.position*scale,logical_rect.size*scale)

static func pixel_scale(texture: Texture2D) -> Vector2:
    return texture.get_size()/size(texture)
