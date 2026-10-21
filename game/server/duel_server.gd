extends Node

const CampaignRunner=preload("res://scripts/session/campaign_host_runner.gd")
const CampaignProtocol=preload("res://scripts/session/campaign_protocol.gd")
const Runner=preload("res://scripts/session/duel_host_runner.gd")
const Release=preload("res://server/version.json")
const Rules=preload("res://content/foundation_rules.tres")
const Protocol=preload("res://scripts/session/duel_protocol.gd")
var runner: Node
var last_state: String=""
var campaign_mode: bool=false

func _ready() -> void:
    var args: PackedStringArray=OS.get_cmdline_user_args()
    if "--version" in args:
        print("Moonstone duel server ",Release.data.version," protocol=",Protocol.VERSION," combat=",Protocol.fingerprint())
        print("Campaign protocol=",CampaignProtocol.VERSION," campaign=",CampaignProtocol.fingerprint())
        get_tree().quit();return
    if "--help" in args:
        print("Moonstone duel server ",Release.data.version,"\nUsage: Moonstone-Server --port PORT\nDuel: UDP27866, two players.\nCampaign: --campaign --players 2 --port 27867 --save user://network-campaign.json\nCampaign supports1-4 humans. Existing saves reserve their original seats. Ctrl+C stops the host.")
        get_tree().quit();return
    campaign_mode="--campaign" in args
    var port: int=27867 if campaign_mode else 27866
    var count: int=2
    var save_path: String="user://network-campaign.json"
    var seed: int=0
    var index: int=0
    while index<args.size():
        var option: String=args[index]
        var value: String=""
        if option=="--campaign":index+=1;continue
        if "=" in option:
            value=option.get_slice("=",1);option=option.get_slice("=",0)
        elif option in ["--port","--players","--save","--seed"] and index+1<args.size():index+=1;value=args[index]
        else:_error("Unknown argument. Use --help.");return
        if option=="--port":
            if not value.is_valid_int() or int(value)<1024 or int(value)>65535:_error("Port must be 1024 to65535.");return
            port=int(value)
        elif option=="--players" and campaign_mode:
            if not value.is_valid_int() or int(value)<1 or int(value)>4:_error("Players must be1 to4.");return
            count=int(value)
        elif option=="--save" and campaign_mode:
            if value.is_empty() or value.length()>512:_error("A campaign save path is required.");return
            save_path=value
        elif option=="--seed" and campaign_mode:
            if not value.is_valid_int() or int(value)<1 or int(value)>0x7fffffff:_error("Seed must be1 to2147483647.");return
            seed=int(value)
        else:_error("Unknown argument. Use --help.");return
        index+=1
    if DisplayServer.get_name()!="headless":_error("Run the server with --headless.");return
    if campaign_mode:
        if seed==0:
            var rng:=RandomNumberGenerator.new();rng.randomize();seed=rng.randi_range(2,0x7fffffff)
        runner=CampaignRunner.new(count,seed,save_path)
    else:runner=Runner.new(Rules)
    if not runner.host.listen(port):runner.free();runner=null;_error("Cannot open the port or combat build is not ready.");return
    add_child(runner);runner.host.changed.connect(_changed)
    if campaign_mode:
        print("MOONSTONE_CAMPAIGN_READY port=",port," version=",Release.data.version," humans=",runner.host.human_count," protocol=",CampaignProtocol.VERSION," build=",CampaignProtocol.fingerprint()," display=",DisplayServer.get_name())
        print("Campaign host: players join their reserved knight and all choose Ready.")
        _changed();return
    print("MOONSTONE_SERVER_READY port=",port," version=",Release.data.version," protocol=",Protocol.VERSION," build=",Protocol.fingerprint()," display=",DisplayServer.get_name())
    print("Waiting for two game clients. Ctrl+C stops the host.")
    _changed()

func _changed() -> void:
    var host: RefCounted=runner.host
    if campaign_mode:
        if host.state!=last_state:
            last_state=host.state;print("MOONSTONE_CAMPAIGN_STATE state=",host.state," players=",host.seats.size()," notice=",host.notice)
        return
    if host.state=="closed":_error("Cannot reopen the duel port. Restart the host.");return
    if host.state=="ended" and last_state!="ended":
        print("MOONSTONE_SERVER_ROUND round=",host.session.round_id," tick=",host.session.simulation.tick," hash=",Protocol.state_hash(host.session.simulation.snapshot())," outcome=",host.session.simulation.outcome())
    if host.state!=last_state or host.state=="listening":
        last_state=host.state
        print("MOONSTONE_SERVER_STATE state=",host.state," players=",host.seats.size())

func _error(message: String) -> void:
    printerr(message);get_tree().quit(2)

func _notification(what: int) -> void:
    if what==NOTIFICATION_WM_CLOSE_REQUEST and runner!=null and campaign_mode:runner.host.save();get_tree().quit()
