extends Node2D

func _ready() -> void:
    add_to_group("moonstone_input_surfaces")

# Shared presentation skin for loot, inventory, equipment and progression.
# Layout choices remain native/provisional until an original-screen comparison.
var art: Resource = preload("res://assets/classic/loot/art.tres")
var font: Font = ThemeDB.fallback_font

func draw_classic_background(chest: bool = false) -> void:
    draw_texture_rect(art.background if chest else art.panel_background, Rect2(0, 0, 640, 400), false)

func draw_icon(id: String, target: Rect2) -> void:
    if id.begins_with("key_") and art.icon_for(id) == null:
        var center: Vector2 = target.get_center()
        var gold := Color("ddc68c")
        draw_arc(center + Vector2(-10,0),6,0,TAU,16,gold,3)
        draw_line(center+Vector2(-4,0),center+Vector2(15,0),gold,3)
        draw_line(center+Vector2(10,0),center+Vector2(10,6),gold,3)
        draw_line(center+Vector2(15,0),center+Vector2(15,6),gold,3)
        return
    var texture: Texture2D = art.icon_for(id)
    if texture == null: return
    var size: Vector2 = texture.get_size() * 2
    size *= minf(1.0, minf(target.size.x / size.x, target.size.y / size.y))
    draw_texture_rect(texture, Rect2(target.get_center() - size / 2, size), false)

func text_at(point: Vector2, value: String, size: int = 13, colour: Color = Color("e5e6df")) -> void:
    draw_string(font, point, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, colour)

func paragraph(value: String, point: Vector2, width: float, colour: Color = Color("b7beb0")) -> void:
    var line: String = ""
    for word in value.split(" "):
        var candidate: String = word if line.is_empty() else line + " " + word
        if font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x > width and not line.is_empty():
            text_at(point, line, 13, colour)
            point.y += 18
            line = word
        else: line = candidate
    if not line.is_empty(): text_at(point, line, 13, colour)
