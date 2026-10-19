extends RefCounted

const Images=preload("res://scripts/presentation/graphics/logical_image.gd")
const KnightArt=preload("res://assets/classic/knight_selection/art.tres")
const Places=preload("res://scripts/domain/town_locations.gd")
const Scenes=preload("res://assets/classic/town_locations/art.tres")
var art: Resource=preload("res://assets/classic/world/art.tres")
var journey: RefCounted
var kind: String
var _phase: String="greeting"
var phase: String:
    get:return journey.places.visit.get("phase",_phase) if journey!=null else _phase
    set(value):
        _phase=value
        if journey!=null and not journey.places.visit.is_empty():journey.places.visit.phase=value
var donation: int:
    get:return int(journey.places.visit.get("donation",0)) if journey!=null else 0
    set(value):
        if journey!=null and not journey.places.visit.is_empty():journey.places.visit.donation=value
var bet: int=1
var reply: String=""
var last_phase: String=""
var started: bool=false
func _init(service: String) -> void:
    kind=service
    if kind=="tavern":_phase="tavern"
func rows() -> Array[String]:
    if phase=="donation":return ["minus","plus","accept","exit"]
    if phase=="tavern":return ["bet_1","bet_2","bet_3","bet_4","bet_5","exit"]
    return ["continue","exit"]
func row_rect(index: int) -> Rect2:
    if phase=="donation":return [Rect2(288,338,28,16),Rect2(324,338,28,16),Rect2(262,370,40,16),Rect2(346,370,64,16)][index]
    if phase=="tavern":return Rect2(536,[76,132,188,242,294][index],86,48) if index<5 else Rect2(536,362,90,32)
    return Rect2(0,320,640,80) if index==0 else Rect2()
func sync_audio(host: Node) -> void:
    if journey==null or journey.places.visit.is_empty():return
    var audio: Node=host.get_node_or_null("/root/MoonstoneAudio")
    if not started:
        started=true
        if audio!=null and phase in ["greeting","tavern"]:
            var sequences: Array=range(125,128) if kind=="tavern" else range(116,120) if kind=="mystic" else range(121,125)
            for seq in sequences:audio.play_cue("town_%03d"%seq,"town:"+kind+":greeting",0)
    if phase!=last_phase:
        if audio!=null and phase=="rolling":audio.stop_scope("town:"+kind+":",false)
        last_phase=phase
func advance(host: Node) -> void:
    if journey==null or journey.places.visit.is_empty() or host.help_visible:return
    sync_audio(host)
    var v: Dictionary=journey.places.visit
    v.tick=mini(1000000,int(v.tick)+1)
    if phase=="rolling":
        for cue in Scenes.data.dice_roll_cues:
            if int(cue.tick)==int(v.tick) and posmod(int(v.tick)+int(v.bet)*17,100)<50:
                var audio: Node=host.get_node_or_null("/root/MoonstoneAudio")
                if audio!=null:audio.play_cue("town_153","town:tavern:roll",v.tick)
        if int(v.tick)>=int(Scenes.data.dice_roll_ticks):v.phase="dice";v.tick=0;journey.persist()
    host.queue_redraw()
func adjust(amount: int,host: Node) -> void:
    donation=clampi(donation+amount,0,journey.inventory.gold);journey.persist();host.queue_redraw()
func accept(host: Node) -> void:
    if Places.donate(journey,donation):host.selected=0
    host.queue_redraw()
func activate(host: Node) -> void:
    if phase=="greeting":phase="donation";journey.persist()
    elif phase=="reply":host.finished.emit();return
    elif phase=="donation":accept(host)
    elif phase=="dice":phase="tavern";journey.persist()
    elif phase=="tavern":
        bet=clampi(host.selected+1,1,5)
        if not Places.wager(journey,bet):journey.message="You cannot afford that wager."
    host.selected=0;host.queue_redraw()
func back(host: Node) -> void:
    if phase=="rolling":return
    host.finished.emit()
func key(event: InputEventKey,host: Node) -> void:
    if host.help_visible:host.help_visible=false;host.queue_redraw();return
    host.mouse_active=false
    if event.keycode in [KEY_ESCAPE,KEY_I]:back(host)
    elif event.keycode==KEY_F1:host.help_visible=true
    elif event.keycode in [KEY_ENTER,KEY_KP_ENTER,KEY_SPACE,KEY_Z]:
        if phase=="tavern" and host.selected==5:back(host)
        else:activate(host)
    elif phase=="donation":
        if event.keycode in [KEY_LEFT,KEY_DOWN,KEY_MINUS,KEY_KP_SUBTRACT]:adjust(-1,host)
        elif event.keycode in [KEY_RIGHT,KEY_UP,KEY_PLUS,KEY_EQUAL,KEY_KP_ADD]:adjust(1,host)
        elif event.keycode in [KEY_1,KEY_2]:donation=mini(journey.inventory.gold,10 if event.keycode==KEY_1 else 15);journey.persist()
    elif phase=="tavern" and event.keycode in [KEY_UP,KEY_DOWN]:host.selected=posmod(host.selected+(1 if event.keycode==KEY_DOWN else -1),6)
    host.queue_redraw()
