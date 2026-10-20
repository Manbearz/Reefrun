extends Control

const SpriteTextScript := preload("res://scripts/sprite_text.gd")
const DailyAttemptScript := preload("res://scripts/daily_attempt.gd")
const DailyTestModeScript := preload("res://scripts/daily_test_mode.gd")
const OVERLAY_W := 1145.0
const OVERLAY_H := 1374.0
const SCORE_W := 941.0
const SCORE_H := 1672.0
const NAME_BOX := Rect2(270, 742, 590, 82)
const PLAY_BOX := Rect2(250, 900, 640, 185)
const SCORE_BOX := Rect2(210, 1124, 730, 168)
const BACK_BOX := Rect2(230, 1478, 480, 140)
# Inner light-blue bars on the 941-wide scoreboard art, to the right of the painted ranks.
const SCORE_ROWS_Y := [427.0, 531.0, 635.0, 739.0, 843.0, 947.0, 1052.0, 1157.0, 1261.0, 1361.0]
const SCORE_ROWS_H := [88.0, 87.0, 87.0, 87.0, 88.0, 88.0, 88.0, 87.0, 83.0, 85.0]
const SCORE_NAME_X := 286.0
const SCORE_NAME_W := 310.0
const SCORE_VALUE_X := 554.0
const SCORE_VALUE_W := 150.0
const SCORE_PAGES := ["daily", "weekly", "monthly"]
const MODE_W := 845.0
const MODE_H := 1860.0
const MODE_UNLIMITED := Rect2(64, 608, 716, 338)
const MODE_DAILY := Rect2(62, 976, 720, 310)
const MODE_MISSIONS := Rect2(16, 1316, 784, 220)
const MODE_BACK := Rect2(130, 1632, 520, 198)
const MODE_NOTE := Rect2(90, 1148, 660, 52)
const MODE_RESET_LINE := Rect2(90, 1250, 660, 28)
const SWIPE_MIN := 48.0
const ARROW_BOX := 96.0

var _home: Control
var _scores: Control
var _score_card: TextureRect
var _score_rows: Control
var _score_names: Array[SpriteTextScript] = []
var _score_values: Array[SpriteTextScript] = []
var _score_status: SpriteTextScript
var _score_page := 0
var _score_swiping := false
var _score_press := Vector2.ZERO
var _score_arrow_left_rect := Rect2()
var _score_arrow_right_rect := Rect2()
var _name_edit: LineEdit
var _ground: TextureRect
var _fish_icons: Array[TextureRect] = []
var _fish_rings: Array[Panel] = []
var _fish_hats: Array[TextureRect] = []
var _fish_prices: Array[Control] = []
var _fish_cells: Array[Control] = []
var _fish_rest: Array[Vector2] = []
var _fish_phase := PackedFloat32Array()
var _fish_speed := PackedFloat32Array()
var _fish_order: PackedInt32Array = PackedInt32Array()
var _fish_clip: Control
var _fish_row: Control
var _fish_scroll_x := 0.0
var _fish_max_scroll := 0.0
var _fish_cell := 76.0
var _fish_gap := 8.0
var _fish_pressing := false
var _fish_dragged := false
var _fish_press := Vector2.ZERO
var _fish_press_scroll := 0.0
var _hat_icons: Array[TextureRect] = []
var _hat_rings: Array[Panel] = []
var _hat_prices: Array[Control] = []
var _hat_cells: Array[Control] = []
var _hat_rest: Array[Vector2] = []
var _hat_phase := PackedFloat32Array()
var _hat_speed := PackedFloat32Array()
var _hat_ids: PackedInt32Array = PackedInt32Array()
var _hat_clip: Control
var _hat_row: Control
var _hat_scroll_x := 0.0
var _hat_max_scroll := 0.0
var _hat_cell := 68.0
var _hat_gap := 8.0
var _hat_pressing := false
var _hat_dragged := false
var _hat_press := Vector2.ZERO
var _hat_press_scroll := 0.0
var _wallet_coin: TextureRect
var _wallet_text: SpriteTextScript
var _wallet_rest := Vector2.ZERO
var _wallet_text_rest := Vector2.ZERO
var _wallet_phase := 0.22
var _wallet_speed := 1.64
var _wallet_flash := 0.0
var _bob_t := 0.0
var _card_pos := Vector2.ZERO
var _card_scale := 1.0
var _score_pos := Vector2.ZERO
var _score_scale := Vector2.ONE
var _score_back: Button
var _score_arrow_left_icon: TextureRect
var _score_arrow_right_icon: TextureRect
var _score_arrow_left_btn: Button
var _score_arrow_right_btn: Button
var _check_t := 0.0
var _modes: Control
var _mode_origin := Vector2.ZERO
var _mode_scale := Vector2.ONE
var _mode_card: TextureRect
var _mode_reset_cover: Control
var _mode_note: SpriteTextScript
var _mode_reset: SpriteTextScript
var _daily_button: Button
var _mode_unlimited: Button
var _mode_back: Button
var _mission_button: Button
var _missions: DailyMissionsOverlay
var _modes_return := false
var _mode_token := 0
var _mode_busy := false
var _daily_locked := false
var _status_course: Dictionary = {}
var _daily_checking := false
var _status_busy := false
var _status_again := false
var _daily_resets_unix := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	set_process(true)
	set_process_input(true)
	_backdrop()
	_card_scale = RR.VIEW_W / OVERLAY_W
	var card_size := Vector2(OVERLAY_W, OVERLAY_H) * _card_scale
	var fish_strip := 210.0
	_card_pos = Vector2((RR.VIEW_W - card_size.x) * 0.5, clampf((RR.VIEW_H - card_size.y - fish_strip) * 0.42, 10.0, 90.0))
	_home = _layer()
	_scores = _layer()
	_scores.visible = false
	_build_home(card_size)
	_build_scores()
	_build_mode_overlay()
	_missions = DailyMissionsOverlay.new()
	_missions.use_screen_board()
	add_child(_missions)
	_missions.set_dismissible(true)
	_missions.present("hidden")
	_missions.dismissed.connect(_close_missions)
	var backend := get_node_or_null("/root/Backend")
	if backend and backend.has_method("prepare_menu"):
		backend.prepare_menu()
	if backend and backend.has_method("on_menu_ready"):
		backend.on_menu_ready()
	if backend and backend.has_signal("leaderboards_ready") and not backend.leaderboards_ready.is_connected(_fill_scores):
		backend.leaderboards_ready.connect(_fill_scores)
	if backend and backend.has_signal("identity_ready") and not backend.identity_ready.is_connected(_on_identity_ready):
		backend.identity_ready.connect(_on_identity_ready)
	if backend and backend.has_signal("share_rewards_changed") and not backend.share_rewards_changed.is_connected(_refresh_wallet):
		backend.share_rewards_changed.connect(_refresh_wallet)
	if backend and backend.has_signal("daily_missions_changed") and not backend.daily_missions_changed.is_connected(_refresh_wallet):
		backend.daily_missions_changed.connect(_refresh_wallet)
	if backend and backend.has_signal("daily_missions_changed") and not backend.daily_missions_changed.is_connected(_on_menu_missions):
		backend.daily_missions_changed.connect(_on_menu_missions)
	if not get_viewport().size_changed.is_connected(_sync_menu_anchor):
		get_viewport().size_changed.connect(_sync_menu_anchor)


func _process(delta: float) -> void:
	if _home.visible:
		_bob_picker(delta)
		if _wallet_flash > 0.0:
			_wallet_flash = maxf(_wallet_flash - delta, 0.0)
			if _wallet_text:
				var pulse := 0.5 + 0.5 * sin(_wallet_flash * 18.0)
				_wallet_text.modulate = Color(1.0, pulse, pulse, 1.0)
				if _wallet_flash <= 0.0:
					_wallet_text.modulate = Color.WHITE
	_check_t += delta
	if _check_t < 1.0:
		return
	_check_t = 0.0
	if _mode_shows_locked() and _modes and _modes.visible:
		_set_mode_reset(DailyAttemptScript.reset_label(_daily_resets_unix, int(Time.get_unix_time_from_system())))
	var backend := get_node_or_null("/root/Backend")
	if _mode_busy:
		backend = null
	if backend and backend.has_method("daily_refresh_due") and backend.daily_refresh_due():
		backend.call_deferred("refresh_daily_after_rollover")
		if _modes and _modes.visible:
			_refresh_daily_status()
	if not _scores.visible:
		return
	if GameSession.refresh_boards():
		_fill_scores()
	if backend and backend.has_method("leaderboard_period_stale") and backend.leaderboard_period_stale():
		backend.call_deferred("fetch_leaderboards")


