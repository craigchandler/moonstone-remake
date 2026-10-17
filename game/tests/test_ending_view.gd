extends SceneTree

const ART=preload("res://assets/classic/ending_complete/art.tres")
var failures: int=0
func check(ok: bool,label: String) -> void:
    if not ok:failures+=1;push_error(label)
func _initialize() -> void:run.call_deferred()
func run() -> void:
    var host: Node=load("res://scenes/main.tscn").instantiate()
    host.saving_enabled=false
    host.definition=host.definition.duplicate();host.definition.rival_turns=false
    root.add_child(host);host.set_physics_process(false)
    await process_frame
    var j: RefCounted=host.journey
    j.quest.stones=1;j.day=17;j.world.position=j.Henge.POSITION
    check(j.enter_henge(),"real matching-phase victory entry")
    host.show_quest()
    var view: Node=host.quest_view
    for i in range(20):view.advance()
    view.activate()
    var initial: Dictionary=j.checkpoint()
    var audio: Node=root.get_node("MoonstoneAudio")
    audio.stop_music();audio.played.clear();audio.trace_enabled=true;audio.trace_path="user://ending-view-audio.json"
    for section in ART.sections:
        while j.quest.ending.tick<section.start:view.advance()
        check(host.quest_view==view and host.menu_view==null,"no early menu at "+section.id)
        check(view.ending_view.shown_frame==ART.pose_at(section.start).frame,"actual displayed scene at "+section.id)
        check(view.ending_view.palette.get_shader_parameter("row")==section.start,"authoritative palette clock at "+section.id)
        var clone: RefCounted=host.Journey.new(host.definition,host.rules,2)
        check(clone.restore_checkpoint(JSON.parse_string(JSON.stringify(j.checkpoint()))),"Continue at "+section.id)
        check(clone.checkpoint()==j.checkpoint(),"unchanged state at "+section.id)
    while j.quest.ending.stage=="ready":view.advance()
    check(host.quest_view==null and host.menu_view!=null,"automatic final-frame menu return")
    var music: Array=audio.played.filter(func(row: Dictionary) -> bool:return row.key=="ending_music")
    check(music.size()==1 and music[0].tick==36,"continuous ending music through all scenes")
    check(audio.music_owner=="menu","ending owner hands music to menu")
    var done: Dictionary=j.checkpoint()
    var unchanged: Dictionary=done.duplicate(true);unchanged.quest.ending=initial.quest.ending
    check(unchanged==initial,"ending cannot change equipment, loot, stats, RNG or day")
    host.menu_choice("continue")
    check(host.quest_view!=null and host.menu_view==null and j.checkpoint()==done,"completed Continue shows final card without replay")
    check(host.quest_view.ending_view.visible and audio.music_owner=="","completed card is visible and silent")
    host.quest_view.activate()
    check(host.menu_view!=null and host.quest_view==null and j.checkpoint()==done,"completed return remains idempotent")
    audio.trace_enabled=false
    host.queue_free();await process_frame
    if failures==0:print("PASS: all ending scene boundaries, actual view/palette clock, exact Continue, continuous music, automatic menu, final card and reward isolation")
    quit(1 if failures else 0)
