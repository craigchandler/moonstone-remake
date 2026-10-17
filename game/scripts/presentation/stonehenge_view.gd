extends "res://scripts/presentation/original_panel_view.gd"

signal finished
const KnightArt=preload("res://assets/classic/knight_selection/art.tres")
var journey: RefCounted
var scene_art: Resource=preload("res://assets/classic/stonehenge/art.tres")
var message_picture: Texture2D=preload("res://assets/classic/recovered/A/message.piv/image.png")
var selected: int=0
var page: int=0
var last_phase: String=""
var last_audio_tick: int=-1
var audio: Node

func _ready() -> void:
    super._ready()
    audio=get_node_or_null("/root/MoonstoneAudio")
    sync_audio()

func _exit_tree() -> void:
    if is_instance_valid(audio): audio.stop_scope("stonehenge:",false)
    super._exit_tree()

func phase() -> String:
    return String(journey.henge.get("phase",""))

func rows() -> Array:
    if phase()=="temple": return ["strength","constitution","endurance"]
    var result: Array=[]
    for id in journey.loot_rules.items:
        if int(journey.inventory.items.get(id,0))>0: result.append(id)
    return result

func slots() -> Array[Dictionary]:
    # Keys and ordinary equipment are visible belongings, never valid offerings.
    return pack_slots(journey.inventory.items,journey.owned_keys,74,page,journey.quest.stones)

func row_rect(index: int) -> Rect2:
    if index<0 or index>=rows().size(): return Rect2()
    if phase()=="temple": return Rect2(230,70+index*14,80,14)
    for slot in slots():
        if slot.id==rows()[index]:return slot.rect
    return Rect2()

func activate() -> void:
    if phase()=="greeting": journey.advance_henge()
    elif phase()=="offering" and not rows().is_empty():
        selected=clampi(selected,0,rows().size()-1)
        if journey.offer_henge_item(rows()[selected]):
            if audio!=null:
                for cue in audio.Pack.cues.loot_click: audio.play_cue(cue,"ui:stonehenge-offer")
    elif phase()=="temple": journey.upgrade_stat(rows()[clampi(selected,0,2)])
    selected=clampi(selected,0,maxi(0,rows().size()-1))
    sync_audio()
    queue_redraw()

func back() -> void:
    if phase()=="greeting": journey.advance_henge()
    elif phase()=="offering": journey.leave_henge_offering()
    elif phase() in ["prelude","ritual"]: journey.complete_henge()
    elif phase()=="temple":
        if journey.leave_henge(): finished.emit()
    selected=0
    sync_audio()
    queue_redraw()

func advance() -> void:
    # Sound is presentation only; muting never changes this saved phase clock.
    journey.tick_henge()
    sync_audio()
    queue_redraw()

func sync_audio() -> void:
    if audio==null: return
    if phase()!=last_phase:
        last_audio_tick=-1
        audio.stop_scope("stonehenge:",false)
        if phase()=="ritual" and journey.henge.tick==0:
            for cue in audio.Pack.cues.ritual_open: audio.play_cue(cue,"stonehenge:ritual",0)
        last_phase=phase()
    if phase()!="ritual" or last_audio_tick==int(journey.henge.tick): return
    last_audio_tick=int(journey.henge.tick)
    for entry in scene_art.cues:
        if int(entry.tick)!=int(journey.henge.tick): continue
        # Stable local presentation choice, independent of campaign RNG/save data.
        if entry.optional and posmod(String(journey.henge.offered).hash()+int(entry.pose)*37,100)>=50: continue
        for cue in audio.Pack.cues.ritual_chant: audio.play_cue(cue,"stonehenge:ritual",journey.henge.tick)

