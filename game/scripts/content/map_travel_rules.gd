class_name MoonstoneMapTravelRules
extends Resource

# Imported once from the verified retail tables; no source parsing during play.
@export var terrain: PackedByteArray = PackedByteArray()
@export var regions: PackedByteArray = PackedByteArray()
@export var columns: int = 40
@export var rows: int = 25
@export var cell_size: int = 8
@export var foot_offset: Vector2i = Vector2i(4, 10)

func mask_at(point: Vector2i) -> int:
    if terrain.is_empty(): return 0
    var foot: Vector2i = point + foot_offset
    # Existing saved bounds include the lower edge. Clamp each axis rather than
    # letting the feet wrap into the next row or read beyond the slowdown grid.
    var x: int = clampi(foot.x / cell_size, 0, columns-1)
    var y: int = clampi(foot.y / cell_size, 0, rows-1)
    return terrain[y*columns+x]
