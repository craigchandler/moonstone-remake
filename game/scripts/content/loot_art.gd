class_name MoonstoneLootArt
extends Resource

@export var background: Texture2D
@export var panel_background: Texture2D
@export var icons: Dictionary = {}
@export var single_background: Texture2D
@export var pixel_font: Texture2D
@export var sword_cursor: Texture2D
@export var glyphs: Dictionary = {}

func icon_for(item: String) -> Texture2D:
    if item=="scroll_of_acquisition":return preload("res://assets/classic/targeted_scrolls/scroll_of_acquisition.png")
    if item=="scroll_of_the_hawk":return preload("res://assets/classic/targeted_scrolls/scroll_of_the_hawk.png")
    return icons.get(item)
