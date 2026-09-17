extends Node

var _streams: Dictionary = {}
var _music: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_streams["swim"] = load("res://assets/sfx/swim.mp3")
	_streams["grappling"] = load("res://assets/sfx/grappling.mp3")
	_streams["checkpoint"] = load("res://assets/sfx/checkpoint.wav")
	_start_music()


func play(id: String, volume_db: float = 0.0) -> void:
	var stream := _streams.get(id) as AudioStream
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()


func _start_music() -> void:
	var stream := load("res://assets/sfx/ambient.wav") as AudioStream
	if stream == null:
		return
	_music = AudioStreamPlayer.new()
	_music.stream = stream
	_music.volume_db = -16.0
	add_child(_music)
	_music.play()