func _unhandled_key_input(event: InputEvent) -> void:
    if not event is InputEventKey or not event.pressed or event.echo: return
    get_viewport().set_input_as_handled()
    if event.keycode==KEY_F1: help_visible=not help_visible;queue_redraw();return
    if help_visible: help_visible=false;queue_redraw();return
    mouse_active=false
    if event.keycode in [KEY_ESCAPE,KEY_I]: back()
    elif event.keycode in [KEY_ENTER,KEY_KP_ENTER,KEY_SPACE,KEY_Z]: activate()
    elif event.keycode in [KEY_UP,KEY_DOWN]:
        selected=posmod(selected+(1 if event.keycode==KEY_DOWN else -1),maxi(1,rows().size()))
        if phase()=="offering":page=0
    elif event.keycode in [KEY_PAGEUP,KEY_PAGEDOWN]: page=posmod(page+(1 if event.keycode==KEY_PAGEDOWN else -1),pack_pages(journey.inventory.items))
    queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion:
        mouse_active=true;pointer=event.position;queue_redraw();return
    if not event is InputEventMouseButton or not event.pressed or event.button_index!=MOUSE_BUTTON_LEFT: return
    get_viewport().set_input_as_handled()
    mouse_active=true;pointer=event.position
    if help_visible: help_visible=false
    elif phase()=="greeting":activate()
    elif phase() in ["offering","temple"]:
        if on_column(pointer,true): back();return
        if phase()=="offering" and Rect2(502,268,134,18).has_point(pointer):
            page=posmod(page+1,pack_pages(journey.inventory.items));queue_redraw();return
        for index in range(rows().size()):
            if row_rect(index).has_point(pointer): selected=index;activate();break
    queue_redraw()

func pose_at(track: Array, tick: int, loop: bool) -> Dictionary:
    var total: int=0
    for pose in track:total+=int(pose.ticks)
    var remaining: int=posmod(tick,total) if loop else clampi(tick,0,total-1)
    for pose in track:
        if remaining<int(pose.ticks):return pose
        remaining-=int(pose.ticks)
    return track.back()

func draw_track(track: Array, tick: int, loop: bool) -> void:
    for layer in pose_at(track,tick,loop).layers:
        var texture: Texture2D=KnightArt.coloured(scene_art.frames[int(layer.frame)],journey.identity.kind)
        draw_texture_rect(texture,Rect2(Vector2(layer.x,layer.y)*2,texture.get_size()*2),false)

func _draw() -> void:
    if journey==null or journey.henge.is_empty():return
    if phase() in ["greeting","prelude"]:
        draw_texture_rect(message_picture,Rect2(0,0,640,400),false)
        for line in (scene_art.greeting if phase()=="greeting" else scene_art.prelude):pixel_text(line.text,Vector2(320,line.y*2),true)
    elif phase()=="ritual":
        draw_texture_rect(KnightArt.coloured(scene_art.background,journey.identity.kind),Rect2(0,0,640,400),false)
        draw_track(scene_art.druids,journey.henge.tick,true)
        draw_track(scene_art.knight,journey.henge.tick,false)
    else:
        draw_texture_rect(art.single_background,Rect2(0,0,640,400),false)
        draw_sheet(journey,74)
        draw_slots(slots())
        var caption: String="OFFER A MAGIC ITEM" if phase()=="offering" else "HIGH TEMPLE"
        selected=clampi(selected,0,maxi(0,rows().size()-1))
        if not rows().is_empty():
            var id: String=rows()[selected]
            caption="OFFER "+String(journey.loot_rules.items[id].name) if phase()=="offering" else "IMPROVE %s - %d XP" % [id,journey.upgrade_cost()]
        if mouse_active:
            caption="EXIT" if on_column(pointer,true) else ""
            for i in range(rows().size()):
                if row_rect(i).has_point(pointer):caption="OFFER "+String(journey.loot_rules.items[rows()[i]].name) if phase()=="offering" else "IMPROVE %s - %d XP" % [rows()[i],journey.upgrade_cost()]
        draw_caption(caption)
        if phase()=="temple" and not journey.message.is_empty():pixel_text(journey.message.left(56),Vector2(320,14),true,Color("ddc68c"))
        if phase()=="offering" and pack_pages(journey.inventory.items)>1:pixel_text("PACK %d/%d >" % [page+1,pack_pages(journey.inventory.items)],Vector2(502,268))
        var fallback:=Vector2(444,240)
        if not rows().is_empty():fallback=row_rect(selected).get_center()
        draw_pointer(fallback)
    draw_help("STONEHENGE\nCLICK A MAGIC ITEM / SPACE: OFFER ONE\nARROWS: SELECT / PGUP-PGDN: PACK PAGES\nCOLUMNS / ESC / I: LEAVE THE PANEL\nESC DURING RITUAL: SKIP TO BLESSING\nTEMPLE STATS COST XP AS IN HIGHWOOD\nLEAVING THE TEMPLE SPENDS THIS TURN")
