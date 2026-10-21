extends "res://scripts/presentation/town_market_view.gd"
func input_kind() -> String:return "town_market_view"
func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion:mouse_active=true;pointer=event.position;hovered=caption_at(pointer);queue_redraw();return
    if not event is InputEventMouseButton or not event.pressed or event.button_index!=MOUSE_BUTTON_LEFT:return
    get_viewport().set_input_as_handled();mouse_active=true;pointer=event.position
    if help_visible:help_visible=false;queue_redraw();return
    if on_column(pointer,false):finished.emit();return
    for i in range(3):
        if row_rect(i).has_point(pointer):selected=i;activate();return
    for slot in buy_slots():
        if slot.rect.has_point(pointer):journey.request("trade",{"id":slot.id,"buy":true});return
    for slot in own_slots():
        if slot.rect.has_point(pointer):journey.request("trade",{"id":slot.id,"buy":false});return
