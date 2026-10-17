extends Node
const Runtime=preload("res://scripts/session/runtime_mode.gd")

const Pack = preload("res://assets/classic/audio/sounds.tres")
const Town=preload("res://assets/classic/town_locations/art.tres")
const VOICES: int = 8
var players: Array[AudioStreamPlayer] = []
var owners: Dictionary = {}
var muted: bool = false
var volume: float = 0.7
var enabled: bool = true
var played: Array[Dictionary] = []
var trace_enabled: bool = false
var trace_path: String = ""
var serial: int = 0
var toast: Label
var toast_time: float = 0
var recording: AudioEffectRecord
var recording_path: String = ""
var music_player: AudioStreamPlayer
var music_active: bool=false
var music_tick: int=-1
var music_owner: String=""

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    # Validate exported resource dependencies even with headless/Dummy playback.
    # Source-only success does not establish that the release contains its WAVs.
    for key in Pack.streams.merged(Town.streams):
        var stream: AudioStream = Pack.streams.get(key,Town.streams.get(key))
        if stream == null or not stream is AudioStreamWAV or stream.get_length() <= 0:
            push_error("Missing native audio stream: " + key)
            enabled = false
    var settings := ConfigFile.new()
    if settings.load("user://preferences.cfg") == OK:
        muted = bool(settings.get_value("audio", "muted", false))
        volume = clampf(float(settings.get_value("audio", "volume", 0.7)),0,1)
    for argument in Runtime.user_arguments(Runtime.debug_enabled()):
        if argument == "--mute": muted = true
        if argument == "--unmute": muted = false
        if argument.begins_with("--sound-volume="):
            volume = clampf(float(argument.trim_prefix("--sound-volume=")),0,1)
        if argument == "--audio-disabled": enabled = false
        if argument.begins_with("--audio-trace="):
            trace_path = argument.trim_prefix("--audio-trace=")
            trace_enabled = true
            print("AUDIO_PACK=",Pack.streams.size()+Town.streams.size()," native streams validated")
        if argument.begins_with("--audio-record="):
            recording_path = argument.trim_prefix("--audio-record=")
    var bus: int = AudioServer.get_bus_index("Moonstone")
    if bus < 0:
        AudioServer.add_bus()
        bus = AudioServer.bus_count - 1
        AudioServer.set_bus_name(bus,"Moonstone")
    if not recording_path.is_empty():
        recording = AudioEffectRecord.new()
        recording.format = AudioStreamWAV.FORMAT_16_BITS
        AudioServer.add_bus_effect(bus,recording)
        recording.set_recording_active(true)
    for i in VOICES:
        var player := AudioStreamPlayer.new()
        player.bus = "Moonstone"
        add_child(player)
        players.append(player)
    music_player=AudioStreamPlayer.new()
    music_player.bus="Moonstone"
    add_child(music_player)
    var layer := CanvasLayer.new()
    layer.layer = 90
    add_child(layer)
    toast = Label.new()
    toast.position = Vector2(432,6)
    toast.add_theme_font_size_override("font_size",14)
    layer.add_child(toast)
    apply_volume()

func play_cue(key: String, owner: String = "", tick: int = -1) -> void:
    if not Pack.streams.has(key) and not Town.streams.has(key):
        push_error("Unknown audio cue: " + key)
        return
    if trace_enabled:
        played.append({"key":key,"owner":owner,"tick":tick,"muted":muted,"enabled":enabled})
        # Flushed at each cue so exports that quit immediately retain evidence.
        var file := FileAccess.open(trace_path,FileAccess.WRITE)
        if file != null: file.store_string(JSON.stringify(played))
    # Dummy has no mixer to retire playback references on immediate headless
    # shutdown. Headless runs still resolve/trace cues and verify every stream.
    if not enabled or muted or AudioServer.get_driver_name() == "Dummy": return
    var selected: AudioStreamPlayer
    for player in players:
        if not player.playing:
            selected = player
            break
    if selected == null:
        selected = players[serial % VOICES]
    serial += 1
    selected.stop()
    selected.stream = Pack.streams.get(key,Town.streams.get(key))
    owners[selected.get_instance_id()] = {"owner":owner,"sustained":(Pack.sustained.has(key) or Town.sustained.has(key))}
    selected.play()

func stop_owner(owner: String, sustained_only: bool = true) -> void:
    for player in players:
        var entry: Dictionary = owners.get(player.get_instance_id(),{})
        if entry.get("owner", "") == owner and (not sustained_only or entry.get("sustained",false)):
            player.stop()