func input(event: InputEvent,host: Node) -> void:
    if event is InputEventMouseMotion:host.mouse_active=true;host.pointer=event.position;host.queue_redraw();return
    if not event is InputEventMouseButton or not event.pressed or event.button_index!=MOUSE_BUTTON_LEFT:return
    host.get_viewport().set_input_as_handled();host.mouse_active=true;host.pointer=event.position
    if host.help_visible:host.help_visible=false
    elif phase in ["greeting","reply","dice"]:activate(host)
    elif phase!="rolling":
        for index in range(rows().size()):
            if not row_rect(index).has_point(event.position):continue
            var action: String=rows()[index]
            if action=="exit":back(host)
            elif action=="minus":adjust(-1,host)
            elif action=="plus":adjust(1,host)
            elif action=="accept":accept(host)
            else:host.selected=index;activate(host)
            break
    host.queue_redraw()
func sprite(host: Node,index: int,point: Vector2) -> void:
    var texture: Texture2D=art.service_sprites[kind+"_"+str(index)]
    host.draw_texture_rect(texture,Rect2(point*2,Images.size(texture)*2),false)
func draw_track(host: Node,key: String,tick: int) -> void:
    var poses: Array=Scenes.data[key];var total: int=0
    for pose in poses:total+=int(pose.ticks)
    var remaining: int=clampi(tick,0,total-1) if key=="dice_roll" else posmod(tick,total)
    for pose in poses:
        if remaining<int(pose.ticks):
            for layer in pose.layers:
                var texture: Texture2D=KnightArt.coloured(Scenes.frames["dice_"+str(layer.frame)],journey.identity.kind)
                host.draw_texture_rect(texture,Rect2(Vector2(layer.x,layer.y)*2,Images.size(texture)*2),false)
            return
        remaining-=int(pose.ticks)
func draw(host: Node) -> void:
    var v: Dictionary=journey.places.visit
    if v.is_empty():return
    host.draw_texture_rect(KnightArt.coloured(art.service_pictures["dice" if phase=="dice" else kind],journey.identity.kind),Rect2(0,0,640,400),false)
    if phase=="greeting":
        for line in art.service_dialogue[kind]:host.pixel_text(line.text,Vector2(320,line.y*2),true)
    elif phase=="donation":
        var portrait: int=1 if kind=="healer" else 0
        sprite(host,portrait,Vector2(2,162));sprite(host,portrait,Vector2(270,162))
        for d in [[2,173,185],[3,131,185],[4,144,169],[5,162,169]]:sprite(host,d[0],Vector2(d[1],d[2]))
        host.pixel_text("Your Gold",Vector2(4,380));host.pixel_text("Donation",Vector2(524,380))
        host.pixel_text(str(journey.inventory.gold-donation),Vector2(40,350));host.pixel_text(str(donation),Vector2(576,350))
    elif phase=="reply":
        var text: String={"none":"NO GOLD WAS OFFERED.","tiny":"YOUR OFFER WAS TOO SMALL.","plain":"YOUR OFFER IS ACCEPTED.","healed":"YOUR WOUNDS AND LIVES ARE RESTORED.","unchanged":"YOUR ABILITIES REMAIN UNCHANGED.","raise":"YOUR "+String(v.subject).to_upper()+" IS INCREASED.","lower":"YOUR "+String(v.subject).to_upper()+" IS DECREASED."}.get(v.result,"")
        host.pixel_text(text,Vector2(320,342),true)
        host.pixel_text("%d GOLD OFFERED"%v.amount,Vector2(320,362),true)
    elif phase in ["tavern","rolling"]:
        host.draw_texture_rect(KnightArt.coloured(Scenes.pictures.tavern,journey.identity.kind),Rect2(0,0,640,400),false)
        draw_track(host,"dice_roll" if phase=="rolling" else "dice_idle",v.tick)
        host.pixel_text(str(journey.inventory.gold),Vector2(564,28))
    elif phase=="dice":
        var dice: Array=v.dice if v.dice.size()==3 else [1,3,5]
        for i in range(3):
            var texture: Texture2D=art.service_sprites["dice_"+str(dice[i])]
            host.draw_texture_rect(texture,Rect2([Vector2(230,30),Vector2(98,76),Vector2(150,176)][i],Images.size(texture)*2),false)
        var lines: Array=[("You won %d gold pieces."%v.payout) if v.payout>0 else ("You lost %d gold pieces."%v.bet),"You now have %d gold pieces."%journey.inventory.gold,"Press fire to continue"]
        for i in range(lines.size()):host.pixel_text(lines[i],Vector2(348,252+i*28),false,Color("553322"))
    host.draw_help("ARROWS OR + / -: CHANGE OFFER\nSPACE / ENTER: CONTINUE OR ACCEPT\nCANCEL KEEPS UNCONFIRMED GOLD\nAN ACCEPTED DONATION IS SPENT\nTAVERN: CHOOSE A 1 TO 5 GOLD WAGER\nESC / I: RETURN TO TOWN")
    if phase!="rolling":host.draw_pointer(row_rect(clampi(host.selected,0,rows().size()-1)).get_center())
