extends RefCounted

# Staged positions/health; real leap, rope contacts and owned escape commands.
var choice: String="rat_tree"
var mirror: bool=false
var tick: int=0
var checked: Dictionary={}
var counters: int=0
var saved: Dictionary={}
func length() -> int:return 420
func advance(session: RefCounted) -> void:
    if tick==0:
        session.start(&"competitive",&"rat_lair",{"count":1,"concurrent":1})
        var m: RefCounted=session.simulation
        m.actors[1].health=100;m.actors[1].maximum=100
        m.actors[1].x=280;m.actors[1].y=177
        m.actors[10].x=370 if mirror else -50
        m.actors[10].health=13;m.actors[10].maximum=13;m.actors[10].cooldown_remaining=0
        session.command(10,0,Vector2i.ZERO,"rat_leap",-1 if mirror else 1)
    var m: RefCounted=session.simulation
    var rat: Dictionary=m.actors[10];var knight: Dictionary=m.actors[1]
    if tick==110:checked.far=rat.rat_tree and not rat.rat_perch_near and rat.rest_height==-98
    if tick==125:knight.x=205
    if tick==150:checked.near=rat.rat_tree and rat.rat_perch_near and rat.held_target==0
    if tick==160:knight.x=160;knight.y=157
    if tick>=180 and knight.grab_remaining>0:session.command(1,1,Vector2i.DOWN,"block")
    m.advance()
    for event in m.events:
        if event.type=="damage" and event.get("move")=="rat_counter":
            counters+=1
            if rat.health>0:checked["counter"+str(counters)]=knight.hidden_by==10 and rat.held_target==1 and m.rat_perch.owner==10 and rat.special_clip=="rat_squeeze_hit"
    if tick in [110,150,175,195,225,255,280]:saved[str(tick)]=m.snapshot()
    if tick==310:checked.release=counters==3 and rat.health==0 and rat.defeat_clip=="rat_release" and rat.rest_height==-98 and knight.health==100 and knight.hidden_by==0 and knight.grab_remaining==0 and m.rat_perch.owner==0
    tick+=1
func verify(_session: RefCounted=null) -> bool:
    for key in checked:
        if not checked[key]:push_error("Ratman tree fixture failed: "+key);return false
    return checked.size()==5 and counters==3