func stop_scope(prefix: String, sustained_only: bool = true) -> void:
    for player in players:
        var entry: Dictionary = owners.get(player.get_instance_id(),{})
        if String(entry.get("owner", "")).begins_with(prefix) and (not sustained_only or entry.get("sustained",false)):
            player.stop()

func stop_all() -> void:
    for player in players: player.stop()
    owners.clear()

func ending_music(tick: int) -> void:
    const Ending=preload("res://assets/classic/ending_complete/art.tres")
    if tick<Ending.music_tick:
        stop_music()
        return
    if music_active and music_owner=="ending":
        music_tick=tick
        return
    stop_music()
    music_active=true;music_tick=tick;music_owner="ending"
    if trace_enabled:
        played.append({"key":"ending_music","owner":"ending0036","tick":tick,"offset":float(tick-Ending.music_tick)/50.0,"muted":muted,"enabled":enabled})
        var file:=FileAccess.open(trace_path,FileAccess.WRITE)
        if file!=null:file.store_string(JSON.stringify(played))
    # PCM position is presentation only. It cannot drive campaign progression.
    music_player.stream=Ending.music
    if enabled and AudioServer.get_driver_name()!="Dummy":music_player.play(float(tick-Ending.music_tick)/50.0)

func opening_music(tick: int) -> void:
    const Opening=preload("res://assets/classic/intro_menu/art.tres")
    if tick<Opening.music_tick:
        stop_music()
        return
    if music_active and music_owner=="intro":return
    stop_music()
    music_active=true;music_tick=tick;music_owner="intro"
    if trace_enabled:
        played.append({"key":"opening_music","owner":"intro","tick":tick,"offset":float(tick-Opening.music_tick)/50.0,"muted":muted,"enabled":enabled})
        var file:=FileAccess.open(trace_path,FileAccess.WRITE)
        if file!=null:file.store_string(JSON.stringify(played))
    music_player.stream=Opening.music
    if enabled and AudioServer.get_driver_name()!="Dummy":music_player.play(float(tick-Opening.music_tick)/50.0)

func menu_music() -> void:
    const Opening=preload("res://assets/classic/intro_menu/art.tres")
    if music_active and music_owner=="menu":return
    stop_music()
    music_active=true;music_owner="menu";music_tick=0
    if trace_enabled:
        played.append({"key":"menu_music","owner":"title","tick":0,"muted":muted,"enabled":enabled})
        var file:=FileAccess.open(trace_path,FileAccess.WRITE)
        if file!=null:file.store_string(JSON.stringify(played))
    var stream: AudioStreamWAV=Opening.menu_music.duplicate()
    stream.loop_mode=AudioStreamWAV.LOOP_FORWARD
    stream.loop_begin=Opening.menu_loop_begin;stream.loop_end=Opening.menu_loop_end
    music_player.stream=stream
    if enabled and AudioServer.get_driver_name()!="Dummy":music_player.play()

func stop_music() -> void:
    if is_instance_valid(music_player):music_player.stop()
    music_active=false;music_tick=-1;music_owner=""

func apply_volume() -> void:
    for player in players:
        player.volume_db = linear_to_db(volume * 0.5) if not muted and volume > 0 else -80
    if muted or volume == 0: stop_all()
    if is_instance_valid(music_player):music_player.volume_db=linear_to_db(volume*0.5) if not muted and volume>0 else -80

func save_preference() -> void:
    if Runtime.debug_enabled():return
    var settings := ConfigFile.new()
    settings.load("user://preferences.cfg") # preserve the gore preference
    settings.set_value("audio", "muted", muted)
    settings.set_value("audio", "volume", volume)
    if settings.save("user://preferences.cfg") != OK: push_warning("Sound preference could not be saved")

func _input(event: InputEvent) -> void:
    if not event is InputEventKey or not event.pressed or event.echo: return
    if event.keycode not in [KEY_F8,KEY_F9,KEY_F10]: return
    if event.keycode == KEY_F8: muted = not muted
    elif event.keycode == KEY_F9: volume = maxf(0,volume-0.1)
    else: volume = minf(1,volume+0.1)
    apply_volume()
    save_preference()
    toast.text = "Sound off" if muted else "Sound %d%%" % roundi(volume*100)
    toast_time = 2.0
    toast.visible = true
    get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
    toast_time = maxf(0,toast_time-delta)
    if is_instance_valid(toast): toast.visible = toast_time > 0

func _exit_tree() -> void:
    if recording != null:
        recording.set_recording_active(false)
        var stream: AudioStreamWAV = recording.get_recording()
        if stream != null:
            var error: int = stream.save_to_wav(recording_path)
            if error != OK: push_error("Could not save runtime audio recording")
    stop_all()
    stop_music()
    if is_instance_valid(music_player):music_player.stream=null
    for player in players: player.stream = null
