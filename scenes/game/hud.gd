class_name GameHUD
extends CanvasLayer

const SpriteTextScript := preload("res://scripts/sprite_text.gd")

var alive_text: SpriteTextScript
var swimming_text: SpriteTextScript
var score_text: SpriteTextScript
var hint_text: SpriteTextScript
var lobby_text: SpriteTextScript
var lobby_time: SpriteTextScript
var feed_text: SpriteTextScript
var crown: TextureRect
var _alive := -1
var _score := -1
var _feed_tween: Tween


func _ready() -> void:
	layer = 20
	alive_text = _line("1", 28, Vector2(12, 18), Vector2(280, 36), HORIZONTAL_ALIGNMENT_LEFT)
	swimming_text = _line("SWIMMING", 12, Vector2(12, 52), Vector2(320, 18), HORIZONTAL_ALIGNMENT_LEFT)
	score_text = _line("0", 40, Vector2(0, 76), Vector2(RR.VIEW_W, 70), HORIZONTAL_ALIGNMENT_CENTER, true)
	crown = TextureRect.new()
	crown.texture = Sprites.tex("crown_gold")
	crown.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	crown.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	crown.position = Vector2(RR.VIEW_W * 0.5 - 17, 48)
	crown.size = Vector2(34, 28)
	crown.visible = false
	add_child(crown)
	hint_text = _line("3", 78, Vector2(0, RR.VIEW_H * 0.34), Vector2(RR.VIEW_W, 110), HORIZONTAL_ALIGNMENT_CENTER, true)
	hint_text.visible = false
	lobby_text = _line("LOBBY", 22, Vector2(0, RR.VIEW_H * 0.30), Vector2(RR.VIEW_W, 32), HORIZONTAL_ALIGNMENT_CENTER)
	lobby_time = _line("12", 64, Vector2(0, RR.VIEW_H * 0.36), Vector2(RR.VIEW_W, 80), HORIZONTAL_ALIGNMENT_CENTER, true)
	feed_text = _line("", 14, Vector2(12, RR.VIEW_H - 92), Vector2(RR.VIEW_W - 24, 24), HORIZONTAL_ALIGNMENT_LEFT)


func _line(text: String, height: float, pos: Vector2, box: Vector2, align: HorizontalAlignment, gold := false) -> SpriteTextScript:
	var line := SpriteTextScript.new()
	line.position = pos
	line.configure(text, height, box, align, gold)
	add_child(line)
	return line


func refresh(alive_count: int, score: int, started: bool, player_alive: bool) -> void:
	if alive_count != _alive:
		_alive = alive_count
		alive_text.set_value(str(alive_count))
	if score != _score:
		_score = score
		score_text.set_value(str(score))
	crown.visible = player_alive and alive_count <= 10 and started
	if crown.visible:
		crown.texture = Sprites.tex("crown_gold" if alive_count <= 3 else "crown_silver")


func set_lobby(active: bool, starts_in: int) -> void:
	lobby_text.visible = active
	lobby_time.visible = active
	score_text.visible = not active
	if active:
		hint_text.visible = false
		lobby_text.set_value("LOBBY")
		lobby_time.set_value(str(maxi(0, starts_in)))


func set_countdown(value: String) -> void:
	hint_text.visible = not value.is_empty()
	if value.is_empty():
		return
	hint_text.set_value(value)


func show_feed(text: String) -> void:
	feed_text.set_value(text)
	feed_text.modulate.a = 1.0
	if _feed_tween:
		_feed_tween.kill()
	_feed_tween = create_tween()
	_feed_tween.tween_interval(0.9)
	_feed_tween.tween_property(feed_text, "modulate:a", 0.0, 0.5)
