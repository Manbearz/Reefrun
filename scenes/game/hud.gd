class_name GameHUD
extends CanvasLayer

const SpriteTextScript := preload("res://scripts/sprite_text.gd")

var alive_text: SpriteTextScript
var swimming_text: SpriteTextScript
var score_text: SpriteTextScript
var hint_text: SpriteTextScript
var lobby_text: SpriteTextScript
var lobby_time: SpriteTextScript
var jump_hint: TextureRect
var feed_text: SpriteTextScript
var crown: TextureRect
var _coin_icon: TextureRect
var _coin_text: SpriteTextScript
var _alive := -1
var _score := -1
var _coins := -1
var _feed_tween: Tween
var _glyph_probe: SpriteTextScript
var _suppress_lobby_chrome := false
var _chrome_fade: Tween
var dive_text: SpriteTextScript
var _top_chrome: Array[Dictionary] = []


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
	crown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(crown)
	_coin_icon = TextureRect.new()
	_coin_icon.texture = Sprites.tex("coin")
	_coin_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_coin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_coin_icon.position = Vector2(RR.VIEW_W - 108, 16)
	_coin_icon.size = Vector2(30, 30)
	_coin_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_coin_icon)
	_coin_text = _line("0", 22, Vector2(RR.VIEW_W - 74, 16), Vector2(62, 30), HORIZONTAL_ALIGNMENT_LEFT, true)
	_track_top(alive_text)
	_track_top(swimming_text)
	_track_top(score_text)
	_track_top(crown)
	_track_top(_coin_icon)
	_track_top(_coin_text)
	hint_text = _line("3", 78, Vector2(0, RR.VIEW_H * 0.34), Vector2(RR.VIEW_W, 110), HORIZONTAL_ALIGNMENT_CENTER, true)
	hint_text.visible = false
	lobby_text = _line("LOBBY", 22, Vector2(0, RR.VIEW_H * 0.30), Vector2(RR.VIEW_W, 32), HORIZONTAL_ALIGNMENT_CENTER)
	lobby_time = _line("12", 64, Vector2(0, RR.VIEW_H * 0.36), Vector2(RR.VIEW_W, 80), HORIZONTAL_ALIGNMENT_CENTER, true)
	_build_jump_hint()
	feed_text = _line("", 14, Vector2(12, RR.screen_bottom() - 92.0), Vector2(RR.VIEW_W - 24, 24), HORIZONTAL_ALIGNMENT_LEFT)
	apply_screen_layout()
	_prewarm_glyphs()


func apply_screen_layout() -> void:
	var inset := _top_safe_inset()
	for entry in _top_chrome:
		var node := entry["node"] as CanvasItem
		if node == null:
			continue
		var base: Vector2 = entry["base"]
		node.position = base + Vector2(0.0, inset)
	if feed_text:
		feed_text.position.y = RR.screen_bottom() - 92.0 - RR.display_insets(RR.screen_size()).w


func _track_top(node: CanvasItem) -> void:
	_top_chrome.append({"node": node, "base": node.position})


func _top_safe_inset() -> float:
	# Status bar, camera hole, and Dynamic Island. Pipes, the fish, and
	# PLAY_TOP are not moved.
	return RR.display_insets(RR.screen_size()).y


func _prewarm_glyphs() -> void:
	_glyph_probe = SpriteTextScript.new()
	_glyph_probe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glyph_probe.position = Vector2(2, 2)
	_glyph_probe.modulate.a = 0.04
	_glyph_probe.configure("0123456789", 8, Vector2(72, 10), HORIZONTAL_ALIGNMENT_LEFT, true)
	add_child(_glyph_probe)
	score_text.set_value("1")
	score_text.set_value("0")
	show_feed(" ")
	feed_text.modulate.a = 0.0


func hide_prewarm() -> void:
	if _glyph_probe:
		_glyph_probe.visible = false


