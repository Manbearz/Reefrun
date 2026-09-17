extends Control

const SpriteTextScript := preload("res://scripts/sprite_text.gd")
const OVERLAY_W := 1145.0
const OVERLAY_H := 1374.0
const NAME_BOX := Rect2(270, 742, 590, 82)
const PLAY_BOX := Rect2(250, 900, 640, 185)
const SCORE_BOX := Rect2(210, 1124, 730, 168)
const BACK_BOX := Rect2(238, 1180, 669, 122)
const ROW_Y := [336.0, 415.0, 495.0, 575.0, 655.0, 737.0, 817.0, 897.0, 977.0, 1058.0]
const ROW_H := [41.0, 38.0, 39.0, 38.0, 39.0, 37.0, 36.0, 34.0, 38.0, 35.0]
const WEEKLY_NAME := Rect2(190, 0, 210, 0)
const WEEKLY_SCORE := Rect2(388, 0, 80, 0)
const MONTHLY_NAME := Rect2(726, 0, 210, 0)
const MONTHLY_SCORE := Rect2(924, 0, 80, 0)
const NAME_INSET := 1.0
const NAME_NUDGE_Y := 3.0
const SCORE_INSET := 2.0
const NAME_TEXT_SCALE := 1.28
const SCORE_NUM_SCALE := 0.78

var _home: Control
var _scores: Control
var _score_rows: Control
var _name_edit: LineEdit
var _ground: TextureRect
var _fish_icons: Array[TextureRect] = []
var _fish_rings: Array[Panel] = []
var _card_pos := Vector2.ZERO
var _card_scale := 1.0
var _score_pos := Vector2.ZERO
var _score_scale := 1.0
var _check_t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_backdrop()
	_card_scale = RR.VIEW_W / OVERLAY_W
	var card_size := Vector2(OVERLAY_W, OVERLAY_H) * _card_scale
	var fish_strip := 118.0
	_card_pos = Vector2((RR.VIEW_W - card_size.x) * 0.5, clampf((RR.VIEW_H - card_size.y - fish_strip) * 0.42, 10.0, 90.0))
	_score_scale = minf(RR.VIEW_H / OVERLAY_H, RR.VIEW_W / 952.0) * 0.92
	var score_size := Vector2(OVERLAY_W, OVERLAY_H) * _score_scale
	_score_pos = Vector2((RR.VIEW_W - score_size.x) * 0.5, (RR.VIEW_H - score_size.y) * 0.5)
	_home = _layer()
	_scores = _layer()
	_scores.visible = false
	_build_home(card_size)
	_build_scores(score_size)


func _process(delta: float) -> void:
	if not _scores.visible:
		return
	_check_t += delta
	if _check_t < 1.0:
		return
	_check_t = 0.0
	if GameSession.refresh_boards():
		_fill_scores()


func _backdrop() -> void:
	var bg := TextureRect.new()
	bg.texture = Sprites.tex("background")
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_ground = TextureRect.new()
	_ground.texture = Sprites.tex("ground")
	_ground.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ground.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ground.position = Vector2(0, RR.VIEW_H - RR.GROUND_H)
	_ground.size = Vector2(RR.VIEW_W, RR.GROUND_H)
	_ground.modulate = Color(1, 1, 1, 0.52)
	add_child(_ground)


func _layer() -> Control:
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layer)
	return layer


func _build_home(card_size: Vector2) -> void:
	_home.add_child(_overlay_card(Sprites.tex("main_menu_overlay"), card_size, _card_pos, true))
	_name_edit = LineEdit.new()
	_name_edit.text = GameSession.player_name
	_name_edit.placeholder_text = "YOUR NAME..."
	_name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_edit.max_length = 14
	_name_edit.position = _card_pos + NAME_BOX.position * _card_scale
	_name_edit.size = NAME_BOX.size * _card_scale
	_name_edit.caret_blink = true
	_style_name(_name_edit)
	_name_edit.text_changed.connect(_on_name_changed)
	_name_edit.text_submitted.connect(func(_t: String): _play())
	_home.add_child(_name_edit)
	_home.add_child(_hotspot(PLAY_BOX, _play, _card_pos, _card_scale))
	_home.add_child(_hotspot(SCORE_BOX, _show_scores, _card_pos, _card_scale))
	_build_fish_picker()


func _build_scores(card_size: Vector2) -> void:
	_scores.add_child(_overlay_card(Sprites.tex("highscore_overlay"), card_size, _score_pos))
	_score_rows = Control.new()
	_score_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_score_rows.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_scores.add_child(_score_rows)
	_scores.add_child(_hotspot(BACK_BOX, _show_home, _score_pos, _score_scale))
	_fill_scores()


func _overlay_card(tex: Texture2D, card_size: Vector2, origin: Vector2, fade_bottom := false) -> TextureRect:
	var card := TextureRect.new()
	card.texture = tex
	card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.position = origin
	card.size = card_size
	if fade_bottom:
		card.material = _bottom_coral_fade()
	return card


