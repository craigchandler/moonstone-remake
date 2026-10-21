extends "res://scripts/presentation/town_service_screen.gd"
func advance(host: Node) -> void:sync_audio(host);host.queue_redraw()
func adjust(amount: int,host: Node) -> void:
    journey.request("donation",{"amount":clampi(donation+amount,0,journey.inventory.gold)});host.queue_redraw()
func accept(host: Node) -> void:journey.request("donate");host.selected=0
func activate(host: Node) -> void:
    if phase in ["greeting","dice"]:journey.request("visit_next")
    elif phase=="reply":host.finished.emit()
    elif phase=="donation":journey.request("donate")
    elif phase=="tavern":journey.request("wager",{"amount":clampi(host.selected+1,1,5)})
    host.selected=0;host.queue_redraw()
func key(event: InputEventKey,host: Node) -> void:
    if event.keycode in [KEY_1,KEY_2] and phase=="donation":
        journey.request("donation",{"amount":mini(journey.inventory.gold,10 if event.keycode==KEY_1 else 15)})
    else:super.key(event,host)