func _input(event: InputEvent) -> void:
	if _scores.visible and _score_swipe_input(event):
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_on_menu_touch_press(touch.position)
		else:
			_on_menu_touch_release(touch.position)
		return
	if event is InputEventScreenDrag and _hat_pressing:
		_move_hat_drag(_hat_local((event as InputEventScreenDrag).position))
		_mark_input_handled()


func _mark_input_handled() -> void:
	if not is_inside_tree():
		return
	var vp := get_viewport()
	if vp:
		vp.set_input_as_handled()


func _on_menu_touch_press(pos: Vector2) -> void:
	if _missions and _missions.mode() == "board":
		if not _missions.card_contains(pos):
			_close_missions()
		_mark_input_handled()
		return
	if _modes and _modes.visible:
		if not _press_button_in(_modes, pos):
			_mark_input_handled()
		else:
			_mark_input_handled()
		return
	if _home.visible and _hat_clip != null and _hat_contains(pos):
		_begin_hat_drag(_hat_local(pos))
		_mark_input_handled()
		return
	if _press_button_at(pos):
		_mark_input_handled()
		return
	if _home.visible and _name_edit and _name_edit.is_visible_in_tree() and _name_edit.get_global_rect().has_point(pos):
		_name_edit.grab_focus()
		GameSession.begin_virtual_keyboard_lock()
		_mark_input_handled()


func _on_menu_touch_release(pos: Vector2) -> void:
	if _hat_pressing:
		_end_hat_drag(_hat_local(pos))
		_mark_input_handled()


func _hat_contains(pos: Vector2) -> bool:
	if _hat_clip == null:
		return false
	return Rect2(Vector2.ZERO, _hat_clip.size).has_point(_hat_local(pos))


func _press_button_at(pos: Vector2) -> bool:
	if _home and _home.visible:
		if _press_button_in(_home, pos):
			return true
	if _scores and _scores.visible:
		if _press_button_in(_scores, pos):
			return true
	return false


func _press_button_in(node: Node, pos: Vector2) -> bool:
	for i in range(node.get_child_count() - 1, -1, -1):
		if _press_button_in(node.get_child(i), pos):
			return true
	if node is BaseButton:
		var btn := node as BaseButton
		if btn.visible and btn.is_visible_in_tree() and not btn.disabled and btn.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			if btn.get_global_rect().has_point(pos):
				btn.pressed.emit()
				return true
	return false


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
	_ground.position = Vector2(0, RR.screen_bottom() - RR.GROUND_H)
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
	_name_edit.text = GameSession.clamp_player_name(GameSession.player_name)
	_name_edit.placeholder_text = "YOUR NAME..."
	_name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_edit.max_length = GameSession.NAME_MAX_LEN
	_name_edit.position = _card_pos + NAME_BOX.position * _card_scale
	_name_edit.size = NAME_BOX.size * _card_scale
	_name_edit.caret_blink = true
	_name_edit.virtual_keyboard_enabled = true
	_name_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	_style_name(_name_edit)
	_name_edit.focus_entered.connect(GameSession.begin_virtual_keyboard_lock)
	_name_edit.focus_exited.connect(GameSession.end_virtual_keyboard_lock)
	_name_edit.text_changed.connect(_on_name_changed)
	_name_edit.text_submitted.connect(func(_t: String): _play())
	_home.add_child(_name_edit)
	_home.add_child(_hotspot(PLAY_BOX, _play, _card_pos, _card_scale))
	_home.add_child(_hotspot(SCORE_BOX, _show_scores, _card_pos, _card_scale))
	_build_fish_picker()
	_build_hat_picker()


func _build_scores() -> void:
	_score_card = _overlay_card(Sprites.tex("daily_overlay"), RR.screen_size(), Vector2.ZERO)
	_score_card.stretch_mode = TextureRect.STRETCH_SCALE
	_score_card.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_score_card.z_index = 0
	_scores.add_child(_score_card)
	_score_rows = Control.new()
	_score_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_score_rows.z_index = 8
	_score_rows.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_scores.add_child(_score_rows)
	_build_score_labels()
	_score_back = _hotspot(BACK_BOX, _show_home, Vector2.ZERO, 1.0)
	_scores.add_child(_score_back)
	_build_score_arrows()
	_layout_scores()
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


func _fish_band_bottom() -> float:
	return RR.screen_bottom() - RR.GROUND_H - 16.0


func _layout_fish_y(clip_h: float) -> float:
	var hs_bottom := _card_pos.y + (SCORE_BOX.position.y + SCORE_BOX.size.y) * _card_scale
	var gap_top := hs_bottom + 6.0
	var gap_bottom := _fish_band_bottom() - 6.0
	var row_y := gap_top + maxf(0.0, gap_bottom - gap_top - clip_h) * 0.5
	return minf(row_y, gap_bottom - clip_h)


func _hat_row_under_fish(hat_clip_h: float) -> float:
	var bottom := RR.screen_bottom()
	var hat_y := _fish_band_bottom()
	if _fish_clip:
		hat_y = _fish_clip.position.y + _fish_clip.size.y + 8.0
	return minf(hat_y, bottom - hat_clip_h - 6.0)


func _sync_menu_anchor() -> void:
	var bottom := RR.screen_bottom()
	if _ground:
		_ground.position = Vector2(0, bottom - RR.GROUND_H)
	_layout_mode_overlay()
	_layout_scores()
	if _fish_clip:
		_fish_clip.position.y = _layout_fish_y(_fish_clip.size.y)
	if _hat_clip == null:
		return
	var hat_y := _hat_row_under_fish(_hat_clip.size.y)
	var hat_delta := hat_y - _hat_clip.position.y
	_hat_clip.position.y = hat_y
	if _wallet_coin and not is_zero_approx(hat_delta):
		_wallet_rest.y += hat_delta
		_wallet_text_rest.y += hat_delta
		_wallet_coin.position.y = _wallet_rest.y
		if _wallet_text:
			_wallet_text.position.y = _wallet_text_rest.y


