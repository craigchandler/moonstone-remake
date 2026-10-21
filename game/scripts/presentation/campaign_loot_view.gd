extends "res://scripts/presentation/loot_view.gd"
const RemoteInventory=preload("res://scripts/presentation/campaign_inventory_view.gd")
func open_character(tab: int=0,item: String="") -> void:
    if character_view!=null or not journey.looting():return
    character_view=RemoteInventory.new();character_view.journey=journey;character_view.loot_context=true
    add_child(character_view);character_view.set_tab(tab);character_view.finished.connect(close_character)
    if not item.is_empty():character_view.selected=character_view.rows().find(item);character_view.activate()
