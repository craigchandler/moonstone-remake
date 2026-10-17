extends SceneTree

const Session = preload("res://scripts/session/local_session.gd")
const Fixture = preload("res://debug/fixtures/finisher_fixture.gd")
const Animator = preload("res://scripts/presentation/actor_animator.gd")
const Scheduler = preload("res://scripts/presentation/combat_sound_cues.gd")
const Pack = preload("res://assets/classic/audio/sounds.tres")
var rules: Resource = preload("res://content/foundation_rules.tres")
var art: Resource = preload("res://content/classic_art.tres")
var failures: int = 0

func check(ok: bool, label: String) -> void:
    if not ok:
        failures += 1
        push_error(label)

func _initialize() -> void:
    run.call_deferred()

func run() -> void:
    check(Pack.streams.size() >= 120,"complete native sound pack loads")
    for key in Pack.streams:
        var stream: AudioStreamWAV = Pack.streams[key]
        check(stream != null and stream.get_length() > 0 and stream.mix_rate == 48000,"native PCM stream: "+key)
    var guardian_count: int = 0
    var total: int = 0
    for name in ["spear","balok_a","balok_b","balok_release","troll","mud_carry","mud_quick","mud_escape","mud_interrupt","guardian_close","guardian_far","guardian_death","dragon_death","hammer_a","hammer_b"]:
        for mirror in [false,true]:
            var session: RefCounted = Session.new(rules)
            var fixture: RefCounted = Fixture.new()
            fixture.choice = name
            fixture.mirror = mirror
            var animator: RefCounted = Animator.new()
            var scheduler: RefCounted = Scheduler.new()
            var replay_scheduler: RefCounted = Scheduler.new()
            var seen: Dictionary = {}
            for tick in fixture.length():
                fixture.advance(session)
                animator.update(session.simulation.actors,rules,art)
                var before: Dictionary = session.simulation.snapshot()
                var batch: Dictionary = scheduler.collect(session.simulation,animator.poses,art,Pack)
                check(batch == replay_scheduler.collect(session.simulation,animator.poses,art,Pack),"reproducible sound choices")
                check(scheduler.collect(session.simulation,animator.poses,art,Pack).cues.is_empty(),"rendering twice cannot replay a cue")
                check(before == session.simulation.snapshot(),"audio cannot mutate rules, clocks, RNG or snapshots")
                for cue in batch.cues:
                    check(Pack.streams.has(cue.key),"every scheduled cue is a native resource")
                    seen[cue.key] = int(seen.get(cue.key,0)) + 1
                    total += 1
            check(not seen.is_empty(),"real contact/finish has sounds: "+name)
            if name == "guardian_death":
                check(int(seen.get("guardian_death",0)) == 1,"Guardian death sequence starts once")
                guardian_count += int(seen.get("guardian_death",0))
            check(fixture.verify(session),"audio keeps real finishing outcome: "+name)
    # A new attack using the same first pose must retrigger once. No attack or
    # death event is replayed just because the renderer runs again at that tick.
    var session: RefCounted = Session.new(rules)
    session.start(&"competitive",&"duel")
    var animator: RefCounted = Animator.new()
    var scheduler: RefCounted = Scheduler.new()
    var actor: Dictionary = session.simulation.actors[1]
    for attack in 2:
        actor.action = "swing"
        actor.remaining = rules.moves.swing.windup + rules.moves.swing.active + rules.moves.swing.recovery
        session.simulation.tick += 1
        session.simulation.events.clear()
        session.simulation.events.append({"type":"attack","actor":1,"move":"swing"})
        animator.update(session.simulation.actors,rules,art)
        check(scheduler.collect(session.simulation,animator.poses,art,Pack).cues.size() == 1,"same-pose new sword attack starts one cue")
    scheduler.reset()
    check(scheduler.last_tick == -1 and scheduler.history.is_empty(),"restart clears only presentation history")
    var audio: Node = root.get_node_or_null("MoonstoneAudio")
    check(audio != null,"audio service is available in a real scene tree")
    if audio != null:
        audio.enabled = false
        var before: Dictionary = session.simulation.snapshot()
        audio.play_cue("guardian_death","test",1)
        audio.muted = true
        audio.play_cue("guardian_death","test",1)
        check(before == session.simulation.snapshot(),"mute/disabled audio cannot affect battle")
        check(audio.players.size() == 8,"bounded playback voices")
    if failures == 0: print("PASS: native audio, 30 finishing replays, cue deduplication, Guardian scream once, restart and mute isolation; cues=",total," guardian=",guardian_count)
    quit(0 if failures == 0 else 1)