func _build_fish_picker() -> void:
	var count := RR.FISH_IDS.size()
	var pad := 12.0
	var cell := _fish_cell
	var gap := _fish_gap
	var icon_h := 68.0
	var price_h := 22.0
	var row_h := icon_h + price_h + 4.0
	var bob := 10.0
	var hat_room := 16.0
	# Extra room so the selection stroke stays inside the clip at both ends of the bob.
	var edge := 14.0
	var clip_h := row_h + hat_room + bob + edge * 2.0
	var row_y := _layout_fish_y(clip_h)
	_fish_clip = Control.new()
	_fish_clip.position = Vector2(pad, row_y)
	_fish_clip.size = Vector2(RR.VIEW_W - pad * 2.0, clip_h)
	_fish_clip.mouse_filter = Control.MOUSE_FILTER_STOP
	_fish_clip.clip_contents = true
	_fish_clip.z_index = 30
	_fish_clip.gui_input.connect(_on_fish_gui)
	_home.add_child(_fish_clip)
	var inner_w := 4.0 + float(count) * (cell + gap) - gap
	_fish_max_scroll = maxf(0.0, inner_w - _fish_clip.size.x)
	_fish_row = Control.new()
	_fish_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fish_row.custom_minimum_size = Vector2(inner_w, _fish_clip.size.y)
	_fish_row.size = Vector2(inner_w, _fish_clip.size.y)
	_fish_clip.add_child(_fish_row)
	_fish_order = _fish_display_order()
	for n in count:
		var fish_i := _fish_order[n]
		var x := 4.0 + float(n) * (cell + gap)
		var y := edge + hat_room + bob * 0.5
		var holder := Control.new()
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.position = Vector2(x, y)
		holder.size = Vector2(cell, row_h)
		_fish_row.add_child(holder)
		_fish_cells.append(holder)
		_fish_rest.append(holder.position)
		_fish_phase.append(float(n) * 0.37 + 0.2)
		_fish_speed.append(1.35 + fmod(float(n) * 0.17, 0.9))
		var icon_pos := Vector2(2.0, 0.0)
		var icon_size := Vector2(cell - 4.0, icon_h)
		var ring := Panel.new()
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ring.position = icon_pos - Vector2(6.0, 20.0)
		ring.size = icon_size + Vector2(12.0, 40.0)
		ring.z_index = 8
		_fish_rings.append(ring)
		holder.add_child(ring)
		var icon := TextureRect.new()
		icon.texture = Sprites.tex(RR.FISH_IDS[fish_i])
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.position = icon_pos
		icon.size = icon_size
		_fish_icons.append(icon)
		holder.add_child(icon)
		var hat := TextureRect.new()
		hat.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		hat.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hat.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.add_child(hat)
		_fish_hats.append(hat)
		var price := _make_hat_price(cell, price_h, RR.fish_price(fish_i))
		price.position = Vector2(0.0, icon_h + 1.0)
		price.visible = fish_i >= RR.FREE_FISH
		_fish_prices.append(price)
		holder.add_child(price)
		holder.move_child(ring, holder.get_child_count() - 1)
	var stride := cell + gap
	var focus_slot := 0
	for n in _fish_order.size():
		if _fish_order[n] == GameSession.fish_index:
			focus_slot = n
			break
	var focus_center := 4.0 + float(focus_slot) * stride + cell * 0.5
	_fish_scroll_x = clampf(focus_center - _fish_clip.size.x * 0.5, 0.0, _fish_max_scroll)
	_apply_fish_scroll()
	_refresh_fish_pick()


func _build_hat_picker() -> void:
	var pad := 12.0
	var cell := _hat_cell
	var gap := _hat_gap
	var icon_h := 52.0
	var price_h := 24.0
	var row_h := icon_h + price_h + 6.0
	var bob := 12.0
	var edge := 14.0
	var clip_h := row_h + bob + edge * 2.0
	var row_y := _hat_row_under_fish(clip_h)
	var wallet_w := 92.0
	_build_wallet(Vector2(pad, row_y + edge + 18.0), Vector2(wallet_w, 48.0))
	_hat_clip = Control.new()
	_hat_clip.position = Vector2(pad + wallet_w + 6.0, row_y)
	_hat_clip.size = Vector2(RR.VIEW_W - pad * 2.0 - wallet_w - 6.0, clip_h)
	_hat_clip.mouse_filter = Control.MOUSE_FILTER_STOP
	_hat_clip.clip_contents = true
	_hat_clip.z_index = 40
	_hat_clip.gui_input.connect(_on_hat_gui)
	_home.add_child(_hat_clip)
	_hat_ids = _hat_display_order()
	var count := _hat_ids.size()
	var inner_w := 4.0 + float(count) * (cell + gap) - gap
	_hat_max_scroll = maxf(0.0, inner_w - _hat_clip.size.x)
	_hat_row = Control.new()
	_hat_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hat_row.custom_minimum_size = Vector2(inner_w, clip_h)
	_hat_row.size = Vector2(inner_w, clip_h)
	_hat_clip.add_child(_hat_row)
	for n in count:
		var hat_i := _hat_ids[n]
		var x := 4.0 + float(n) * (cell + gap)
		var y := edge + bob * 0.5
		var holder := Control.new()
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.position = Vector2(x, y)
		holder.size = Vector2(cell, row_h)
		holder.z_index = 1
		_hat_row.add_child(holder)
		_hat_cells.append(holder)
		_hat_rest.append(holder.position)
		_hat_phase.append(float(n) * 0.41 + 0.18)
		_hat_speed.append(1.38 + fmod(float(n) * 0.19, 1.1))
		var icon_pos := Vector2(8.0, 2.0)
		var icon_size := Vector2(cell - 16.0, icon_h)
		var ring := Panel.new()
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ring.position = icon_pos - Vector2(4.0, 6.0)
		ring.size = icon_size + Vector2(8.0, 12.0)
		ring.z_index = 8
		_hat_rings.append(ring)
		holder.add_child(ring)
		var icon := TextureRect.new()
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.position = icon_pos
		icon.size = icon_size
		icon.z_index = 1
		if hat_i >= 0:
			icon.texture = Sprites.tex(RR.hat_id(hat_i))
		else:
			var off := SpriteTextScript.new()
			off.position = Vector2(0.0, icon_h * 0.28)
			off.configure("OFF", 14, Vector2(cell - 16.0, 22.0), HORIZONTAL_ALIGNMENT_CENTER)
			icon.add_child(off)
		_hat_icons.append(icon)
		holder.add_child(icon)
		var price := _make_hat_price(cell, price_h, 0 if hat_i < 0 else RR.hat_price(hat_i))
		price.position = Vector2(0.0, icon_h + 2.0)
		price.visible = hat_i >= 0
		price.z_index = 2
		_hat_prices.append(price)
		holder.add_child(price)
		holder.move_child(ring, holder.get_child_count() - 1)
	_refresh_hat_pick()


func _make_hat_price(cell_w: float, price_h: float, amount: int = 0) -> Control:
	var wrap := Control.new()
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.size = Vector2(cell_w, price_h)
	var coin := TextureRect.new()
	coin.texture = Sprites.tex("coin")
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin.size = Vector2(16, 16)
	coin.position = Vector2(1.0, (price_h - 16.0) * 0.5)
	wrap.add_child(coin)
	var num := SpriteTextScript.new()
	num.position = Vector2(16.0, 0.0)
	num.configure(str(amount), 14, Vector2(maxf(20.0, cell_w - 18.0), price_h), HORIZONTAL_ALIGNMENT_LEFT, true, true)
	wrap.add_child(num)
	return wrap


