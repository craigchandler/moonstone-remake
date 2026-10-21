extends "res://scripts/presentation/inventory_view.gd"
const RemoteService=preload("res://scripts/presentation/campaign_service_screen.gd")
# Tab selection changes this panel only. Opening a confirmed service panel must
# not issue another service command or edit the confirmed journey projection.
func set_tab(index: int) -> void:
    if loot_context and index not in [0,2]:return
    tab=clampi(index,0,5)
    service_screen=RemoteService.new({3:"healer",4:"tavern",5:"mystic"}[tab]) if tab>=3 else null
    if service_screen!=null:service_screen.journey=journey
    selected=0;target_item="";inspection="";page=0;hovered="";queue_redraw()
