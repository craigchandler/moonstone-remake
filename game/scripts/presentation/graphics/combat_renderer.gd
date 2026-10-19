extends RefCounted

# Renderer contract: draw a detached CombatFrame on a CanvasItem-compatible
# target. Backends own resources; the frame contains no textures or game objects.
func render(_canvas: Object, _frame: RefCounted, _background: Texture2D=null, _hold_binding: String="") -> void:
    push_error("Combat renderer must implement render")
