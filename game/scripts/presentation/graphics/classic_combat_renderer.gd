extends "res://scripts/presentation/graphics/combat_renderer.gd"

const KnightArt=preload("res://assets/classic/knight_selection/art.tres")
const Sampler=preload("res://scripts/presentation/graphics/classic_pose_sampler.gd")
const Images=preload("res://scripts/presentation/graphics/logical_image.gd")
var art: Resource
var font: Font=ThemeDB.fallback_font

func _init(pack: Resource=null) -> void:
    art=pack

func render(canvas: Object, frame: RefCounted, background: Texture2D=null, hold_binding: String="") -> void:
    canvas.draw_texture_rect(background if background!=null else art.background_for(frame.encounter),Rect2(0,0,640,400),false)
    if not frame.perch.is_empty():
        var tree: Resource=art.animation_for("ratman")
        var leaf: Dictionary=tree.sample("tree_anchor",0)
        var point:=Vector2(frame.perch.x,frame.perch.y+frame.perch.height)
        draw_pose(canvas,tree,leaf,"purple",frame.gore,frame.colour,point)
    for actor in frame.actors:
        if actor.kind=="dragon":draw_feet(canvas,frame,actor)
        if actor.kind=="guardian" and actor.alive:
            var body: Resource=art.animation_for("guardian_finishes")
            var pose: Dictionary=body.sample("body",frame.tick%24,24)
            canvas.draw_set_transform((actor.ground+Vector2(0,actor.height))*2,0.0,Vector2(actor.facing,1))
            draw_pose(canvas,body,pose,"purple",frame.gore,frame.colour)
            canvas.draw_set_transform(Vector2.ZERO)
    for actor in frame.actors:
        if not actor.visible:continue
        var ground: Vector2=actor.ground*2
        var point: Vector2=ground+Vector2(0,actor.height*2)
        var size: Vector2=art.size_for(actor.kind)*2
        var animation: Resource=art.animation_for(actor.family)
        var pose: Dictionary={} if animation==null else Sampler.sample(animation,actor.motion,art.attack_returns.get(actor.kind,{}))
        canvas.draw_set_transform(ground,0.0,Vector2(1.0,0.28))
        canvas.draw_circle(Vector2.ZERO,38.0 if actor.kind=="balok" else 21.0,Color(0,0,0,0.35))
        canvas.draw_set_transform(Vector2.ZERO)
        if actor.alive or not pose.is_empty():
            canvas.draw_set_transform(point,0.0,Vector2(float(actor.facing),1.0))
            var tint:=Color(1.6,1.2,1.2) if actor.flash else Color.WHITE
            if not pose.is_empty():
                draw_pose(canvas,animation,pose,actor.appearance.variant,frame.gore,actor.appearance.colour,Vector2.ZERO,2.0,tint)
            else:
                canvas.draw_texture_rect(art.texture_for(actor.kind),Rect2(-size.x/2,-size.y,size.x,size.y),false,tint)
            if actor.guarding and pose.is_empty():canvas.draw_arc(Vector2(15,-48),28,-PI/2,PI/2,16,Color(0.5,0.8,1),2.0)
            canvas.draw_set_transform(Vector2.ZERO)
        else:canvas.draw_line(point+Vector2(-20,0),point+Vector2(20,0),Color(0.7,0.25,0.2),3)
        if actor.alive and not actor.hold_hint.is_empty():
            var hint: String=actor.hold_hint
            if not hold_binding.is_empty() and "HELD:" in hint:hint="HELD: "+hold_binding+" + Down"
            canvas.draw_string(font,point+Vector2(-20,15),hint,HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color(0.55,0.78,0.9) if actor.team==1 else Color(0.9,0.46,0.38))
    if frame.gore:
        for effect in frame.effects:
            var animation: Resource=art.effects.get(effect.kind)
            if animation==null:continue
            var pose: Dictionary=animation.sample("burst",effect.elapsed,effect.duration)
            canvas.draw_set_transform(effect.point*2,0.0,Vector2(effect.facing,1))
            draw_pose(canvas,animation,pose,"gore",true,0)
            canvas.draw_set_transform(Vector2.ZERO)
    for projectile in frame.projectiles:
        if projectile.kind=="dragon_fire":
            var animation: Resource=art.animation_for("dragon")
            var pose: Dictionary=animation.sample("ground_fire",projectile.age,144)
            draw_pose(canvas,animation,pose,"purple",frame.gore,frame.colour,projectile.ground)
        else:
            var texture: Texture2D=art.projectiles.get("dagger")
            if texture==null:continue
            var size: Vector2=Images.size(texture)
            canvas.draw_set_transform((projectile.ground+Vector2(0,projectile.height))*2,0.0,Vector2(float(projectile.facing),1))
            canvas.draw_texture_rect(texture,Rect2(-size,size*2),false)
            canvas.draw_set_transform(Vector2.ZERO)

func atlas(animation: Resource, variant: String, gore: bool, colour: int) -> Texture2D:
    return KnightArt.coloured(animation.atlas_for(variant if gore else variant+"_clean"),colour)

func draw_pose(canvas: Object, animation: Resource, pose: Dictionary, variant: String,
        gore: bool, colour: int, point: Vector2=Vector2.ZERO, scale: float=2.0,
        tint: Color=Color.WHITE) -> void:
    if animation.layers==null:
        canvas.draw_texture_rect_region(atlas(animation,variant,gore,colour),Rect2((point+pose.offset)*scale,pose.logical_size*scale),pose.region,tint)
        return
    var selected: String=variant if gore else variant+"_clean"
    var appearance: Dictionary=animation.layer_variants.get(selected,animation.layer_variants.get(animation.default_variant,{}))
    var identity: int=colour if appearance.get("colour",-1)<0 else int(appearance.colour)
    for piece in animation.layers.pieces(pose.index,appearance.get("gore",gore)):
        var texture: Texture2D=animation.layers.pages[piece.page]
        var paint: Color=animation.layers.colour(piece.slot,identity)*tint
        canvas.draw_texture_rect_region(texture,Rect2((point+pose.offset+piece.offset)*scale,piece.size*scale),piece.region,paint)

func draw_feet(canvas: Object, frame: RefCounted, actor: Dictionary) -> void:
    var animation: Resource=art.animation_for("dragon")
    var pose: Dictionary=Sampler.sample(animation,actor.feet)
    for depth in [-20,10]:
        draw_pose(canvas,animation,pose,"purple",frame.gore,frame.colour,Vector2(5,actor.ground.y+depth))

static func pose_rect(pose: Dictionary, point: Vector2=Vector2.ZERO) -> Rect2:
    return Rect2((point+pose.offset)*2,pose.logical_size*2)
