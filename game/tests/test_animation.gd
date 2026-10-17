extends SceneTree

const Model = preload("res://scripts/domain/combat_simulation.gd")
const Animator = preload("res://scripts/presentation/actor_animator.gd")
var failures: int = 0

func check(condition: bool, message: String) -> void:
    if not condition:
        failures += 1
        push_error(message)

func _initialize() -> void:
    var rules: Resource = load("res://content/foundation_rules.tres")
    var art: Resource = load("res://content/classic_art.tres")
    var animations: Resource = art.animation_for("knight")
    check(animations.poses.size() == 72, "all traced knight poses should be present")
    for variant in animations.atlases:
        var atlas: Texture2D = animations.atlas_for(variant)
        var bounds := Rect2(Vector2.ZERO, atlas.get_size())
        for pose in animations.poses:
            check(bounds.encloses(pose.region), "pose must stay within its atlas")
            check(pose.offset == Vector2(-128, -128), "all poses must share the original foot anchor")
    for name in animations.clips:
        var clip: Dictionary = animations.clips[name]
        check(clip.frames.size() == clip.weights.size(), "each pose needs its hold weight")
        for index in clip.frames:
            check(index >= 0 and index < animations.poses.size(), "clip references a valid pose")
        if clip.has("phases"):
            for phase in ["windup", "active", "recovery"]:
                check(not clip.phases[phase].is_empty(), "attack phase has at least one pose")

    # Test the actual simulation boundary, not a second invented animation clock.
    var model: RefCounted = Model.new(rules)
    var animator: RefCounted = Animator.new()
    for action in ["swing", "heavy", "lunge", "reverse", "upward", "dagger"]:
        model.start(&"competitive", 2)
        model.actors[1].x = 100
        model.actors[2].x = 65 if action == "reverse" else (180 if action in ["heavy", "lunge", "dagger"] else 125)
        animator.reset()
        var initial: Dictionary = model.snapshot()
        animator.update(model.actors, rules, art)
        check(model.snapshot() == initial, "presentation must not alter game state")
        check(model.submit(1, {"actor": 1, "sequence": 1, "tick": 0, "dx": 0, "dy": 0,
            "action": action}), "attack accepted")
        model.advance()
        var saw_damage: bool = false
        var seen: Dictionary = {}
        for step in range(1 + rules.moves[action].windup + rules.moves[action].active + rules.moves[action].recovery):
            animator.update(model.actors, rules, art)
            var pose: Dictionary = animator.poses[1]
            seen[pose.index] = true
            for event in model.events:
                if event.type == "damage":
                    saw_damage = true
                    check(action == "dagger" or (pose.clip == action and pose.phase == "active"),
                        "damage tick must display the corresponding strike pose")
                if event.type == "dagger":
                    check(pose.clip == "dagger" and pose.phase == "active", "dagger release matches the throw pose")
            if model.actors[1].remaining == 0:
                check(pose.clip == "idle", "attack completion returns to idle")
                break
            model.advance()
        check(saw_damage, "attack should reach its real damage tick")
        check(seen.size() >= (4 if action == "upward" else 3),
            "contact branch displays preparation, impact and return; full paths covered by pacing suite")

    # The mechanics and artwork sample the same active pose/hold sequence.
    var geometry: Resource = rules.geometry["knight"]
    for action in rules.actor_definitions.knight.allowed_moves:
        var clip: Dictionary = animations.clips[action]
        var contacts: Array = geometry.attacks[action]
        check(clip.phases.active.size() == contacts.size(), "one contact set per active visual pose")
        for i in range(contacts.size()):
            check(contacts[i].weight == clip.weights[clip.frames.find(clip.phases.active[i])],
                "contact/visual phase weights match")

    var spear: Resource = art.animation_for("trogg_spear")
    check(spear.poses.size() == 72, "all traced spear Trogg poses should be present")
    for variant in spear.atlases:
        var bounds := Rect2(Vector2.ZERO, spear.atlas_for(variant).get_size())
        for pose in spear.poses:
            check(bounds.encloses(pose.region), "Trogg pose stays inside atlas")
            check(pose.offset == Vector2(-128, -128), "Trogg original origin shares logical foot anchor")
    check(spear.clips.spear_thrust.phases.active.size() == rules.geometry.trogg_spear.attacks.spear_thrust.size(),
        "Trogg thrust visual and contact phases agree")
    for clip_name in ["defeat", "defeat_split", "defeat_guts"]:
        model.start(&"competitive", 0, &"spear_lair")
        var actor: Dictionary = model.actors[10]
        actor.health = 0
        actor.defeat_clip = clip_name
        actor.down_remaining = rules.actor_definitions.trogg_spear.defeat_duration(clip_name)
        animator.reset()
        for step in range(actor.down_remaining + 20):
            animator.update(model.actors, rules, art)
            check(animator.poses[10].clip == clip_name, "selected Trogg death clip is shown")
            model.advance()
        check(animator.poses[10].index == spear.clips[clip_name].frames.back(), "Trogg corpse holds final pose")

    model.start(&"competitive", 2)
    animator.reset()
    animator.update(model.actors, rules, art)
    check(model.submit(1, {"actor": 1, "sequence": 1, "tick": 0, "dx": -1, "dy": 0,
        "action": "idle"}), "leftward movement accepted")
    model.advance()
    animator.update(model.actors, rules, art)
    check(animator.poses[1].clip == "walk" and model.actors[1].facing == -1,
        "walk selects a pose while facing remains authoritative")
    model.advance()
    animator.update(model.actors, rules, art)
    check(animator.poses[1].clip == "idle", "movement animation stops without movement")
    check(model.submit(1, {"actor": 1, "sequence": 2, "tick": model.tick, "dx": 0, "dy": 0,
        "action": "block"}), "guard accepted")
    model.advance()
    animator.update(model.actors, rules, art)
    check(animator.poses[1].clip == "block", "guard displays the original sword stance")
    model.actors[1].reaction = "hurt_b"
    model.actors[1].reaction_remaining = rules.actor_definitions.knight.reaction_ticks
    var before: Dictionary = model.snapshot()
    animator.update(model.actors, rules, art)
    check(animator.poses[1].clip == "hurt_b", "hit reaction takes visual priority over guard")
    check(model.snapshot() == before, "reaction rendering does not alter authoritative state")
    model.actors[1].health = 0
    model.actors[1].down_remaining = rules.actor_definitions.knight.defeat_ticks
    animator.update(model.actors, rules, art)
    var initial_fall: int = animator.poses[1].index
    for step in range(rules.actor_definitions.knight.defeat_ticks + 20):
        model.advance()
        animator.update(model.actors, rules, art)
    check(animator.poses[1].clip == "defeat" and animator.poses[1].index != initial_fall,
        "fall advances to its final corpse pose")
    check(animator.poses[1].index == animations.clips.defeat.frames.back(),
        "corpse holds its final pose indefinitely")
    animator.reset()
    check(animator.history.is_empty() and animator.poses.is_empty(), "restart clears presentation history")
    if failures == 0:
        print("PASS: animation resources, contact/pose alignment, reverse strike, reactions, corpse persistence and reset")
    quit(1 if failures else 0)