func _build_jump_hint() -> void:
	jump_hint = TextureRect.new()
	jump_hint.texture = Sprites.tex("jump_overlay")
	jump_hint.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	jump_hint.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	jump_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	jump_hint.visible = false
	var tex := jump_hint.texture
	var aspect := 2.6
	if tex:
		aspect = float(tex.get_width()) / maxf(1.0, float(tex.get_height()))
	var w := RR.VIEW_W * 0.62
	var h := w / aspect
	jump_hint.size = Vector2(w, h)
	jump_hint.position = Vector2((RR.VIEW_W - w) * 0.5, lobby_time.position.y + lobby_time.size.y + 6.0)
	add_child(jump_hint)


func _line(text: String, height: float, pos: Vector2, box: Vector2, align: HorizontalAlignment, gold := false) -> SpriteTextScript:
	var line := SpriteTextScript.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
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


func set_mission_card(active: bool, reveal_sec := 0.0) -> void:
	_suppress_lobby_chrome = active
	if active:
		_stop_chrome_fade()
		_show_lobby_chrome(false)
		return
	if reveal_sec > 0.0:
		_fade_in_lobby_chrome(reveal_sec)


func set_lobby(active: bool, starts_in: int) -> void:
	var show_chrome := active and not _suppress_lobby_chrome
	score_text.visible = not active
	if not show_chrome:
		if _chrome_fade == null:
			_show_lobby_chrome(false)
	elif _chrome_fade == null:
		_show_lobby_chrome(true)
	if active:
		hint_text.visible = false
		lobby_text.set_value("LOBBY")
		lobby_time.set_value(str(maxi(0, starts_in)))


func _show_lobby_chrome(show: bool) -> void:
	lobby_text.visible = show
	lobby_time.visible = show
	lobby_text.modulate.a = 1.0 if show else 0.0
	lobby_time.modulate.a = 1.0 if show else 0.0
	if jump_hint:
		jump_hint.visible = show
		jump_hint.modulate.a = 1.0 if show else 0.0


func _stop_chrome_fade() -> void:
	if _chrome_fade:
		_chrome_fade.kill()
		_chrome_fade = null


func _fade_in_lobby_chrome(seconds: float) -> void:
	_stop_chrome_fade()
	lobby_text.visible = true
	lobby_time.visible = true
	lobby_text.modulate.a = 0.0
	lobby_time.modulate.a = 0.0
	if jump_hint:
		jump_hint.visible = true
		jump_hint.modulate.a = 0.0
	var fade := create_tween()
	_chrome_fade = fade
	fade.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	fade.set_parallel(true)
	fade.tween_property(lobby_text, "modulate:a", 1.0, seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	fade.tween_property(lobby_time, "modulate:a", 1.0, seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	if jump_hint:
		fade.tween_property(jump_hint, "modulate:a", 1.0, seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	fade.finished.connect(func() -> void:
		if _chrome_fade == fade:
			_chrome_fade = null
	)


func set_countdown(value: String) -> void:
	hint_text.visible = not value.is_empty()
	if value.is_empty():
		return
	hint_text.set_value(value)


func set_dive_timer(label: String, show: bool) -> void:
	if dive_text == null:
		dive_text = _line("DIVE", 16, Vector2(12, 96), Vector2(230, 24), HORIZONTAL_ALIGNMENT_LEFT, true)
		_track_top(dive_text)
		apply_screen_layout()
	var visible_label := show and not label.is_empty()
	dive_text.visible = visible_label
	if visible_label:
		dive_text.set_value(label)


func set_coins(value: int) -> void:
	if value == _coins:
		return
	_coins = value
	_coin_text.set_value(str(maxi(0, value)))


func show_feed(text: String) -> void:
	feed_text.set_value(text)
	feed_text.modulate.a = 1.0
	if _feed_tween:
		_feed_tween.kill()
	_feed_tween = create_tween()
	_feed_tween.tween_interval(0.9)
	_feed_tween.tween_property(feed_text, "modulate:a", 0.0, 0.5)
