extends RefCounted

# Export-safe diagnostic: exercises the same pack and renderer as normal play.
# It checks resources and drawing commands, not graphical pixel equivalence.
const Art=preload("res://content/generated/classic_layered_art.tres")
const Rules=preload("res://content/foundation_rules.tres")
const Renderer=preload("res://scripts/presentation/graphics/classic_combat_renderer.gd")
const Frame=preload("res://scripts/presentation/graphics/combat_frame.gd")
const Session=preload("res://scripts/session/local_session.gd")
const Animator=preload("res://scripts/presentation/actor_animator.gd")
const Effects=preload("res://scripts/presentation/combat_hit_effects.gd")

func inspect() -> Dictionary:
    var failures: Array[String]=[]
    var paths: Dictionary={}
    var poses: int=0
    var pages: int=0
    var colours: int=0
    for animation in Art.animations.values()+Art.effects.values():
        if paths.has(animation.resource_path):continue
        paths[animation.resource_path]=true
        if animation.layers==null:
            failures.append("Missing layered animation "+animation.resource_path);continue
        if not animation.atlases.is_empty():failures.append("Layer pack retains baked colour atlases")
        if animation.poses.size()!=animation.layers.poses.size():failures.append("Layer pose count differs")
        poses+=animation.poses.size()
        for texture in animation.layers.pages:
            pages+=1
            if texture.get_width()>2048 or texture.get_height()>2048:failures.append("Layer page exceeds bounds")
        for index in animation.layers.poses.size():
            for gore in [false,true]:
                for piece in animation.layers.pieces(index,gore):
                    var texture: Texture2D=animation.layers.pages[piece.page]
                    if not Rect2(Vector2.ZERO,texture.get_size()).encloses(piece.region):failures.append("Layer source exceeds page")
                    if not Rect2(Vector2.ZERO,animation.poses[index].region.size).encloses(Rect2(piece.offset,piece.size)):failures.append("Piece exceeds logical pose")
                    if piece.slot>=0:colours+=1
    var counter:=Counter.new()
    var renderer: RefCounted=Renderer.new(Art)
    for encounter in Rules.encounters:
        var session: RefCounted=Session.new(Rules)
        session.start(&"competitive",StringName(encounter))
        var animator: RefCounted=Animator.new()
        var effects: RefCounted=Effects.new()
        for tick in 80:
            session.advance(Vector2i.RIGHT,"heavy" if tick%30==0 else "")
            animator.update(session.simulation.actors,Rules,Art);effects.update(session.simulation,Art)
            var frame: RefCounted=Frame.new()
            frame.capture(session.simulation,animator,effects,Rules,StringName(encounter),tick%2==0,tick%5,{},{})
            renderer.render(counter,frame)
    if counter.layer_draws==0 or counter.other_regions!=0:failures.append("Combat did not exclusively draw layer pages")
    return {"families":paths.size(),"poses":poses,"pages":pages,"colour_pieces":colours,
        "layer_draws":counter.layer_draws,"other_regions":counter.other_regions,"failures":failures}

func report(host: Node) -> void:
    var result: Dictionary=inspect()
    print("LAYERED_GRAPHICS_STATE="+JSON.stringify(result))
    if result.failures.is_empty():print("PASS: exported layered combat resources, colours, gore and live pose drawing")
    host.get_tree().quit(0 if result.failures.is_empty() else 1)

class Counter extends RefCounted:
    var layer_draws: int=0
    var other_regions: int=0
    func draw_texture_rect_region(texture: Texture2D,_rect: Rect2,_region: Rect2,_tint: Color=Color.WHITE) -> void:
        if texture.resource_path.begins_with("res://assets/classic/layered/"):layer_draws+=1
        else:other_regions+=1
    func draw_texture_rect(_texture: Texture2D,_rect: Rect2,_tile: bool,_tint: Color=Color.WHITE) -> void:pass
    func draw_set_transform(_point: Vector2,_rotation: float=0.0,_scale: Vector2=Vector2.ONE) -> void:pass
    func draw_circle(_point: Vector2,_radius: float,_colour: Color) -> void:pass
    func draw_arc(_point: Vector2,_radius: float,_start: float,_end: float,_count: int,_colour: Color,_width: float) -> void:pass
    func draw_line(_start: Vector2,_end: Vector2,_colour: Color,_width: float) -> void:pass
    func draw_string(_font: Font,_point: Vector2,_text: String,_alignment: int,_width: float,_size: int,_colour: Color) -> void:pass
