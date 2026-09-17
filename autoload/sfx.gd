extends Node

const POOL_SIZE := 8

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next_player := 0
var _music: AudioStreamPlayer
var bypass_swim := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_streams["swim"] = load("res://assets/sfx/swim.mp3")
	_streams["grappling"] = load("res://assets/sfx/grappling.mp3")
	_streams["checkpoint"] = load("res://assets/sfx/checkpoint.wav")
	bypass_swim = _detect_bypass_swim()
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)
	_start_music()


func play(id: String, volume_db: float = 0.0) -> void:
	if id == "swim" and bypass_swim:
		return
	var stream := _streams.get(id) as AudioStream
	if stream == null or _players.is_empty():
		return
	var player := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	if player.playing:
		player.stop()
	player.stream = stream
	player.volume_db = volume_db
	player.play()


func _detect_bypass_swim() -> bool:
	if OS.get_cmdline_user_args().has("--bypass-swim"):
		return true
	if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
		var js := Engine.get_singleton("JavaScriptBridge")
		var flag: Variant = js.eval("new URLSearchParams(location.search).get('bypass_swim')")
		if str(flag) == "1":
			return true
	return false


func _start_music() -> void:
	var stream := load("res://assets/sfx/ambient.wav") as AudioStream
	if stream == null:
		return
	_music = AudioStreamPlayer.new()
	_music.stream = stream
	_music.volume_db = -16.0
	add_child(_music)
	_music.play()
