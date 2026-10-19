extends SceneTree

const Images=preload("res://scripts/presentation/graphics/logical_image.gd")
const Frame=preload("res://scripts/presentation/graphics/combat_frame.gd")
const Animator=preload("res://scripts/presentation/actor_animator.gd")
const Session=preload("res://scripts/session/local_session.gd")
const Effects=preload("res://scripts/presentation/combat_hit_effects.gd")
const Rules=preload("res://content/foundation_rules.tres")
const Art=preload("res://content/classic_art.tres")
var failures: int=0

func check(ok: bool, label: String) -> void:
    if not ok:failures+=1;push_error(label)

func _initialize() -> void:run.call_deferred()

func run() -> void:
    var panel: Node=preload("res://scripts/presentation/original_panel_view.gd").new()
    var map: Node=preload("res://scenes/main.tscn").instantiate()
    var original: Texture2D=panel.art.icon_for("healing_potion")
    var logical: Vector2=Images.size(original)
    var before: Rect2=panel.icon_region("healing_potion",Vector2(31,165))
    var slots: Array[Dictionary]=panel.pack_slots({"healing_potion":4,"scroll_of_protection":3},15,0)
    var pixels:=Image.create(int(logical.x*4),int(logical.y*4),false,Image.FORMAT_RGBA8)
    var enlarged:=ImageTexture.create_from_image(pixels)
    enlarged.take_over_path(original.resource_path)
    panel.art=panel.art.duplicate()
    panel.art.icons=panel.art.icons.duplicate();panel.art.icons.healing_potion=enlarged
    check(Images.size(enlarged)==logical,"replacement pixels do not define logical size")
    check(panel.icon_region("healing_potion",Vector2(31,165))==before,"4x icon retains drawing and click bounds")
    check(panel.pack_slots({"healing_potion":4,"scroll_of_protection":3},15,0)==slots,"inventory slot geometry remains identical")
    check(Images.source_rect(enlarged,Rect2(Vector2.ONE,logical/2))==Rect2(Vector2(4,4),logical*2),"source cropping scales independently of layout")
    var marker: Texture2D=preload("res://assets/classic/knight_selection/art.tres").tokens[0]
    check(map.icon_rect(Vector2i(50,60),marker).size==Images.size(marker)*map.map_rect.size/Vector2(320,200),"map picking uses the same logical icon dimensions")
    var animation: Resource=Art.animation_for("knight").duplicate()
    var classic: Dictionary=animation.sample("heavy",5,20,"active")
    animation.atlas_scale=Vector2(4,4)
    var hd: Dictionary=animation.sample("heavy",5,20,"active")
    check(classic.offset==hd.offset and classic.logical_size==hd.logical_size and classic.index==hd.index,"larger atlas retains feet, size and phase")
    check(hd.region==Rect2(classic.region.position*4,classic.region.size*4),"atlas source coordinates scale without changing clocks")
    var session: RefCounted=Session.new(Rules);session.start(&"competitive",&"duel")
    var animator: RefCounted=Animator.new();animator.update(session.simulation.actors,Rules,Art)
    var frame: RefCounted=Frame.new()
    var equipment: Dictionary={1:{"weapon":"sword_of_sharpness","armour":"battleplate"}}
    var snapshot: Dictionary=session.simulation.snapshot()
    frame.capture(session.simulation,animator,Effects.new(),Rules,&"duel",false,3,{10:1},equipment)
    check(frame.actors[0].appearance.weapon=="sword_of_sharpness" and frame.actors[0].appearance.armour=="battleplate","renderer receives effective equipment IDs")
    check(not frame.gore and frame.actors[0].appearance.colour==3,"colour and gore are presentation inputs")
    check(values_only(frame.actors) and values_only(frame.projectiles) and values_only(frame.effects),"renderer frame contains no objects, resources or live models")
    frame.actors[0].ground=Vector2(-100,-100);frame.actors[0].motion.clip="changed";frame.actors[0].appearance.weapon="changed"
    check(snapshot==session.simulation.snapshot() and animator.motions[1].clip!="changed" and equipment[1].weapon=="sword_of_sharpness","renderer edits cannot mutate rules, animation history or equipment")
    frame.capture(session.simulation,animator,Effects.new(),Rules,&"duel",true,0,{},{})
    check(snapshot==session.simulation.snapshot(),"repeated presentation capture leaves deterministic state unchanged")
    panel.free();map.free()
    if failures==0:print("PASS: independent actor/equipment frames, isolation, 4x icon layout/picking/cropping and atlas foot/phase invariance")
    quit(1 if failures else 0)

func values_only(value: Variant) -> bool:
    if value is Object:return false
    if value is Dictionary:
        for key in value:
            if not values_only(value[key]):return false
    elif value is Array:
        for item in value:
            if not values_only(item):return false
    return true
