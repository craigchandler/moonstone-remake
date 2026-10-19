class_name MoonstoneSpriteLayers
extends Resource

# Reusable pose pieces in logical units. Colour pieces are neutral artwork with
# an alpha mask; modulation supplies a palette shade without tinting the armour.
# Clean/gore pieces also represent silhouette changes, not just red particles.
@export var pages: Array[Texture2D] = []
@export var poses: Array[Dictionary] = []
@export var palette: PackedColorArray = PackedColorArray()

func pieces(index: int, gore: bool) -> Array:
    if index < 0 or index >= poses.size():return []
    var pose: Dictionary=poses[index]
    return pose.shared + pose.get("gore" if gore else "clean",[])

func colour(slot: int, identity: int) -> Color:
    if slot < 0:return Color.WHITE
    var index: int=clampi(identity,0,4)*3+slot
    return palette[index] if index < palette.size() else Color.WHITE