func _on_hat_gui(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN or mouse.button_index == MOUSE_BUTTON_WHEEL_RIGHT:
			_scroll_hats(_hat_cell + _hat_gap)
			_hat_clip.accept_event()
			return
		if mouse.button_index == MOUSE_BUTTON_WHEEL_UP or mouse.button_index == MOUSE_BUTTON_WHEEL_LEFT:
			_scroll_hats(-(_hat_cell + _hat_gap))
			_hat_clip.accept_event()
			return
		if mouse.button_index == MOUSE_BUTTON_LEFT:
			if mouse.pressed:
				_begin_hat_drag(mouse.position)
			else:
				_end_hat_drag(mouse.position)
			_hat_clip.accept_event()
			return
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _hat_pressing and (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			_move_hat_drag(motion.position)
			_hat_clip.accept_event()
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		var pos := _hat_local(touch.position)
		if touch.pressed:
			_begin_hat_drag(pos)
		else:
			_end_hat_drag(pos)
		_hat_clip.accept_event()
		return
	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_move_hat_drag(_hat_local(drag.position))
		_hat_clip.accept_event()


func _hat_local(global_pos: Vector2) -> Vector2:
	return _hat_clip.get_global_transform_with_canvas().affine_inverse() * global_pos


func _begin_hat_drag(pos: Vector2) -> void:
	_hat_pressing = true
	_hat_dragged = false
	_hat_press = pos
	_hat_press_scroll = _hat_scroll_x


func _move_hat_drag(pos: Vector2) -> void:
	if not _hat_pressing:
		return
	var dx := pos.x - _hat_press.x
	if absf(dx) > 6.0:
		_hat_dragged = true
	_hat_scroll_x = clampf(_hat_press_scroll - dx, 0.0, _hat_max_scroll)
	_apply_hat_scroll()


func _end_hat_drag(pos: Vector2) -> void:
	if not _hat_pressing:
		return
	_hat_pressing = false
	if _hat_dragged:
		return
	_click_hat_at(pos)


func _scroll_hats(delta_x: float) -> void:
	_hat_scroll_x = clampf(_hat_scroll_x + delta_x, 0.0, _hat_max_scroll)
	_apply_hat_scroll()


func _apply_hat_scroll() -> void:
	if _hat_row:
		_hat_row.position.x = -_hat_scroll_x


func _click_hat_at(pos: Vector2) -> void:
	var x := pos.x + _hat_scroll_x - 4.0
	if x < 0.0:
		return
	var stride := _hat_cell + _hat_gap
	var index := int(x / stride)
	if index < 0 or index >= _hat_ids.size():
		return
	if x - float(index) * stride > _hat_cell:
		return
	_choose_hat(_hat_ids[index])


func _build_wallet(origin: Vector2, box: Vector2) -> void:
	_wallet_coin = TextureRect.new()
	_wallet_coin.texture = Sprites.tex("coin")
	_wallet_coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_wallet_coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_wallet_coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wallet_coin.z_index = 40
	_wallet_coin.position = origin
	_wallet_coin.size = Vector2(box.y * 0.72, box.y * 0.72)
	_wallet_rest = _wallet_coin.position
	_home.add_child(_wallet_coin)
	_wallet_text = SpriteTextScript.new()
	_wallet_text.z_index = 40
	_wallet_text.position = Vector2(origin.x + _wallet_coin.size.x + 4.0, origin.y + 10.0)
	_wallet_text_rest = _wallet_text.position
	_wallet_text.configure(str(GameSession.coins), 22, Vector2(box.x - _wallet_coin.size.x, 28), HORIZONTAL_ALIGNMENT_LEFT, true)
	_home.add_child(_wallet_text)


func _refresh_wallet() -> void:
	if _wallet_text:
		_wallet_text.set_value(str(GameSession.coins))
		_wallet_text.modulate = Color.WHITE


func _flash_wallet() -> void:
	_wallet_flash = 0.7


func _hat_display_order() -> PackedInt32Array:
	return RR.hat_shop_order(GameSession.owned_hats)


func _relayout_hats() -> bool:
	var order := _hat_display_order()
	if order.size() != _hat_ids.size():
		return false
	var same := true
	for n in order.size():
		if order[n] != _hat_ids[n]:
			same = false
			break
	if same:
		return false
	var slot_of := {}
	for n in _hat_ids.size():
		slot_of[_hat_ids[n]] = n
	var ids := PackedInt32Array()
	var cells: Array[Control] = []
	var rests: Array[Vector2] = []
	var phases := PackedFloat32Array()
	var speeds := PackedFloat32Array()
	var rings: Array[Panel] = []
	var icons: Array[TextureRect] = []
	var prices: Array[Control] = []
	var stride := _hat_cell + _hat_gap
	var rest_y := _hat_rest[0].y if not _hat_rest.is_empty() else 6.0
	for n in order.size():
		var src: int = int(slot_of[order[n]])
		ids.append(order[n])
		cells.append(_hat_cells[src])
		rests.append(Vector2(4.0 + float(n) * stride, rest_y))
		phases.append(_hat_phase[src])
		speeds.append(_hat_speed[src])
		rings.append(_hat_rings[src])
		icons.append(_hat_icons[src])
		prices.append(_hat_prices[src])
		_hat_cells[src].position = rests[n]
	_hat_ids = ids
	_hat_cells = cells
	_hat_rest = rests
	_hat_phase = phases
	_hat_speed = speeds
	_hat_rings = rings
	_hat_icons = icons
	_hat_prices = prices
	return true


func _choose_hat(index: int) -> void:
	var owned_before := GameSession.owned_hats.size()
	if index < 0:
		GameSession.equip_hat(-1)
	elif GameSession.owns_hat(index):
		if GameSession.hat_index == index:
			GameSession.equip_hat(-1)
		else:
			GameSession.equip_hat(index)
	elif not GameSession.buy_hat(index):
		_flash_wallet()
		return
	if GameSession.owned_hats.size() > owned_before and _relayout_hats():
		_hat_scroll_x = 0.0
		_apply_hat_scroll()
	_refresh_wallet()
	_refresh_hat_pick()
	_refresh_fish_hats()


func _refresh_hat_pick() -> void:
	for n in _hat_icons.size():
		var hat_i := _hat_ids[n]
		var equipped := hat_i == GameSession.hat_index
		var owned := hat_i < 0 or GameSession.owns_hat(hat_i)
		var ring_style := StyleBoxFlat.new()
		ring_style.bg_color = Color(0, 0, 0, 0)
		ring_style.draw_center = false
		ring_style.set_border_width_all(3 if equipped else 0)
		ring_style.border_color = Color(1.0, 0.92, 0.42, 0.95)
		ring_style.set_corner_radius_all(14)
		_hat_rings[n].add_theme_stylebox_override("panel", ring_style)
		_hat_rings[n].z_index = 8
		if hat_i < 0:
			_hat_icons[n].modulate = Color(0.75, 0.84, 0.9, 0.55 if not equipped else 0.9)
		else:
			_hat_icons[n].modulate = Color.WHITE if owned else Color(0.78, 0.82, 0.86, 0.9)
		_hat_prices[n].visible = hat_i >= 0 and not owned


func _on_fish_gui(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN or mouse.button_index == MOUSE_BUTTON_WHEEL_RIGHT:
			_scroll_fish(_fish_cell + _fish_gap)
			_fish_clip.accept_event()
			return
		if mouse.button_index == MOUSE_BUTTON_WHEEL_UP or mouse.button_index == MOUSE_BUTTON_WHEEL_LEFT:
			_scroll_fish(-(_fish_cell + _fish_gap))
			_fish_clip.accept_event()
			return
		if mouse.button_index == MOUSE_BUTTON_LEFT:
			if mouse.pressed:
				_begin_fish_drag(mouse.position)
			else:
				_end_fish_drag(mouse.position)
			_fish_clip.accept_event()
			return
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _fish_pressing and (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			_move_fish_drag(motion.position)
			_fish_clip.accept_event()
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		var pos := _fish_local(touch.position)
		if touch.pressed:
			_begin_fish_drag(pos)
		else:
			_end_fish_drag(pos)
		_fish_clip.accept_event()
		return
	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_move_fish_drag(_fish_local(drag.position))
		_fish_clip.accept_event()


func _fish_local(global_pos: Vector2) -> Vector2:
	return _fish_clip.get_global_transform_with_canvas().affine_inverse() * global_pos


func _begin_fish_drag(pos: Vector2) -> void:
	_fish_pressing = true
	_fish_dragged = false
	_fish_press = pos
	_fish_press_scroll = _fish_scroll_x


func _move_fish_drag(pos: Vector2) -> void:
	if not _fish_pressing:
		return
	var dx := pos.x - _fish_press.x
	if absf(dx) > 6.0:
		_fish_dragged = true
	_fish_scroll_x = clampf(_fish_press_scroll - dx, 0.0, _fish_max_scroll)
	_apply_fish_scroll()


func _end_fish_drag(pos: Vector2) -> void:
	if not _fish_pressing:
		return
	_fish_pressing = false
	if _fish_dragged:
		return
	_click_fish_at(pos)


func _scroll_fish(delta_x: float) -> void:
	_fish_scroll_x = clampf(_fish_scroll_x + delta_x, 0.0, _fish_max_scroll)
	_apply_fish_scroll()


func _apply_fish_scroll() -> void:
	if _fish_row:
		_fish_row.position.x = -_fish_scroll_x


func _click_fish_at(pos: Vector2) -> void:
	var x := pos.x + _fish_scroll_x - 4.0
	if x < 0.0:
		return
	var stride := _fish_cell + _fish_gap
	var index := int(x / stride)
	if index < 0 or index >= RR.FISH_IDS.size():
		return
	if x - float(index) * stride > _fish_cell:
		return
	_choose_fish(_fish_order[index])


func _choose_fish(index: int) -> void:
	var owned_before := GameSession.owned_fish.size()
	if not GameSession.buy_fish(index):
		_flash_wallet()
		return
	if GameSession.owned_fish.size() > owned_before and _relayout_fish():
		_fish_scroll_x = 0.0
		_apply_fish_scroll()
	_refresh_wallet()
	_refresh_fish_pick()
	_refresh_fish_hats()


func _fish_display_order() -> PackedInt32Array:
	return RR.fish_shop_order(GameSession.owned_fish)


func _relayout_fish() -> bool:
	var order := _fish_display_order()
	if order.size() != _fish_order.size():
		return false
	var same := true
	for n in order.size():
		if order[n] != _fish_order[n]:
			same = false
			break
	if same:
		return false
	var slot_of := {}
	for n in _fish_order.size():
		slot_of[_fish_order[n]] = n
	var ids := PackedInt32Array()
	var cells: Array[Control] = []
	var rests: Array[Vector2] = []
	var phases := PackedFloat32Array()
	var speeds := PackedFloat32Array()
	var rings: Array[Panel] = []
	var icons: Array[TextureRect] = []
	var hats: Array[TextureRect] = []
	var prices: Array[Control] = []
	var stride := _fish_cell + _fish_gap
	var rest_y := _fish_rest[0].y if not _fish_rest.is_empty() else 16.0
	for n in order.size():
		var src: int = int(slot_of[order[n]])
		ids.append(order[n])
		cells.append(_fish_cells[src])
		rests.append(Vector2(4.0 + float(n) * stride, rest_y))
		phases.append(_fish_phase[src])
		speeds.append(_fish_speed[src])
		rings.append(_fish_rings[src])
		icons.append(_fish_icons[src])
		hats.append(_fish_hats[src])
		prices.append(_fish_prices[src])
		_fish_cells[src].position = rests[n]
	_fish_order = ids
	_fish_cells = cells
	_fish_rest = rests
	_fish_phase = phases
	_fish_speed = speeds
	_fish_rings = rings
	_fish_icons = icons
	_fish_hats = hats
	_fish_prices = prices
	return true


func _refresh_fish_pick() -> void:
	var chosen := clampi(GameSession.fish_index, 0, RR.FISH_IDS.size() - 1)
	for i in _fish_icons.size():
		var fish_i := _fish_order[i]
		var owned := GameSession.owns_fish(fish_i)
		var on := fish_i == chosen and owned
		var ring_style := StyleBoxFlat.new()
		ring_style.bg_color = Color(0.12, 0.42, 0.62, 0.22 if on else 0.0)
		ring_style.set_border_width_all(3 if on else 0)
		ring_style.border_color = Color(1.0, 0.92, 0.42, 0.95)
		ring_style.set_corner_radius_all(18)
		_fish_rings[i].add_theme_stylebox_override("panel", ring_style)
		if on:
			_fish_icons[i].modulate = Color.WHITE
		elif owned:
			_fish_icons[i].modulate = Color(0.82, 0.88, 0.92, 0.78)
		else:
			_fish_icons[i].modulate = Color(0.55, 0.62, 0.7, 0.9)
		_fish_icons[i].scale = Vector2.ONE
		var grow := 1.08 if on else 1.0
		_fish_icons[i].pivot_offset = _fish_icons[i].size * 0.5
		_fish_icons[i].scale = Vector2(grow, grow)
		if i < _fish_prices.size():
			_fish_prices[i].visible = not owned
	_refresh_fish_hats()


func _refresh_fish_hats() -> void:
	var equipped := GameSession.hat_index
	var hat_tex: Texture2D = null
	if equipped >= 0 and equipped < RR.HAT_COUNT:
		hat_tex = Sprites.tex(RR.hat_id(equipped))
	for i in _fish_hats.size():
		var hat := _fish_hats[i]
		hat.texture = hat_tex
		hat.visible = hat_tex != null
		if hat_tex == null:
			continue
		_place_hat_on_fish(hat, RR.FISH_IDS[_fish_order[i]], _fish_icons[i].size)


func _place_hat_on_fish(hat: TextureRect, skin: String, box: Vector2) -> void:
	var hat_tex := hat.texture
	if hat_tex == null:
		return
	var fish_tex := Sprites.tex(skin)
	var fish_size := Vector2(64.0, 64.0)
	if fish_tex:
		fish_size = fish_tex.get_size()
	# Same scale KEEP_ASPECT_CENTERED uses on the fish icon.
	var k := minf(box.x / maxf(fish_size.x, 1.0), box.y / maxf(fish_size.y, 1.0))
	var hat_scale := RR.HAT_SCALE * k / RR.FISH_SCALE
	var hat_size := hat_tex.get_size() * hat_scale
	hat.size = hat_size
	# Sprite2D path: origin at hat_anchor, then brim offset * hat scale.
	var sit := box * 0.5 + RR.hat_anchor(skin, fish_size) * k + RR.hat_brim_offset(hat_tex) * hat_scale
	hat.position = sit - hat_size * 0.5 + Vector2(0.0, 3.0)


func _bob_picker(delta: float) -> void:
	_bob_t += delta
	for i in _fish_cells.size():
		var y := sin(_bob_t * _fish_speed[i] + _fish_phase[i]) * 8.0
		_fish_cells[i].position = _fish_rest[i] + Vector2(0.0, y)
	for i in _hat_cells.size():
		var y := sin(_bob_t * _hat_speed[i] + _hat_phase[i]) * 8.0
		_hat_cells[i].position = _hat_rest[i] + Vector2(0.0, y)
	if _wallet_coin:
		var wy := sin(_bob_t * _wallet_speed + _wallet_phase) * 8.0
		_wallet_coin.position = _wallet_rest + Vector2(0.0, wy)
		if _wallet_text:
			_wallet_text.position = _wallet_text_rest + Vector2(0.0, wy)


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
	edit.add_theme_font_size_override("font_size", maxi(18, int(round(NAME_BOX.size.y * _card_scale * 0.42))))


func _on_name_changed(value: String) -> void:
	GameSession.player_name = GameSession.clamp_player_name(value)
	GameSession._save()


func _show_scores() -> void:
	_on_name_changed(_name_edit.text)
	_score_page = 0
	_score_swiping = false
	GameSession.refresh_boards()
	_fill_scores()
	_home.visible = false
	_scores.visible = true
	if _ground:
		_ground.visible = false
	var backend := get_node_or_null("/root/Backend")
	if backend and backend.has_method("fetch_leaderboards"):
		if backend.has_signal("leaderboards_ready") and not backend.leaderboards_ready.is_connected(_fill_scores):
			backend.leaderboards_ready.connect(_fill_scores)
		backend.fetch_leaderboards()


func _fill_scores() -> void:
	var period: String = SCORE_PAGES[_score_page]
	if _score_card:
		var tex := Sprites.tex("%s_overlay" % period)
		if tex:
			_score_card.texture = tex
	var board := _global_board(period)
	var populated := 0
	var first_name := ""
	var first_score := ""
	for i in _score_names.size():
		var name := ""
		var score := ""
		if i < board.size() and typeof(board[i]) == TYPE_DICTIONARY:
			var row: Dictionary = board[i]
			name = GameSession.clamp_player_name(str(row.get("name", row.get("display_name", "")))).to_upper()
			if name == "<NULL>" or name == "NULL":
				name = ""
			var value := int(row.get("score", 0))
			if value > 0:
				score = str(value)
			if name != "" or score != "":
				populated += 1
				if first_name == "" and first_score == "":
					first_name = name
					first_score = score
		if i < _score_names.size():
			_score_names[i].set_value(name)
		if i < _score_values.size():
			_score_values[i].set_value(score)
	_sync_score_status(period, board.size())
	print("[leaderboard] ui period=%s rows=%d labels=%d first=%s score=%s" % [period, board.size(), populated, first_name, first_score])


func _global_board(period: String) -> Array:
	var backend := get_node_or_null("/root/Backend")
	if backend == null:
		return []
	var raw: Variant = null
	if period == "daily":
		raw = backend.get("global_daily")
	elif period == "weekly":
		raw = backend.get("global_weekly")
	else:
		raw = backend.get("global_monthly")
	if raw is Array:
		return raw
	return []


func _score_swipe_input(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if _score_back_hit(touch.position) or _score_arrow_hit(touch.position):
				return false
			_begin_score_swipe(touch.position)
			return true
		if _score_swiping:
			_end_score_swipe(touch.position)
			return true
		return false
	if event is InputEventScreenDrag and _score_swiping:
		_mark_input_handled()
		return true
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mouse := event as InputEventMouseButton
		if mouse.pressed:
			if _score_back_hit(mouse.position) or _score_arrow_hit(mouse.position):
				return false
			_begin_score_swipe(mouse.position)
			return true
		if _score_swiping:
			_end_score_swipe(mouse.position)
			return true
		return false
	if event is InputEventMouseMotion and _score_swiping:
		_mark_input_handled()
		return true
	return false


func _begin_score_swipe(pos: Vector2) -> void:
	_score_press = pos
	_score_swiping = true
	_mark_input_handled()


func _end_score_swipe(pos: Vector2) -> void:
	_score_swiping = false
	_mark_input_handled()
	var dx := pos.x - _score_press.x
	if absf(dx) < SWIPE_MIN:
		return
	_cycle_score_page(-1 if dx > 0.0 else 1)


func _cycle_score_page(dir: int) -> void:
	_score_page = posmod(_score_page + dir, SCORE_PAGES.size())
	print("[leaderboard] ui period=%s" % SCORE_PAGES[_score_page])
	_fill_scores()
	var backend := get_node_or_null("/root/Backend")
	if backend and backend.has_method("fetch_leaderboards"):
		backend.fetch_leaderboards()


func _score_back_hit(pos: Vector2) -> bool:
	return _score_art_rect(BACK_BOX).has_point(pos)


func _score_art_rect(src: Rect2) -> Rect2:
	return Rect2(src.position * _score_scale, src.size * _score_scale)


func _layout_scores() -> void:
	if _score_card == null:
		return
	var screen := RR.screen_size()
	_score_scale = Vector2(screen.x / SCORE_W, screen.y / SCORE_H)
	_score_pos = Vector2.ZERO
	_score_card.position = Vector2.ZERO
	_score_card.size = screen
	if _score_back:
		var back := _score_art_rect(BACK_BOX)
		_score_back.position = back.position
		_score_back.size = back.size
	var glyph_h := _score_glyph_height()
	var name_h := _score_name_height()
	for i in _score_names.size():
		_place_score_line(_score_names[i], _row_content_rect(i, SCORE_NAME_X, SCORE_NAME_W, 2.0), name_h)
		_place_score_line(_score_values[i], _row_content_rect(i, SCORE_VALUE_X, SCORE_VALUE_W), glyph_h)
	if _score_status:
		_place_score_line(_score_status, Rect2(210.0, 352.0, 520.0, 68.0), 0.0)
	_layout_score_arrows()


func _place_score_line(line: SpriteTextScript, src: Rect2, glyph_h: float) -> void:
	if line == null:
		return
	var box := Vector2(src.size.x * _score_scale.x, src.size.y * _score_scale.y)
	line.position = src.position * _score_scale
	var height := glyph_h if glyph_h > 0.0 else box.y * 0.92
	line.resize_box(height, box)


func _score_arrow_hit(pos: Vector2) -> bool:
	return _score_arrow_left_rect.has_point(pos) or _score_arrow_right_rect.has_point(pos)


func _build_score_arrows() -> void:
	var size := Vector2(ARROW_BOX, ARROW_BOX)
	var back := _score_art_rect(BACK_BOX)
	var y := back.position.y + (back.size.y - size.y) * 0.5
	var left := Rect2(4.0, y, size.x, size.y)
	var right := Rect2(RR.screen_size().x - 4.0 - size.x, y, size.x, size.y)
	_score_arrow_left_rect = left.grow(6.0)
	_score_arrow_right_rect = right.grow(6.0)
	_score_arrow_left_icon = _score_arrow_icon("btn_score_left", left)
	_score_arrow_right_icon = _score_arrow_icon("btn_score_right", right)
	_score_arrow_left_btn = _screen_hotspot(_score_arrow_left_rect, _cycle_score_page.bind(-1))
	_score_arrow_right_btn = _screen_hotspot(_score_arrow_right_rect, _cycle_score_page.bind(1))
	_scores.add_child(_score_arrow_left_btn)
	_scores.add_child(_score_arrow_right_btn)


func _layout_score_arrows() -> void:
	if _score_arrow_left_icon == null:
		return
	var size := Vector2(ARROW_BOX, ARROW_BOX)
	var back := _score_art_rect(BACK_BOX)
	var y := back.position.y + (back.size.y - size.y) * 0.5
	var left := Rect2(4.0, y, size.x, size.y)
	var right := Rect2(RR.screen_size().x - 4.0 - size.x, y, size.x, size.y)
	_score_arrow_left_rect = left.grow(6.0)
	_score_arrow_right_rect = right.grow(6.0)
	_place_score_arrow(_score_arrow_left_icon, _score_arrow_left_btn, left, _score_arrow_left_rect)
	_place_score_arrow(_score_arrow_right_icon, _score_arrow_right_btn, right, _score_arrow_right_rect)


func _place_score_arrow(icon: TextureRect, button: Button, box: Rect2, hit: Rect2) -> void:
	if icon:
		icon.position = box.position
		icon.size = box.size
	if button:
		button.position = hit.position
		button.size = hit.size


func _score_arrow_icon(id: String, box: Rect2) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = Sprites.tex(id)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.position = box.position
	icon.size = box.size
	_scores.add_child(icon)
	return icon


func _screen_hotspot(box: Rect2, pressed: Callable) -> Button:
	var btn := Button.new()
	btn.flat = true
	btn.position = box.position
	btn.size = box.size
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.pressed.connect(pressed)
	return btn


func _build_score_labels() -> void:
	_score_names.clear()
	_score_values.clear()
	var glyph_h := _score_glyph_height()
	var name_h := _score_name_height()
	for i in SCORE_ROWS_Y.size():
		_score_names.append(_add_score_text(_row_content_rect(i, SCORE_NAME_X, SCORE_NAME_W, 2.0), HORIZONTAL_ALIGNMENT_LEFT, false, name_h, true))
		_score_values.append(_add_score_text(_row_content_rect(i, SCORE_VALUE_X, SCORE_VALUE_W), HORIZONTAL_ALIGNMENT_RIGHT, true, glyph_h, true))
	_score_status = _add_score_text(Rect2(210.0, 352.0, 520.0, 68.0), HORIZONTAL_ALIGNMENT_CENTER, false, 0.0, true)
	_score_status.visible = false


func _score_glyph_height() -> float:
	var row_h: float = SCORE_ROWS_H[0]
	for raw in SCORE_ROWS_H:
		row_h = minf(row_h, float(raw))
	# Kept under the row height so a three-digit score still fits the column.
	return row_h * _score_scale.y * 0.54


func _score_name_height() -> float:
	var row_h: float = SCORE_ROWS_H[0]
	for raw in SCORE_ROWS_H:
		row_h = minf(row_h, float(raw))
	# The row width is what actually sets the size. A wide name shrinks to the column.
	return row_h * _score_scale.y


func _row_content_rect(index: int, x: float, width: float, inset: float = 10.0) -> Rect2:
	var y: float = SCORE_ROWS_Y[index]
	var h: float = SCORE_ROWS_H[index]
	return Rect2(x, y + inset, width, maxf(24.0, h - inset * 2.0))


func _add_score_text(src: Rect2, align: HorizontalAlignment, gold_digits: bool, glyph_h: float, fit_box: bool) -> SpriteTextScript:
	var line := SpriteTextScript.new()
	line.z_index = 2
	var box := Vector2(src.size.x * _score_scale.x, src.size.y * _score_scale.y)
	line.position = _score_pos + src.position * _score_scale
	var height := glyph_h if glyph_h > 0.0 else box.y * 0.92
	line.configure("", height, box, align, gold_digits, fit_box)
	if not fit_box:
		line.clip_contents = true
	_score_rows.add_child(line)
	return line


func _sync_score_status(period: String, row_count: int) -> void:
	if _score_status == null:
		return
	var note := ""
	if row_count <= 0:
		var backend := get_node_or_null("/root/Backend")
		var meta: Dictionary = {}
		if backend and backend.get("leaderboard_meta") is Dictionary:
			var all: Dictionary = backend.leaderboard_meta
			var got: Variant = all.get(period, {})
			if typeof(got) == TYPE_DICTIONARY:
				meta = got
		var busy: bool = backend != null and backend.has_method("leaderboard_busy") and backend.leaderboard_busy()
		if meta.is_empty() or busy:
			note = "LOADING"
		elif not bool(meta.get("ok", false)):
			note = "COULD NOT LOAD"
	_score_status.set_value(note)
	_score_status.visible = note != ""


func _show_home() -> void:
	_score_swiping = false
	_scores.visible = false
	_home.visible = true
	if _ground:
		_ground.visible = true


func _play() -> void:
	if _name_edit:
		_on_name_changed(_name_edit.text)
		_name_edit.release_focus()
	GameSession.end_virtual_keyboard_lock()
	_open_modes()


func _build_mode_overlay() -> void:
	_modes = Control.new()
	_modes.visible = false
	_modes.z_index = 80
	_modes.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_modes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_modes)
	var dim := ColorRect.new()
	dim.color = Palette.SHADOW
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_modes.add_child(dim)
	_mode_card = _overlay_card(Sprites.tex("mode_unlocked"), Vector2(MODE_W, MODE_H), Vector2.ZERO)
	_mode_card.stretch_mode = TextureRect.STRETCH_SCALE
	_mode_card.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_modes.add_child(_mode_card)
	_mode_reset_cover = _mode_cover()
	_modes.add_child(_mode_reset_cover)
	_mode_unlimited = _hotspot(MODE_UNLIMITED, _choose_unlimited, Vector2.ZERO, 1.0)
	var daily := _hotspot(MODE_DAILY, _choose_daily, Vector2.ZERO, 1.0)
	_mode_back = _hotspot(MODE_BACK, _close_modes, Vector2.ZERO, 1.0)
	_mission_button = _hotspot(MODE_MISSIONS, _open_missions, Vector2.ZERO, 1.0)
	for btn in [_mode_unlimited, daily, _mode_back, _mission_button]:
		btn.focus_mode = Control.FOCUS_NONE
		_modes.add_child(btn)
	_daily_button = daily
	_mode_note = SpriteTextScript.new()
	_mode_note.modulate = Palette.GOLD
	_mode_note.visible = false
	_mode_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modes.add_child(_mode_note)
	_mode_reset = SpriteTextScript.new()
	_mode_reset.modulate = Palette.SAND
	_mode_reset.visible = false
	_mode_reset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modes.add_child(_mode_reset)
	_layout_mode_overlay()


func _open_missions() -> void:
	if _missions == null:
		return
	_modes_return = _modes != null and _modes.visible
	if _modes:
		_modes.visible = false
	_missions.refresh_from_session()
	_missions.present("board", true)
	var backend := get_node_or_null("/root/Backend")
	if backend and backend.has_method("refresh_daily_missions"):
		backend.refresh_daily_missions()


func _close_missions() -> void:
	if _missions:
		_missions.present("hidden")
	if _modes_return and _modes:
		_modes.visible = true
	_modes_return = false


func _on_menu_missions() -> void:
	if _missions and _missions.mode() == "board":
		_missions.refresh_from_session()


func _layout_mode_overlay() -> void:
	if _mode_card == null or _modes == null:
		return
	var screen := RR.screen_size()
	_mode_scale = Vector2(screen.x / MODE_W, screen.y / MODE_H)
	_mode_origin = Vector2.ZERO
	_mode_card.position = Vector2.ZERO
	_mode_card.size = screen
	_place_hotspot(_mode_unlimited, MODE_UNLIMITED)
	_place_hotspot(_daily_button, MODE_DAILY)
	_place_hotspot(_mission_button, MODE_MISSIONS)
	_place_hotspot(_mode_back, MODE_BACK)
	_layout_mode_status()


func _place_hotspot(btn: Button, src: Rect2) -> void:
	if btn == null:
		return
	btn.position = _mode_origin + src.position * _mode_scale
	btn.size = src.size * _mode_scale


func _mode_cover() -> Panel:
	var cover := Panel.new()
	cover.visible = false
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = Color8(22, 53, 73)
	box.set_corner_radius_all(10)
	cover.add_theme_stylebox_override("panel", box)
	return cover


func _mode_view_rect(src: Rect2) -> Rect2:
	return Rect2(_mode_origin + src.position * _mode_scale, src.size * _mode_scale)


func _layout_mode_status() -> void:
	_apply_mode_art()
	var line := _mode_view_rect(MODE_RESET_LINE)
	if _mode_reset_cover:
		_mode_reset_cover.position = line.position
		_mode_reset_cover.size = line.size
		_mode_reset_cover.visible = _mode_shows_locked() and _mode_reset != null and _mode_reset.visible


func _mode_shows_locked() -> bool:
	if DailyTestModeScript.enabled():
		return false
	return _daily_locked


func _apply_mode_art() -> void:
	if _mode_card == null:
		return
	var tex := Sprites.tex("mode_locked" if _mode_shows_locked() else "mode_unlocked")
	if tex:
		_mode_card.texture = tex


func _open_modes() -> void:
	if _modes == null:
		return
	_mode_busy = false
	_modes.visible = true
	if _daily_locked:
		_show_daily_completed(_daily_resets_unix)
	else:
		_set_mode_note("")
		_set_mode_reset("")
	_layout_mode_overlay()
	_refresh_daily_status()


func _close_modes() -> void:
	_mode_token += 1
	_mode_busy = false
	_modes_return = false
	if _modes:
		_modes.visible = false
	_close_missions()
	_set_mode_note("")
	_set_mode_reset("")
	var backend := get_node_or_null("/root/Backend")
	if backend and backend.has_method("cancel_pre_match_requests"):
		backend.cancel_pre_match_requests()


func _set_mode_note(text: String) -> void:
	if _mode_note == null:
		return
	# Locked art already paints the completed line. Errors stay on the open card.
	var show := text != "" and not (_mode_shows_locked() and text == DailyAttemptScript.COMPLETED_LABEL)
	_mode_note.visible = show
	if show:
		var note := _mode_view_rect(MODE_NOTE)
		_mode_note.position = note.position
		_mode_note.configure(text, 16.0, note.size, HORIZONTAL_ALIGNMENT_CENTER, false, true)
	_layout_mode_status()


func _set_mode_reset(text: String) -> void:
	if _mode_reset == null:
		return
	var show := text != "" and _mode_shows_locked()
	_mode_reset.visible = show
	if show:
		var line := _mode_view_rect(MODE_RESET_LINE)
		_mode_reset.position = line.position
		_mode_reset.configure(text, 14.0, line.size, HORIZONTAL_ALIGNMENT_CENTER, false, true)
	_layout_mode_status()


func _on_identity_ready() -> void:
	if _modes and _modes.visible:
		_refresh_daily_status()


func _show_daily_completed(resets_unix: int) -> void:
	_daily_locked = true
	_daily_checking = false
	_daily_resets_unix = resets_unix
	if DailyTestModeScript.enabled():
		_apply_daily_test_override()
		return
	if _daily_button:
		_daily_button.disabled = true
		_daily_button.modulate = Color(1, 1, 1, 0.45)
	_set_mode_note(DailyAttemptScript.COMPLETED_LABEL)
	_set_mode_reset(DailyAttemptScript.reset_label(resets_unix, int(Time.get_unix_time_from_system())))


func _clear_daily_lock() -> void:
	_daily_locked = false
	_daily_checking = false
	_daily_resets_unix = 0
	if _daily_button:
		_daily_button.disabled = false
		_daily_button.modulate = Color.WHITE
	if _modes and _modes.visible and not _mode_busy:
		_set_mode_note("")
		_set_mode_reset("")
	if DailyTestModeScript.enabled():
		_apply_daily_test_override()


func _refresh_daily_status() -> void:
	if _status_busy:
		_status_again = true
		return
	if _mode_busy:
		return
	var backend := get_node_or_null("/root/Backend")
	if backend == null or not backend.has_method("fetch_daily_attempt_status"):
		print("[daily] status_ui skipped error=no_backend")
		return
	if not backend.has_method("has_session") or not backend.has_session():
		print("[daily] status_ui skipped error=no_session button_disabled=%s" % str(_daily_button != null and _daily_button.disabled))
		return
	_status_busy = true
	_daily_checking = true
	if _daily_button and not _daily_locked and not DailyTestModeScript.enabled():
		_daily_button.disabled = true
	var token := _mode_token
	var status: Dictionary = await backend.fetch_daily_attempt_status()
	_status_busy = false
	if _status_again:
		_status_again = false
		_daily_checking = false
		_refresh_daily_status()
		return
	if not is_inside_tree() or token != _mode_token or _modes == null or not _modes.visible:
		_daily_checking = false
		return
	var course: Variant = status.get("course", {})
	if typeof(course) == TYPE_DICTIONARY and int(course.get("course_seed", 0)) != 0:
		_status_course = course
	if status.get("attempted", false):
		_show_daily_completed(int(status.get("resets_at_unix", 0)))
	elif status.get("ok", false):
		_clear_daily_lock()
	else:
		_daily_checking = false
		if _daily_button and not _daily_locked and not DailyTestModeScript.enabled():
			_daily_button.disabled = false
			if int(status.get("status", 0)) == 404:
				_set_mode_note("DAILY UNAVAILABLE")
	if DailyTestModeScript.enabled():
		_apply_daily_test_override()
	print("[daily] status_ui status=%d ok=%s attempted=%s error=%s button_disabled=%s test_mode=%s" % [
		int(status.get("status", 0)),
		str(bool(status.get("ok", false))),
		str(bool(status.get("attempted", false))),
		str(status.get("error", "")),
		str(_daily_button != null and _daily_button.disabled),
		DailyTestModeScript.status_label(),
	])


func _daily_backend_ready() -> bool:
	var backend := get_node_or_null("/root/Backend")
	if backend == null:
		return false
	return (
		backend.has_method("daily_challenge_ready")
		and backend.daily_challenge_ready()
		and backend.has_method("claim_daily_attempt")
		and backend.has_method("prepare_claimed_daily")
		and backend.has_method("start_daily_attempt")
		and backend.has_method("finalize_daily_attempt")
	)


func _apply_daily_test_override() -> void:
	if not DailyTestModeScript.enabled():
		return
	if _daily_button:
		_daily_button.disabled = false
		_daily_button.modulate = Color.WHITE
	_set_mode_note("")
	_set_mode_reset("")


func _start_practice_daily() -> void:
	if not DailyTestModeScript.enabled() or _mode_busy:
		return
	_mode_busy = true
	_mode_token += 1
	var token := _mode_token
	if _name_edit:
		_on_name_changed(_name_edit.text)
	var course := DailyTestModeScript.practice_course(_status_course)
	if int(course.get("course_seed", 0)) == 0:
		var backend := get_node_or_null("/root/Backend")
		if backend and backend.has_method("fetch_practice_course"):
			course = await backend.fetch_practice_course()
	if not is_inside_tree() or token != _mode_token:
		_mode_busy = false
		return
	if not GameSession.begin_practice_daily(course):
		_mode_busy = false
		_set_mode_note("PRACTICE COURSE UNAVAILABLE")
		return
	print("[daily] practice seed=%d id=%s" % [GameSession.course_seed, GameSession.current_challenge_id()])
	get_tree().change_scene_to_file.call_deferred("res://scenes/game/game.tscn")


func _choose_unlimited() -> void:
	if _mode_busy:
		return
	_begin_game(GameSession.MODE_UNLIMITED)


func _choose_daily() -> void:
	if DailyTestModeScript.enabled():
		_start_practice_daily()
		return
	if _mode_busy or _daily_checking:
		print("[daily] choose blocked busy=%s checking=%s button_disabled=%s" % [
			str(_mode_busy),
			str(_daily_checking),
			str(_daily_button != null and _daily_button.disabled),
		])
		return
	if _daily_locked:
		print("[daily] choose blocked locked=true")
		_show_daily_completed(_daily_resets_unix)
		return
	if not _daily_backend_ready():
		print("[daily] choose blocked error=backend_not_ready")
		_set_mode_note("UNAVAILABLE UNTIL INTEGRATION IS COMPLETE")
		return
	_mode_busy = true
	_mode_token += 1
	var token := _mode_token
	_set_mode_note("LOADING")
	_set_mode_reset("")
	var backend := get_node_or_null("/root/Backend")
	var claim: Dictionary = {}
	if backend:
		claim = await backend.claim_daily_attempt()
	if not is_inside_tree() or token != _mode_token or _modes == null or not _modes.visible:
		if claim.get("already_used", false):
			_daily_locked = true
			_daily_resets_unix = int(claim.get("resets_at_unix", 0))
		_mode_busy = false
		return
	if not claim.get("ok", false):
		_mode_busy = false
		print("[daily] choose claim_failed status=%d already_used=%s error=%s" % [
			int(claim.get("status", 0)),
			str(bool(claim.get("already_used", false))),
			str(claim.get("error", "")),
		])
		if claim.get("already_used", false):
			_show_daily_completed(int(claim.get("resets_at_unix", 0)))
		elif int(claim.get("status", 0)) == 404:
			_set_mode_note("DAILY UNAVAILABLE")
		else:
			_set_mode_note("COULD NOT START DAILY CHALLENGE")
		return
	var challenge: Dictionary = claim.get("challenge", {})
	_set_mode_note("LOADING")
	if backend:
		await backend.prepare_claimed_daily(challenge)
	if not is_inside_tree() or token != _mode_token or _modes == null or not _modes.visible:
		_mode_busy = false
		return
	var started: Dictionary = {}
	if backend:
		started = await backend.start_daily_attempt(str(challenge.get("attempt_id", "")))
	if not is_inside_tree() or token != _mode_token or _modes == null or not _modes.visible:
		_mode_busy = false
		return
	if not bool(started.get("started", false)):
		_mode_busy = false
		print("[daily] choose start_failed attempt_id=%s status=%d already_started=%s error=%s" % [
			str(challenge.get("attempt_id", "")),
			int(started.get("status", 0)),
			str(bool(started.get("already_started", false))),
			str(started.get("error", "")),
		])
		if bool(started.get("already_started", false)):
			_show_daily_completed(int(claim.get("resets_at_unix", 0)))
		elif int(started.get("status", 0)) == 404:
			_set_mode_note("DAILY UNAVAILABLE")
		else:
			_set_mode_note("COULD NOT START DAILY CHALLENGE")
		return
	print("[daily] choose enter_game attempt_id=%s seed=%d" % [
		str(challenge.get("attempt_id", "")),
		int(challenge.get("course_seed", 0)),
	])
	_begin_claimed_game(challenge)


func _begin_claimed_game(challenge: Dictionary) -> void:
	if str(challenge.get("attempt_id", "")).strip_edges() == "":
		_mode_busy = false
		print("[daily] choose enter_game error=missing_attempt")
		_set_mode_note("COULD NOT START DAILY CHALLENGE")
		return
	if _name_edit:
		_on_name_changed(_name_edit.text)
	GameSession.begin_claimed_daily(challenge)
	get_tree().change_scene_to_file.call_deferred("res://scenes/game/game.tscn")


func _begin_game(mode: String) -> void:
	if _name_edit:
		_on_name_changed(_name_edit.text)
	GameSession.start_match(mode)
	get_tree().change_scene_to_file.call_deferred("res://scenes/game/game.tscn")
