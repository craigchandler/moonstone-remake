extends "res://scripts/presentation/wizard_view.gd"
func input_kind() -> String:return "wizard_view"
func advance_visit() -> void:sync_audio();queue_redraw()
func activate() -> void:
    if help_visible:help_visible=false;queue_redraw();return
    journey.request("visit_next")