func _bottom_coral_fade() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
void fragment() {
	vec4 col = texture(TEXTURE, UV);
	col.a *= mix(1.0, 0.38, smoothstep(0.942, 0.995, UV.y));
	COLOR = col;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	return mat


func _build_fish_picker() -> void:
	var count := RR.FISH_IDS.size()
	var pad := 18.0
	var gap := 6.0
	var hs_bottom := _card_pos.y + (SCORE_BOX.position.y + SCORE_BOX.size.y) * _card_scale
	var row_h := 96.0
	var row_y := minf(hs_bottom + 6.0, RR.VIEW_H - row_h - 18.0)
	var avail := RR.VIEW_W - pad * 2.0
	var cell := (avail - gap * float(count - 1)) / float(count)
	for i in count:
		var x := pad + float(i) * (cell + gap)
		var ring := Panel.new()
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ring.position = Vector2(x, row_y)
		ring.size = Vector2(cell, row_h)
		_fish_rings.append(ring)
		_home.add_child(ring)
		var icon := TextureRect.new()
		icon.texture = Sprites.tex(RR.FISH_IDS[i])
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.position = Vector2(x, row_y)
		icon.size = Vector2(cell, row_h)
		_fish_icons.append(icon)
		_home.add_child(icon)
		var btn := Button.new()
		btn.flat = true
		btn.position = Vector2(x, row_y)
		btn.size = Vector2(cell, row_h)
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.pressed.connect(_choose_fish.bind(i))
		_home.add_child(btn)
	_refresh_fish_pick()


func _choose_fish(index: int) -> void:
	GameSession.fish_index = clampi(index, 0, RR.FISH_IDS.size() - 1)
	GameSession._save()
	_refresh_fish_pick()


func _refresh_fish_pick() -> void:
	var chosen := clampi(GameSession.fish_index, 0, RR.FISH_IDS.size() - 1)
	for i in _fish_icons.size():
		var on := i == chosen
		var ring_style := StyleBoxFlat.new()
		ring_style.bg_color = Color(0.12, 0.42, 0.62, 0.22 if on else 0.0)
		ring_style.set_border_width_all(3 if on else 0)
		ring_style.border_color = Color(1.0, 0.92, 0.42, 0.95)
		ring_style.set_corner_radius_all(18)
		_fish_rings[i].add_theme_stylebox_override("panel", ring_style)
		_fish_icons[i].modulate = Color.WHITE if on else Color(0.82, 0.88, 0.92, 0.78)
		_fish_icons[i].scale = Vector2.ONE
		var grow := 1.08 if on else 1.0
		_fish_icons[i].pivot_offset = _fish_icons[i].size * 0.5
		_fish_icons[i].scale = Vector2(grow, grow)


func _hotspot(src: Rect2, pressed: Callable, origin: Vector2, scale: float) -> Button:
	var btn := Button.new()
	btn.flat = true
	btn.position = origin + src.position * scale
	btn.size = src.size * scale
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.pressed.connect(pressed)
	return btn


func _style_name(edit: LineEdit) -> void:
	var well := StyleBoxFlat.new()
	well.bg_color = Color(0.97, 0.99, 1.0, 1)
	well.set_corner_radius_all(int(round(NAME_BOX.size.y * _card_scale * 0.42)))
	well.content_margin_left = 10
	well.content_margin_right = 10
	edit.add_theme_stylebox_override("normal", well)
	edit.add_theme_stylebox_override("focus", well)
	edit.add_theme_stylebox_override("read_only", well)
	edit.add_theme_color_override("font_color", Color("16324a"))
	edit.add_theme_color_override("font_placeholder_color", Color(0.42, 0.55, 0.66, 0.85))
	edit.add_theme_color_override("caret_color", Color("16324a"))
	edit.add_theme_font_size_override("font_size", maxi(16, int(round(NAME_BOX.size.y * _card_scale * 0.42))))


func _on_name_changed(value: String) -> void:
	GameSession.player_name = value.strip_edges()
	GameSession._save()


func _show_scores() -> void:
	_on_name_changed(_name_edit.text)
	GameSession.refresh_boards()
	_fill_scores()
	_home.visible = false
	_scores.visible = true
	if _ground:
		_ground.visible = false


func _fill_scores() -> void:
	for child in _score_rows.get_children():
		child.queue_free()
	_fill_column(GameSession.weekly, WEEKLY_NAME, WEEKLY_SCORE)
	_fill_column(GameSession.monthly, MONTHLY_NAME, MONTHLY_SCORE)


func _fill_column(board: Array, name_col: Rect2, score_col: Rect2) -> void:
	for i in ROW_Y.size():
		var y: float = ROW_Y[i]
		var h: float = ROW_H[i]
		var name := ""
		var score := ""
		if i < board.size():
			name = str(board[i].get("name", ""))
			score = str(int(board[i].get("score", 0)))
		var name_box := Rect2(name_col.position.x, y + NAME_INSET + NAME_NUDGE_Y, name_col.size.x, h - NAME_INSET * 2.0)
		var score_box := Rect2(score_col.position.x, y + SCORE_INSET, score_col.size.x, h - SCORE_INSET * 2.0)
		_score_rows.add_child(_row_text(name, name_box, HORIZONTAL_ALIGNMENT_CENTER, false, NAME_TEXT_SCALE))
		_score_rows.add_child(_row_text(score, score_box, HORIZONTAL_ALIGNMENT_RIGHT, true, SCORE_NUM_SCALE))


func _row_text(text: String, src: Rect2, align: HorizontalAlignment, gold: bool, text_scale: float) -> SpriteTextScript:
	var line := SpriteTextScript.new()
	var box := src.size * _score_scale
	var tall := Vector2(box.x, box.y * text_scale)
	line.position = _score_pos + src.position * _score_scale + Vector2(0.0, (box.y - tall.y) * 0.25)
	line.configure(text, tall.y, tall, align, gold, true)
	return line


func _show_home() -> void:
	_scores.visible = false
	_home.visible = true
	if _ground:
		_ground.visible = true


func _play() -> void:
	_on_name_changed(_name_edit.text)
	GameSession.start_match()
	get_tree().change_scene_to_file("res://scenes/game/game.tscn")
