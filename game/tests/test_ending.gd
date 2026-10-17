extends SceneTree
const Journey=preload("res://scripts/session/journey_session.gd")
const Quest=preload("res://scripts/domain/moonstone_quest.gd")
const ART=preload("res://assets/classic/ending_complete/art.tres")
var failures: int=0
var definition: Resource=preload("res://content/first_journey.tres")
var rules: Resource=preload("res://content/foundation_rules.tres")
func check(ok: bool,label: String) -> void:
    if not ok:failures+=1;push_error(label)
func fresh() -> RefCounted:return Journey.new(definition,rules,0x4d4f4f4e)
func clone(j: RefCounted) -> RefCounted:
    var copy: RefCounted=fresh()
    check(copy.restore_checkpoint(JSON.parse_string(JSON.stringify(j.checkpoint()))),"film serialized Continue accepted")
    check(copy.checkpoint()==j.checkpoint(),"film serialized Continue exact")
    return copy
func _initialize() -> void:run.call_deferred()
func run() -> void:
    check(ART.total_ticks==Quest.ENDING_TICKS and ART.music_tick==36 and ART.moon_tick==460,"bounded opening matches imported source schedule")
    check(ART.music is AudioStreamWAV and absf(ART.music.get_length()-81.52)<0.001,"native stereo music segment resolves")
    var last: int=0
    for pose in ART.runs:
        check(pose.start==last and pose.ticks>0 and pose.frame>=0 and pose.frame<ART.frames,"finite contiguous native timeline")
        last+=pose.ticks
    check(last==ART.total_ticks and ART.frames==244 and ART.palettes.size()==12,"all four scene groups and twelve winner/phase variants")
    var j: RefCounted=fresh()
    j.quest.stones=1;j.day=17;j.world.position=j.Henge.POSITION
    check(j.enter_henge(),"matching phase visit")
    for tick in range(20):j.tick_quest()
    var pending: Dictionary=j.checkpoint()
    pending.schema=9;pending.content="journey.campaign.v7"
    var old: RefCounted=fresh()
    check(old.restore_checkpoint(pending) and old.quest.ending.stage=="message" and old.quest.ending.tick==20,"old unconfirmed prompt remains unconfirmed")
    var handoff: Dictionary=pending.duplicate(true)
    handoff.quest.ending.stage="ready"
    check(old.restore_checkpoint(handoff) and old.quest.ending.stage=="ready" and old.quest.ending.tick==0,"old ready handoff begins the film once at zero")
    check(j.enter_ending() and j.quest.ending.tick==0,"confirmed quest starts native clock")
    var before: Dictionary=j.checkpoint()
    j=clone(j)
    var audio: Node=root.get_node("MoonstoneAudio")
    audio.trace_enabled=true;audio.trace_path="user://ending-test-audio.json";audio.played.clear()
    audio.stop_music()
    for tick in range(Quest.ENDING_TICKS):
        audio.ending_music(j.quest.ending.tick)
        j.tick_ending()
        if tick in [34,35,130,289,423,459,699,938,939,1665,2169,2405,2525,2637,2940,3246,3878,3968,4060]:j=clone(j)
    check(j.quest.ending.stage=="complete" and j.quest.ending.tick==Quest.ENDING_TICKS,"automatic finite completion")
    check(audio.played.size()==1 and audio.played[0].key=="ending_music" and audio.played[0].tick==36,"one onset; no restart through flash/fade/ascent")
    var done: Dictionary=j.checkpoint()
    j.tick_ending();check(not j.finish_ending() and j.checkpoint()==done,"completion is idempotent")
    j=clone(j)
    check(not j.travel(Vector2i.RIGHT) and not j.rest() and j.checkpoint()==done,"ending never reopens map progress")
    for setting in ["muted","enabled"]:
        j=fresh();check(j.restore_checkpoint(before),"repeat fixture")
        audio.stop_music();audio.set(setting,setting=="muted")
        for tick in range(Quest.ENDING_TICKS):audio.ending_music(j.quest.ending.tick);j.tick_ending()
        check(j.checkpoint()==done,"audio options cannot change ending state")
    audio.muted=false;audio.enabled=true;audio.stop_music()
    audio.ending_music(700)
    check(audio.played[-1].tick==700 and absf(audio.played[-1].offset-13.28)<0.001,"new presentation owner seeks saved PCM position")
    audio.stop_music();audio.trace_enabled=false
    j=fresh();j.restore_checkpoint(before)
    for tick in range(290):j.tick_ending()
    check(j.finish_ending() and j.checkpoint()==done,"skip settles same state without changing loot/stats/phase")
    for patch in [{"stage":"ready","tick":Quest.ENDING_TICKS},{"stage":"message","tick":21},{"stage":"complete","tick":Quest.ENDING_TICKS-1},{"tick":-1},{"tick":1.5},{"stage":"unknown"}]:
        var bad: Dictionary=done.duplicate(true);bad.quest.ending.merge(patch,true)
        check(not j.restore_checkpoint(bad) and j.checkpoint()==done,"invalid cinematic clock rejects atomically")
    # Old v12 completed endings stay completed; unfinished0036 clocks survive.
    for prior_tick in [0,36,131,700,939]:
        var previous: Dictionary=before.duplicate(true)
        previous.schema=14;previous.content="journey.campaign.v12";previous.quest.ending.tick=prior_tick
        old=fresh()
        check(old.restore_checkpoint(previous) and old.quest.ending.tick==prior_tick,"v12 film retains exact opening clock")
        var expected: Dictionary=previous.duplicate(true);expected.schema=16;expected.content="journey.campaign.v14"
        check(old.checkpoint()==expected,"migration changes only version metadata")
    var complete: Dictionary=done.duplicate(true);complete.schema=14;complete.content="journey.campaign.v12";complete.quest.ending.tick=940
    old=fresh();check(old.restore_checkpoint(complete) and old.checkpoint()==done,"old completed film stays completed, no reward replay")
    complete.quest.ending.tick=941
    check(not old.restore_checkpoint(complete) and old.checkpoint()==done,"malformed old completed clock rejects atomically")
    old=fresh();handoff.quest.ending.tick=21
    check(not old.restore_checkpoint(handoff),"invalid previous handoff cannot silently migrate")
    if failures==0:print("PASS: complete ending timeline,12 palettes, single native music onset/seek, immutable rewards, exact mid-film Continue, legacy handoff migration, audio isolation, idempotent skip/completion and atomic invalid-clock rejection")
    quit(1 if failures else 0)
