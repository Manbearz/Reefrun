extends Control

const SpriteTextScript := preload("res://scripts/sprite_text.gd")
const ButtonFeedbackScript := preload("res://scripts/button_feedback.gd")
const DailyAttemptScript := preload("res://scripts/daily_attempt.gd")
const DailyTestModeScript := preload("res://scripts/daily_test_mode.gd")
const OVERLAY_W := 1145.0
const OVERLAY_H := 1374.0
const SCORE_W := 941.0
const SCORE_H := 1672.0
const NAME_BOX := Rect2(270, 742, 590, 82)
const PLAY_BOX := Rect2(250, 900, 640, 185)
const SCORE_BOX := Rect2(210, 1124, 730, 168)
const SCORE_PLATE := Rect2(218, 1132, 714, 152)
const BACK_BOX := Rect2(230, 1478, 480, 140)
const BACK_PLATE := Rect2(297, 1487, 370, 126)
# Painted Back control, including its dark outline. The wood fill alone sits inside this.
const BACK_VISUAL := Rect2(279, 1469, 406, 160)
# Ranks through the Back button. Covering a taller screen would crop this.
const SCORE_KEEP := Rect2(8, 80, 925, 1560)
# Header artwork through the Back button. A 16:9 screen cannot cover this
# without cropping, so that screen fills instead.
const MODE_KEEP := Rect2(16, 220, 784, 1610)
# Inner light-blue bars on the 941-wide scoreboard art, to the right of the painted ranks.
const SCORE_ROWS_Y := [427.0, 531.0, 635.0, 739.0, 843.0, 947.0, 1052.0, 1157.0, 1261.0, 1361.0]
const SCORE_ROWS_H := [88.0, 87.0, 87.0, 87.0, 88.0, 88.0, 88.0, 87.0, 83.0, 85.0]
# The painted rank badge ends near art x 214. Names start inside the blue bar,
# with a gap after that badge. The box stops before a three-digit score.
const SCORE_NAME_X := 260.0
const SCORE_NAME_W := 314.0
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
const DAILY_FISH_SIZE := 56.0
const DAILY_FISH_GAP := 12.0
const DAILY_FISH_SHADER := "shader_type canvas_item;\nvoid fragment() {\n\tvec4 c = texture(TEXTURE, UV);\n\tfloat g = dot(c.rgb, vec3(0.299, 0.587, 0.114));\n\tCOLOR = vec4(vec3(g), c.a);\n}\n"
const SWIPE_MIN := 48.0
const ARROW_BOX := 96.0
const CAROUSEL_SLIDE_SEC := 0.22

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
var _arrow_opaque: Dictionary = {}
var _name_edit: LineEdit
var _lobby_bg: TextureRect
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
var _fish_scroll_visual := 0.0
var _fish_slide_from := 0.0
var _fish_slide_to := 0.0
var _fish_slide_t := 1.0
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
var _hat_scroll_visual := 0.0
var _hat_slide_from := 0.0
var _hat_slide_to := 0.0
var _hat_slide_t := 1.0
var _hat_max_scroll := 0.0
var _fish_ring_on: StyleBoxFlat
var _fish_ring_off: StyleBoxFlat
var _hat_ring_on: StyleBoxFlat
var _hat_ring_off: StyleBoxFlat
var _shown_menu_hat := -999
var _hat_cell := 68.0
var _hat_gap := 8.0
var _hat_pressing := false
var _hat_dragged := false
var _hat_press := Vector2.ZERO
var _hat_press_scroll := 0.0
var _wallet_coin: TextureRect
var _wallet_text: SpriteTextScript
var _best_row: Control
var _best_crown: TextureRect
var _best_text: SpriteTextScript
var _wallet_rest := Vector2.ZERO
var _wallet_text_rest := Vector2.ZERO
var _wallet_phase := 0.22
var _wallet_speed := 1.64
var _wallet_flash := 0.0
var _bob_t := 0.0
var _card_pos := Vector2.ZERO
var _card_scale := 1.0
var _card_base_y := 0.0
var _card_followers: Array[CanvasItem] = []
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
var _privacy_button: Button
var _missions: DailyMissionsOverlay
var _modes_return := false
var _mode_token := 0
var _mode_busy := false
var _launching := false
var _daily_locked := false
var _status_course: Dictionary = {}
var _daily_checking := false
var _status_busy := false
var _status_again := false
var _daily_resets_unix := 0
var _daily_lives := -1
# Editor-binary preview only. -1 follows the server count. Never written to disk.
var _daily_visual_override := -1
var _daily_source := "none"
var _daily_paint_reason := ""
var _daily_paint_sig := ""
var _last_daily_status: Dictionary = {}
var _editor_test_row: Control
var _editor_test_announced := false
var _status_gen := 0
var _daily_net_retry_msec := 0
var _daily_needs_session := false
var _daily_fish: Array[TextureRect] = []
var _daily_fish_color: Texture2D
var _daily_fish_gray_tex: Texture2D


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	set_process(true)
	set_process_input(true)
	_backdrop()
	_card_scale = RR.VIEW_W / OVERLAY_W
	var card_size := Vector2(OVERLAY_W, OVERLAY_H) * _card_scale
	var fish_strip := 210.0
	_card_base_y = clampf((RR.VIEW_H - card_size.y - fish_strip) * 0.42, 10.0, 90.0)
	_card_pos = Vector2((RR.VIEW_W - card_size.x) * 0.5, _card_base_y)
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
	if backend and backend.has_signal("daily_status_refresh_requested") and not backend.daily_status_refresh_requested.is_connected(_on_daily_status_refresh):
		backend.daily_status_refresh_requested.connect(_on_daily_status_refresh)
	if backend and backend.has_signal("share_rewards_changed") and not backend.share_rewards_changed.is_connected(_refresh_wallet):
		backend.share_rewards_changed.connect(_refresh_wallet)
	if backend and backend.has_signal("daily_missions_changed") and not backend.daily_missions_changed.is_connected(_refresh_wallet):
		backend.daily_missions_changed.connect(_refresh_wallet)
	if backend and backend.has_signal("daily_missions_changed") and not backend.daily_missions_changed.is_connected(_on_menu_missions):
		backend.daily_missions_changed.connect(_on_menu_missions)
	if not get_viewport().size_changed.is_connected(_sync_menu_anchor):
		get_viewport().size_changed.connect(_sync_menu_anchor)
	var ads := get_node_or_null("/root/RewardedAds")
	if ads and ads.has_signal("privacy_options_changed") and not ads.privacy_options_changed.is_connected(_sync_privacy_button):
		ads.privacy_options_changed.connect(_sync_privacy_button)
	_sync_menu_anchor()
	if GameSession.has_signal("editor_daily_test_changed") and not GameSession.editor_daily_test_changed.is_connected(_on_editor_daily_test_changed):
		GameSession.editor_daily_test_changed.connect(_on_editor_daily_test_changed)
	_announce_editor_daily_controls()
	if _editor_daily_test_active():
		# A return from a local test run builds a new menu. The life count is
		# already on the session. Paint the fish and the button from it here.
		# The mode screen opens only for the first enable, not after every run.
		_apply_editor_daily_test_presentation()
		if GameSession.editor_daily_test_show_modes:
			GameSession.editor_daily_test_show_modes = false
			_open_modes()
	else:
		_refresh_daily_status()


func _process(delta: float) -> void:
	if _home.visible:
		_tick_carousels(delta)
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
	var backend := get_node_or_null("/root/Backend")
	if _mode_busy:
		backend = null
	if (
		_daily_net_retry_msec > 0
		and Time.get_ticks_msec() >= _daily_net_retry_msec
		and not _editor_daily_test_active()
		and not _mode_busy
		and not _launching
	):
		_daily_net_retry_msec = 0
		_refresh_daily_status()
	if backend and backend.has_method("daily_refresh_due") and backend.daily_refresh_due():
		backend.call_deferred("refresh_daily_after_rollover")
		if not _editor_daily_test_active():
			_refresh_daily_status(true)
	if not _scores.visible:
		return
	if GameSession.refresh_boards():
		_fill_scores()
	if backend and backend.has_method("leaderboard_period_stale") and backend.leaderboard_period_stale():
		backend.call_deferred("fetch_leaderboards")


func _input(event: InputEvent) -> void:
	if _try_daily_visual_override(event):
		return
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
	_lobby_bg = TextureRect.new()
	_lobby_bg.texture = Sprites.tex("background")
	_lobby_bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_lobby_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_lobby_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_lobby_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_lobby_bg)
	_ground = TextureRect.new()
	_ground.texture = Sprites.tex("ground")
	_ground.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ground.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ground.modulate = Color.WHITE
	add_child(_ground)
	_place_lobby_edges()


func _place_lobby_edges() -> void:
	var bottom := RR.screen_bottom()
	if _lobby_bg:
		_lobby_bg.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_lobby_bg.position = Vector2.ZERO
		_lobby_bg.size = Vector2(RR.VIEW_W, bottom + RR.BG_SINK)
	if _ground:
		_ground.position = Vector2(0, bottom - RR.GROUND_H)
		_ground.size = Vector2(RR.VIEW_W, RR.GROUND_H + RR.GROUND_FADE)


func _layer() -> Control:
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layer)
	return layer


func _build_home(card_size: Vector2) -> void:
	var card := _overlay_card(Sprites.tex("main_menu_overlay"), card_size, _card_pos, true)
	_home.add_child(card)
	_follow_card(card)
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
	_follow_card(_name_edit)
	var play := _hotspot(PLAY_BOX, _play, _card_pos, _card_scale)
	_mark_plate(play, "main_menu_overlay", PLAY_BOX, Rect2(256, 906, 628, 173), 0.46, "wood")
	_home.add_child(play)
	_follow_card(play)
	var scores_btn := _hotspot(SCORE_BOX, _show_scores, _card_pos, _card_scale)
	_mark_plate(scores_btn, "main_menu_overlay", SCORE_BOX, SCORE_PLATE, 0.46, "blue")
	_home.add_child(scores_btn)
	_follow_card(scores_btn)
	_build_fish_picker()
	_build_hat_picker()
	_build_personal_best()
	_privacy_button = Button.new()
	_privacy_button.flat = true
	_privacy_button.focus_mode = Control.FOCUS_NONE
	_privacy_button.visible = false
	_privacy_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_privacy_button.custom_minimum_size = Vector2(240, 36)
	_privacy_button.size = Vector2(240, 36)
	_privacy_button.pressed.connect(func() -> void:
		var ads := get_node_or_null("/root/RewardedAds")
		if ads:
			ads.show_privacy_options()
	)
	var privacy_label := SpriteTextScript.new()
	privacy_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	privacy_label.configure("AD PRIVACY", 16, Vector2(240, 28), HORIZONTAL_ALIGNMENT_CENTER)
	_privacy_button.add_child(privacy_label)
	_home.add_child(_privacy_button)


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
	_mark_plate(_score_back, "daily_overlay", BACK_BOX, BACK_PLATE, 0.46, "wood")
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


func _follow_card(node: CanvasItem) -> void:
	node.set_meta("card_dy", node.position.y - _card_pos.y)
	_card_followers.append(node)


func _apply_home_safe_top() -> void:
	var top := RR.display_insets(RR.screen_size()).y
	_card_pos.y = maxf(_card_base_y, top)
	for node in _card_followers:
		if node == null:
			continue
		node.position.y = _card_pos.y + float(node.get_meta("card_dy", 0.0))


func _sync_menu_anchor() -> void:
	_apply_home_safe_top()
	_place_lobby_edges()
	_layout_mode_overlay()
	_layout_scores()
	_sync_privacy_button()
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
	_layout_personal_best()


func _sync_privacy_button(_required: bool = false) -> void:
	if _privacy_button == null:
		return
	var ads := get_node_or_null("/root/RewardedAds")
	var required := false
	if ads != null and ads.has_method("privacy_options_required"):
		required = bool(ads.privacy_options_required())
	_privacy_button.visible = required
	_privacy_button.mouse_filter = Control.MOUSE_FILTER_STOP if required else Control.MOUSE_FILTER_IGNORE
	var screen := RR.screen_size()
	_privacy_button.position = Vector2((screen.x - _privacy_button.size.x) * 0.5, RR.screen_bottom() - 44.0)


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
	_fish_ring_on = _ring_style(Color(0.12, 0.42, 0.62, 0.22), 3, 18)
	_fish_ring_off = _ring_style(Color(0.12, 0.42, 0.62, 0.0), 0, 18)
	_fish_clip = Control.new()
	_fish_clip.position = Vector2(pad, row_y)
	_fish_clip.size = Vector2(RR.VIEW_W - pad * 2.0, clip_h)
	_fish_clip.mouse_filter = Control.MOUSE_FILTER_STOP
	_fish_clip.clip_contents = true
	_fish_clip.z_index = 30
	_still_motion(_fish_clip)
	_fish_clip.gui_input.connect(_on_fish_gui)
	_home.add_child(_fish_clip)
	var inner_w := 4.0 + float(count) * (cell + gap) - gap
	_fish_max_scroll = maxf(0.0, inner_w - _fish_clip.size.x)
	_fish_row = Control.new()
	_fish_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fish_row.custom_minimum_size = Vector2(inner_w, _fish_clip.size.y)
	_fish_row.size = Vector2(inner_w, _fish_clip.size.y)
	_still_motion(_fish_row)
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
		_still_motion(holder)
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
		icon.pivot_offset = icon_size * 0.5
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
	var wallet_w := _build_wallet(Vector2(pad, row_y + edge + 18.0))
	_hat_ring_on = _ring_style(Color(0, 0, 0, 0), 3, 14, false)
	_hat_ring_off = _ring_style(Color(0, 0, 0, 0), 0, 14, false)
	_hat_clip = Control.new()
	_hat_clip.position = Vector2(pad + wallet_w + 6.0, row_y)
	_hat_clip.size = Vector2(RR.VIEW_W - pad * 2.0 - wallet_w - 6.0, clip_h)
	_hat_clip.mouse_filter = Control.MOUSE_FILTER_STOP
	_hat_clip.clip_contents = true
	_hat_clip.z_index = 40
	_still_motion(_hat_clip)
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
	_still_motion(_hat_row)
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
		_still_motion(holder)
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
	_hat_scroll_x = _hat_scroll_visual
	_hat_slide_t = 1.0
	_hat_press_scroll = _hat_scroll_visual


func _move_hat_drag(pos: Vector2) -> void:
	if not _hat_pressing:
		return
	var dx := pos.x - _hat_press.x
	if absf(dx) > 6.0:
		_hat_dragged = true
	_hat_scroll_x = clampf(_hat_press_scroll - dx, 0.0, _hat_max_scroll)
	_hat_scroll_visual = _hat_scroll_x
	_hat_slide_t = 1.0
	_place_hat_row()


func _end_hat_drag(pos: Vector2) -> void:
	if not _hat_pressing:
		return
	_hat_pressing = false
	if _hat_dragged:
		return
	_click_hat_at(pos)


func _scroll_hats(delta_x: float) -> void:
	_start_hat_slide(clampf(_hat_scroll_x + delta_x, 0.0, _hat_max_scroll))


func _apply_hat_scroll() -> void:
	_hat_scroll_visual = _hat_scroll_x
	_hat_slide_from = _hat_scroll_x
	_hat_slide_to = _hat_scroll_x
	_hat_slide_t = 1.0
	_place_hat_row()


func _start_hat_slide(target: float) -> void:
	_hat_scroll_x = target
	if absf(_hat_scroll_visual - target) < 0.5:
		_apply_hat_scroll()
		return
	_hat_slide_from = _hat_scroll_visual
	_hat_slide_to = target
	_hat_slide_t = 0.0


func _place_hat_row() -> void:
	if _hat_row:
		_hat_row.position.x = -_hat_scroll_visual


func _click_hat_at(pos: Vector2) -> void:
	var x := pos.x + _hat_scroll_visual - 4.0
	if x < 0.0:
		return
	var stride := _hat_cell + _hat_gap
	var index := int(x / stride)
	if index < 0 or index >= _hat_ids.size():
		return
	if x - float(index) * stride > _hat_cell:
		return
	_choose_hat(_hat_ids[index])


func _build_wallet(origin: Vector2) -> float:
	# Previous indicator: 34.56 coin, 22px number, 4px gap. Grown in place.
	var old_coin := 48.0 * 0.72
	var coin_size := old_coin * 1.6
	var glyph_h := 22.0 * 1.4
	var gap := 4.0
	var mid_y := origin.y + old_coin * 0.5
	_wallet_coin = TextureRect.new()
	_wallet_coin.name = "WalletCoin"
	_wallet_coin.texture = Sprites.tex("coin")
	_wallet_coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_wallet_coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_wallet_coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wallet_coin.z_index = 40
	_still_motion(_wallet_coin)
	_wallet_coin.position = Vector2(origin.x, mid_y - coin_size * 0.5)
	_wallet_coin.size = Vector2(coin_size, coin_size)
	_wallet_rest = _wallet_coin.position
	_home.add_child(_wallet_coin)
	_wallet_text = SpriteTextScript.new()
	_wallet_text.name = "WalletBalance"
	_still_motion(_wallet_text)
	var text_w := _wallet_text.layout_width("10000", glyph_h, true)
	_wallet_text.z_index = 40
	_wallet_text.position = Vector2(origin.x + coin_size + gap, mid_y - glyph_h * 0.5)
	_wallet_text_rest = _wallet_text.position
	_wallet_text.configure(str(GameSession.coins), glyph_h, Vector2(text_w, glyph_h), HORIZONTAL_ALIGNMENT_LEFT, true)
	_home.add_child(_wallet_text)
	return coin_size + gap + text_w


func _refresh_wallet() -> void:
	if _wallet_text:
		_wallet_text.set_value(str(GameSession.coins))
		_wallet_text.modulate = Color.WHITE


func _build_personal_best() -> void:
	_best_row = Control.new()
	_best_row.name = "PersonalBest"
	_best_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_best_row.z_index = 20
	_home.add_child(_best_row)
	_best_crown = TextureRect.new()
	_best_crown.name = "BestCrown"
	_best_crown.texture = Sprites.tex("crown_gold")
	_best_crown.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_best_crown.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_best_crown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_best_row.add_child(_best_crown)
	_best_text = SpriteTextScript.new()
	_best_text.name = "BestText"
	_best_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_best_text.configure("PERSONAL BEST 0", 18.0, Vector2(RR.VIEW_W, 22.0), HORIZONTAL_ALIGNMENT_CENTER, true, false, 1.05, true)
	_best_row.add_child(_best_text)


func _fish_icon_rest_top() -> float:
	if _fish_clip == null or _fish_rest.is_empty() or _fish_row == null:
		return _fish_band_bottom()
	return _fish_clip.position.y + _fish_row.position.y + _fish_rest[0].y


func _layout_personal_best() -> void:
	if _best_row == null or _best_text == null:
		return
	var label := "PERSONAL BEST %d" % maxi(GameSession.best_score, 0)
	var plate_bottom := _card_pos.y + SCORE_PLATE.end.y * _card_scale
	var icon_top := _fish_icon_rest_top()
	var bob := 8.0
	var band_top := plate_bottom + 6.0
	var band_bottom := icon_top - bob - 6.0
	if band_bottom < band_top + 16.0:
		band_top = plate_bottom + 2.0
		band_bottom = icon_top - 2.0
	var avail := maxf(12.0, band_bottom - band_top)
	var glyph := clampf(minf(22.0, avail * 0.46), 12.0, 22.0)
	if glyph + 2.0 > band_bottom - band_top:
		glyph = maxf(11.0, band_bottom - band_top - 2.0)
	for _pass in 2:
		var width := _place_personal_best(label, glyph, band_top, band_bottom)
		if width <= RR.VIEW_W - 16.0:
			break
		glyph = maxf(11.0, glyph * (RR.VIEW_W - 16.0) / maxf(width, 1.0))


func _place_personal_best(label: String, glyph: float, band_top: float, band_bottom: float) -> float:
	var block := maxf(glyph, 11.0)
	_best_text.configure(label, block, Vector2(RR.VIEW_W, block), HORIZONTAL_ALIGNMENT_CENTER, true, false, 1.05, true)
	_best_text.resize_box(block, Vector2(RR.VIEW_W, block))
	var bounds := _best_glyph_bounds()
	var crown_h := block * 0.86
	var aspect := 1.15
	if _best_crown.texture != null and _best_crown.texture.get_height() > 0:
		aspect = float(_best_crown.texture.get_width()) / float(_best_crown.texture.get_height())
	var crown_w := crown_h * aspect
	var gap := maxf(3.0, block * 0.16)
	var group_w := crown_w + gap + bounds.size.x
	var group_x := (RR.VIEW_W - group_w) * 0.5
	_best_crown.position = Vector2(group_x, (block - crown_h) * 0.5)
	_best_crown.size = Vector2(crown_w, crown_h)
	_best_text.position = Vector2(group_x + crown_w + gap - bounds.position.x, 0.0)
	var y := band_top + (band_bottom - band_top - block) * 0.5
	_best_row.position = Vector2(0.0, y)
	_best_row.size = Vector2(RR.VIEW_W, block)
	return group_w


func _best_glyph_bounds() -> Rect2:
	var left := _best_text.size.x
	var right := 0.0
	var any := false
	for child in _best_text.get_children():
		any = true
		left = minf(left, child.position.x)
		right = maxf(right, child.position.x + child.size.x)
	if not any:
		return Rect2(0.0, 0.0, 0.0, _best_text.size.y)
	return Rect2(left, 0.0, right - left, _best_text.size.y)


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
		_hat_rings[n].add_theme_stylebox_override("panel", _hat_ring_on if equipped else _hat_ring_off)
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
	_fish_scroll_x = _fish_scroll_visual
	_fish_slide_t = 1.0
	_fish_press_scroll = _fish_scroll_visual


func _move_fish_drag(pos: Vector2) -> void:
	if not _fish_pressing:
		return
	var dx := pos.x - _fish_press.x
	if absf(dx) > 6.0:
		_fish_dragged = true
	_fish_scroll_x = clampf(_fish_press_scroll - dx, 0.0, _fish_max_scroll)
	_fish_scroll_visual = _fish_scroll_x
	_fish_slide_t = 1.0
	_place_fish_row()


func _end_fish_drag(pos: Vector2) -> void:
	if not _fish_pressing:
		return
	_fish_pressing = false
	if _fish_dragged:
		return
	_click_fish_at(pos)


func _scroll_fish(delta_x: float) -> void:
	_start_fish_slide(clampf(_fish_scroll_x + delta_x, 0.0, _fish_max_scroll))


func _apply_fish_scroll() -> void:
	_fish_scroll_visual = _fish_scroll_x
	_fish_slide_from = _fish_scroll_x
	_fish_slide_to = _fish_scroll_x
	_fish_slide_t = 1.0
	_place_fish_row()


func _start_fish_slide(target: float) -> void:
	_fish_scroll_x = target
	if absf(_fish_scroll_visual - target) < 0.5:
		_apply_fish_scroll()
		return
	_fish_slide_from = _fish_scroll_visual
	_fish_slide_to = target
	_fish_slide_t = 0.0


func _place_fish_row() -> void:
	if _fish_row:
		_fish_row.position.x = -_fish_scroll_visual


func _click_fish_at(pos: Vector2) -> void:
	var x := pos.x + _fish_scroll_visual - 4.0
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
		_fish_rings[i].add_theme_stylebox_override("panel", _fish_ring_on if on else _fish_ring_off)
		if on:
			_fish_icons[i].modulate = Color.WHITE
		elif owned:
			_fish_icons[i].modulate = Color(0.82, 0.88, 0.92, 0.78)
		else:
			_fish_icons[i].modulate = Color(0.55, 0.62, 0.7, 0.9)
		_fish_icons[i].set_meta("scale_goal", 1.08 if on else 1.0)
		if i < _fish_prices.size():
			_fish_prices[i].visible = not owned
	_refresh_fish_hats()


func _refresh_fish_hats() -> void:
	var equipped := GameSession.hat_index
	if equipped == _shown_menu_hat:
		return
	_shown_menu_hat = equipped
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


func _tick_carousels(delta: float) -> void:
	_advance_slide(delta, true)
	_advance_slide(delta, false)
	_ease_icon_scales(delta)
	_bob_picker(delta)


func _advance_slide(delta: float, fish: bool) -> void:
	var t := _fish_slide_t if fish else _hat_slide_t
	if t >= 1.0:
		return
	t = minf(1.0, t + delta / CAROUSEL_SLIDE_SEC)
	var from := _fish_slide_from if fish else _hat_slide_from
	var to := _fish_slide_to if fish else _hat_slide_to
	var visual := lerpf(from, to, _slide_ease(t))
	if t >= 1.0:
		visual = to
	if fish:
		_fish_slide_t = t
		_fish_scroll_visual = visual
		_place_fish_row()
	else:
		_hat_slide_t = t
		_hat_scroll_visual = visual
		_place_hat_row()


func _slide_ease(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _ease_icon_scales(delta: float) -> void:
	var keep := exp(-delta / 0.06)
	for icon in _fish_icons:
		var goal := float(icon.get_meta("scale_goal", 1.0))
		var shown := icon.scale.x
		if absf(shown - goal) < 0.001:
			continue
		var next := goal + (shown - goal) * keep
		if absf(next - goal) < 0.001:
			next = goal
		icon.scale = Vector2(next, next)


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


func _still_motion(node: CanvasItem) -> void:
	node.physics_interpolation_mode = CanvasItem.PHYSICS_INTERPOLATION_MODE_OFF


func _ring_style(fill: Color, border: int, radius: int, draw_center := true) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.draw_center = draw_center
	style.set_border_width_all(border)
	style.border_color = Color(1.0, 0.92, 0.42, 0.95)
	style.set_corner_radius_all(radius)
	return style


func _hotspot(src: Rect2, pressed: Callable, origin: Vector2, scale: float) -> Button:
	var btn := Button.new()
	btn.flat = true
	btn.position = origin + src.position * scale
	btn.size = src.size * scale
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.pressed.connect(pressed)
	return btn


func _mark_plate(btn: Button, art_id: String, hit: Rect2, plate: Rect2, radius: float, kind := "auto") -> void:
	ButtonFeedbackScript.use_plate(btn, Sprites.tex(art_id), hit, plate, radius, kind)


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
	return Rect2(_score_pos + src.position * _score_scale, src.size * _score_scale)


func _layout_scores() -> void:
	if _score_card == null:
		return
	# The plate covers the portrait screen. Name length must not change this rect.
	var screen := RR.screen_size()
	var plate := RR.fullscreen_plate(Vector2(SCORE_W, SCORE_H), screen, SCORE_KEEP, Vector2(0.5, 0.5))
	_score_scale = Vector2(plate.size.x / SCORE_W, plate.size.y / SCORE_H)
	_score_pos = plate.position
	_score_card.stretch_mode = TextureRect.STRETCH_SCALE
	_score_card.position = plate.position
	_score_card.size = plate.size
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
	line.position = _score_pos + src.position * _score_scale
	var height := glyph_h if glyph_h > 0.0 else box.y * 0.92
	line.resize_box(height, box)


func _score_arrow_hit(pos: Vector2) -> bool:
	return _score_arrow_left_rect.has_point(pos) or _score_arrow_right_rect.has_point(pos)


func _score_arrow_boxes(size: Vector2) -> Array[Rect2]:
	var screen := RR.screen_size()
	var fits := _arrow_fits(size)
	return _arrow_boxes_for(size, _score_art_rect(BACK_VISUAL), screen, RR.display_insets(screen), fits[0], fits[1])


func _arrow_fits(size: Vector2) -> Array[Rect2]:
	var fits: Array[Rect2] = []
	fits.append(_arrow_fit("btn_score_left", size))
	fits.append(_arrow_fit("btn_score_right", size))
	return fits


# Opaque artwork inside a texture box after keep-aspect centering.
func _arrow_fit(id: String, box_size: Vector2) -> Rect2:
	var tex := Sprites.tex(id)
	var tex_size := Vector2(tex.get_width(), tex.get_height())
	var scale := minf(box_size.x / tex_size.x, box_size.y / tex_size.y)
	var opaque := _arrow_opaque_rect(id, tex_size)
	var origin := (box_size - tex_size * scale) * 0.5
	return Rect2(origin + opaque.position * scale, opaque.size * scale)


func _arrow_opaque_rect(id: String, tex_size: Vector2) -> Rect2:
	if _arrow_opaque.has(id):
		return _arrow_opaque[id]
	var rect := Rect2(Vector2.ZERO, tex_size)
	var tex := Sprites.tex(id)
	var image := tex.get_image() if tex else null
	if image:
		var used := image.get_used_rect()
		if used.size.x > 1 and used.size.y > 1:
			rect = Rect2(used.position, used.size)
	_arrow_opaque[id] = rect
	return rect


# Boxes keep the authored arrow size. Their opaque artwork is centered on the
# Back button, with one shared gap that shrinks only to stay on screen.
func _arrow_boxes_for(size: Vector2, button: Rect2, screen: Vector2, margins: Vector4, left_fit: Rect2, right_fit: Rect2) -> Array[Rect2]:
	var min_x := margins.x + 4.0
	var max_x := screen.x - margins.z - 4.0
	var center_y := button.position.y + button.size.y * 0.5
	var left_y := center_y - (left_fit.position.y + left_fit.size.y * 0.5)
	var right_y := center_y - (right_fit.position.y + right_fit.size.y * 0.5)
	var room_left := button.position.x - min_x - left_fit.size.x
	var room_right := max_x - button.end.x - right_fit.size.x
	var gap := minf(minf(left_fit.size.y, right_fit.size.y) * 0.45, maxf(minf(room_left, room_right), 0.0))
	var left_x := button.position.x - gap - (left_fit.position.x + left_fit.size.x)
	var right_x := button.end.x + gap - right_fit.position.x
	var shift_y := _arrow_shift_y(left_y, right_y, left_fit, right_fit, screen.y)
	left_y += shift_y
	right_y += shift_y
	var boxes: Array[Rect2] = []
	boxes.append(Rect2(left_x, left_y, size.x, size.y))
	boxes.append(Rect2(right_x, right_y, size.x, size.y))
	return boxes


func _arrow_shift_y(left_y: float, right_y: float, left_fit: Rect2, right_fit: Rect2, screen_h: float) -> float:
	var top := minf(left_y + left_fit.position.y, right_y + right_fit.position.y)
	var bottom := maxf(left_y + left_fit.end.y, right_y + right_fit.end.y)
	var shift := 0.0
	if top < 0.0:
		shift = -top
	if bottom + shift > screen_h:
		shift -= bottom + shift - screen_h
	return shift


func _arrow_visible(box: Rect2, fit: Rect2) -> Rect2:
	return Rect2(box.position + fit.position, fit.size)


func _build_score_arrows() -> void:
	var size := Vector2(ARROW_BOX, ARROW_BOX)
	var fits := _arrow_fits(size)
	var boxes := _score_arrow_boxes(size)
	var left := boxes[0]
	var right := boxes[1]
	_score_arrow_left_rect = _score_arrow_hit_rect(_arrow_visible(left, fits[0]))
	_score_arrow_right_rect = _score_arrow_hit_rect(_arrow_visible(right, fits[1]))
	_score_arrow_left_icon = _score_arrow_icon("btn_score_left", left)
	_score_arrow_right_icon = _score_arrow_icon("btn_score_right", right)
	_score_arrow_left_btn = _screen_hotspot(_score_arrow_left_rect, _cycle_score_page.bind(-1))
	_score_arrow_right_btn = _screen_hotspot(_score_arrow_right_rect, _cycle_score_page.bind(1))
	ButtonFeedbackScript.use_visual(_score_arrow_left_btn, _score_arrow_left_icon)
	ButtonFeedbackScript.use_visual(_score_arrow_right_btn, _score_arrow_right_icon)
	_scores.add_child(_score_arrow_left_btn)
	_scores.add_child(_score_arrow_right_btn)


func _layout_score_arrows() -> void:
	if _score_arrow_left_icon == null:
		return
	var size := Vector2(ARROW_BOX, ARROW_BOX)
	var fits := _arrow_fits(size)
	var boxes := _score_arrow_boxes(size)
	var left := boxes[0]
	var right := boxes[1]
	_score_arrow_left_rect = _score_arrow_hit_rect(_arrow_visible(left, fits[0]))
	_score_arrow_right_rect = _score_arrow_hit_rect(_arrow_visible(right, fits[1]))
	_place_score_arrow(_score_arrow_left_icon, _score_arrow_left_btn, left, _score_arrow_left_rect)
	_place_score_arrow(_score_arrow_right_icon, _score_arrow_right_btn, right, _score_arrow_right_rect)


func _score_arrow_hit_rect(visible: Rect2) -> Rect2:
	var hit := visible.intersection(Rect2(Vector2.ZERO, RR.screen_size()))
	if hit.size.x < 1.0 or hit.size.y < 1.0:
		return visible
	return hit


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
		_score_names.append(_add_score_text(_row_content_rect(i, SCORE_NAME_X, SCORE_NAME_W, 2.0), HORIZONTAL_ALIGNMENT_LEFT, false, name_h, false, 1.0, true))
		_score_values.append(_add_score_text(_row_content_rect(i, SCORE_VALUE_X, SCORE_VALUE_W), HORIZONTAL_ALIGNMENT_RIGHT, true, glyph_h, true))
	_score_status = _add_score_text(Rect2(210.0, 352.0, 520.0, 68.0), HORIZONTAL_ALIGNMENT_CENTER, false, 0.0, true)
	_score_status.visible = false


func _score_glyph_height() -> float:
	var row_h: float = SCORE_ROWS_H[0]
	for raw in SCORE_ROWS_H:
		row_h = minf(row_h, float(raw))
	# 0.54 fits the row. The extra 0.85 is the shared 15% reduction of names and scores.
	return row_h * _score_scale.y * 0.54 * 0.85


func _score_name_height() -> float:
	# Same destination height as the orange score digits. Letter width follows
	# each sprite's aspect ratio, and every name uses this one height.
	return _score_glyph_height()


func _row_content_rect(index: int, x: float, width: float, inset: float = 10.0) -> Rect2:
	var y: float = SCORE_ROWS_Y[index]
	var h: float = SCORE_ROWS_H[index]
	return Rect2(x, y + inset, width, maxf(24.0, h - inset * 2.0))


func _add_score_text(src: Rect2, align: HorizontalAlignment, gold_digits: bool, glyph_h: float, fit_box: bool, kern: float = 1.12, match_height: bool = false) -> SpriteTextScript:
	var line := SpriteTextScript.new()
	line.z_index = 2
	var box := Vector2(src.size.x * _score_scale.x, src.size.y * _score_scale.y)
	line.position = _score_pos + src.position * _score_scale
	var height := glyph_h if glyph_h > 0.0 else box.y * 0.92
	line.configure("", height, box, align, gold_digits, fit_box, kern, match_height)
	if not fit_box:
		line.clip_contents = true
	_score_rows.add_child(line)
	return line


func _sync_score_status(period: String, row_count: int) -> void:
	if _score_status == null:
		return
	var note := ""
	var backend := get_node_or_null("/root/Backend")
	var meta: Dictionary = {}
	if backend and backend.get("leaderboard_meta") is Dictionary:
		var all: Dictionary = backend.leaderboard_meta
		var got: Variant = all.get(period, {})
		if typeof(got) == TYPE_DICTIONARY:
			meta = got
	var busy: bool = backend != null and backend.has_method("leaderboard_busy") and backend.leaderboard_busy()
	var submit_error := ""
	if period == "daily" and backend != null:
		submit_error = str(backend.get("daily_submit_error"))
	if not meta.is_empty() and not bool(meta.get("ok", false)) and not busy:
		note = "COULD NOT LOAD SCORES"
	elif submit_error != "":
		note = "SCORE NOT SAVED"
	elif row_count <= 0 and (meta.is_empty() or busy):
		note = "LOADING"
	_score_status.set_value(note)
	_score_status.visible = note != ""


func _show_home() -> void:
	_score_swiping = false
	_scores.visible = false
	_home.visible = true
	if _ground:
		_ground.visible = true
	_layout_personal_best()


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
	_mark_plate(_mode_unlimited, "mode_unlocked", MODE_UNLIMITED, MODE_UNLIMITED.grow(-8.0), 0.14)
	_mark_plate(daily, "mode_unlocked", MODE_DAILY, MODE_DAILY.grow(-8.0), 0.14)
	_mark_plate(_mission_button, "mode_unlocked", MODE_MISSIONS, MODE_MISSIONS.grow(-10.0), 0.32)
	_mark_plate(_mode_back, "mode_unlocked", MODE_BACK, Rect2(200, 1634, 380, 96), 0.46, "blue")
	for btn in [_mode_unlimited, daily, _mode_back, _mission_button]:
		btn.focus_mode = Control.FOCUS_NONE
		_modes.add_child(btn)
	_daily_button = daily
	_daily_button.disabled = true
	_build_daily_fish()
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
	_build_editor_daily_test_controls()
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


func _mode_cover_rect(screen: Vector2) -> Rect2:
	return RR.fullscreen_plate(Vector2(MODE_W, MODE_H), screen, MODE_KEEP, Vector2(0.5, 1.0))


func _layout_mode_overlay() -> void:
	if _mode_card == null or _modes == null:
		return
	var screen := RR.screen_size()
	var plate := _mode_cover_rect(screen)
	_mode_scale = Vector2(plate.size.x / MODE_W, plate.size.y / MODE_H)
	_mode_origin = plate.position
	_mode_card.stretch_mode = TextureRect.STRETCH_SCALE
	_mode_card.position = plate.position
	_mode_card.size = plate.size
	_place_hotspot(_mode_unlimited, MODE_UNLIMITED)
	_place_hotspot(_daily_button, MODE_DAILY)
	_place_hotspot(_mission_button, MODE_MISSIONS)
	_place_hotspot(_mode_back, MODE_BACK)
	_layout_daily_fish()
	_layout_editor_daily_test()
	_layout_mode_status()


func _place_hotspot(btn: Button, src: Rect2) -> void:
	if btn == null:
		return
	btn.position = _mode_origin + src.position * _mode_scale
	btn.size = src.size * _mode_scale


func daily_fish_slots() -> Array[Rect2]:
	var slots: Array[Rect2] = []
	var span := DAILY_FISH_SIZE * float(DailyAttemptScript.ATTEMPT_LIMIT) + DAILY_FISH_GAP * float(DailyAttemptScript.ATTEMPT_LIMIT - 1)
	var left := MODE_DAILY.position.x + (MODE_DAILY.size.x - span) * 0.5
	var top := MODE_DAILY.position.y - DAILY_FISH_SIZE * 0.35
	for i in DailyAttemptScript.ATTEMPT_LIMIT:
		slots.append(Rect2(left + float(i) * (DAILY_FISH_SIZE + DAILY_FISH_GAP), top, DAILY_FISH_SIZE, DAILY_FISH_SIZE))
	return slots


# The mode card can be stretched to cover a short screen. Fish stay square
# and sit on the center of their art slot so the sprite is not distorted.
func daily_fish_screen_rects(cover: Rect2) -> Array[Rect2]:
	var scale := Vector2(cover.size.x / MODE_W, cover.size.y / MODE_H)
	var side := DAILY_FISH_SIZE * minf(scale.x, scale.y)
	var placed: Array[Rect2] = []
	for slot in daily_fish_slots():
		var center := cover.position + (slot.position + slot.size * 0.5) * scale
		placed.append(Rect2(center - Vector2(side, side) * 0.5, Vector2(side, side)))
	return placed


func _build_daily_fish() -> void:
	if _modes == null:
		return
	for i in DailyAttemptScript.ATTEMPT_LIMIT:
		var icon := TextureRect.new()
		icon.name = "DailyAttemptFish%d" % i
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.z_index = 4
		icon.use_parent_material = false
		icon.material = null
		icon.modulate = Color.WHITE
		icon.self_modulate = Color.WHITE
		_modes.add_child(icon)
		_daily_fish.append(icon)
	_daily_paint_reason = "build"
	_repaint_attempt_fish()


func _layout_daily_fish() -> void:
	if _daily_fish.is_empty():
		return
	var tex: Texture2D = null
	var sprites := get_node_or_null("/root/Sprites")
	if sprites and sprites.has_method("tex"):
		var fish_id := "fish_blue"
		if GameSession and GameSession.has_method("selected_fish"):
			var picked := str(GameSession.selected_fish())
			if picked != "":
				fish_id = picked
		tex = sprites.tex(fish_id)
		if tex == null:
			tex = sprites.tex("fish_blue")
	var plate := Rect2(_mode_origin, Vector2(MODE_W, MODE_H) * _mode_scale)
	var placed := daily_fish_screen_rects(plate)
	if tex:
		_remember_fish_color(tex)
	for i in _daily_fish.size():
		var icon := _daily_fish[i]
		icon.position = placed[i].position
		icon.size = placed[i].size
	# Position only. The life count is not rebuilt here, or a late layout
	# paints gray fish on top of an already unlocked button.
	_daily_paint_reason = "layout"
	_repaint_attempt_fish()


func _remember_fish_color(tex: Texture2D) -> void:
	if tex == null or tex == _daily_fish_color:
		return
	_daily_fish_color = tex
	_daily_fish_gray_tex = _grayscale_copy(tex)


func _grayscale_copy(tex: Texture2D) -> Texture2D:
	var img := tex.get_image()
	if img == null:
		return null
	img = img.duplicate()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var px := img.get_pixel(x, y)
			var g := px.r * 0.299 + px.g * 0.587 + px.b * 0.114
			img.set_pixel(x, y, Color(g, g, g, px.a))
	return ImageTexture.create_from_image(img)


func _texture_has_color(tex: Texture2D) -> bool:
	if tex == null:
		return false
	var img := tex.get_image()
	if img == null:
		return false
	var step_x := maxi(1, int(img.get_width() / 8.0))
	var step_y := maxi(1, int(img.get_height() / 8.0))
	for y in range(0, img.get_height(), step_y):
		for x in range(0, img.get_width(), step_x):
			var px := img.get_pixel(x, y)
			if px.a < 0.2:
				continue
			var hi := maxf(px.r, maxf(px.g, px.b))
			var lo := minf(px.r, minf(px.g, px.b))
			if hi - lo > 0.08:
				return true
	return false


# A launched game reports Engine.is_editor_hint() false. The editor binary
# still has the editor feature and never the export template feature.
func _editor_daily_debug_allowed() -> bool:
	return OS.has_feature("editor") and not OS.has_feature("template")


func _try_daily_visual_override(event: InputEvent) -> bool:
	if not _editor_daily_debug_allowed() or not event is InputEventKey:
		return false
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return false
	var code := key.keycode if key.keycode != KEY_NONE else key.physical_keycode
	var lives := -2
	match code:
		KEY_F6:
			lives = 3
		KEY_F7:
			lives = 2
		KEY_F8:
			lives = 1
		KEY_F9:
			lives = 0
		KEY_F10:
			lives = -1
		_:
			return false
	if code == KEY_F6:
		print("[DAILY DEBUG] F6 reached the game input handler.")
	if lives == 3:
		if not GameSession.activate_editor_daily_test():
			return false
		_mark_input_handled()
		return true
	if not _set_daily_visual_override(lives):
		return false
	if lives >= 0 and _modes != null and not _modes.visible:
		_open_modes()
	_mark_input_handled()
	return true


func _set_daily_visual_override(lives: int) -> bool:
	if not _editor_daily_debug_allowed():
		return false
	if not GameSession.set_editor_daily_test(lives):
		return false
	_announce_editor_daily_test(lives)
	_apply_editor_daily_test_presentation()
	_log_button_disable_state(_last_daily_status)
	return true


func _build_editor_daily_test_controls() -> void:
	if not _editor_daily_debug_allowed() or _modes == null:
		return
	var panel := PanelContainer.new()
	panel.name = "EditorDailyTest"
	panel.z_index = 120
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.04, 0.1, 0.16, 0.94)
	box.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", box)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 4)
	panel.add_child(column)
	var title := Label.new()
	title.text = "DAILY TEST  ·  Ctrl+Shift+9"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(title)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 6)
	column.add_child(row)
	_add_editor_test_button(row, "ENABLE 3", 3)
	_add_editor_test_button(row, "2", 2)
	_add_editor_test_button(row, "1", 1)
	_add_editor_test_button(row, "0 LOCK", 0)
	_add_editor_test_button(row, "SERVER", -1)
	var day_row := HBoxContainer.new()
	day_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	day_row.add_theme_constant_override("separation", 6)
	column.add_child(day_row)
	var new_day := Button.new()
	new_day.text = "NEW DAY"
	new_day.focus_mode = Control.FOCUS_NONE
	new_day.custom_minimum_size = Vector2(120, 40)
	new_day.pressed.connect(_on_editor_new_day)
	day_row.add_child(new_day)
	panel.z_index = 500
	add_child(panel)
	_editor_test_row = panel


func _add_editor_test_button(row: HBoxContainer, label: String, lives: int) -> void:
	var button := Button.new()
	button.text = label
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(86, 40)
	button.pressed.connect(_on_editor_test_lives.bind(lives))
	row.add_child(button)


func _layout_editor_daily_test() -> void:
	if _editor_test_row == null:
		return
	var screen := RR.screen_size()
	_editor_test_row.position = Vector2(8, 8)
	_editor_test_row.size = Vector2(maxf(screen.x - 16.0, 280.0), 168.0)


func _on_editor_daily_test_changed(lives: int) -> void:
	_apply_editor_daily_test_presentation()
	if lives >= 0 and _modes != null and not _modes.visible:
		_open_modes()


func _on_editor_test_lives(lives: int) -> void:
	if lives == 3:
		if not GameSession.activate_editor_daily_test():
			print("[DAILY DEBUG] REFUSED. This is not an editor play session.")
		return
	if not _set_daily_visual_override(lives):
		print("[DAILY DEBUG] REFUSED. This is not an editor play session.")
		return
	if lives < 0:
		_refresh_daily_status()
		return
	if lives >= 0 and _modes != null and not _modes.visible:
		_open_modes()


func _on_editor_new_day() -> void:
	if not GameSession.simulate_editor_daily_new_day():
		print("[DAILY DEBUG] REFUSED. This is not an editor play session.")
		return
	if _modes != null and not _modes.visible:
		_open_modes()


func _on_daily_status_refresh() -> void:
	if _editor_daily_test_active() or _mode_busy or _launching:
		return
	_daily_needs_session = false
	_refresh_daily_status(true)


func _announce_editor_daily_controls() -> void:
	if not _editor_daily_debug_allowed() or _editor_test_announced:
		return
	_editor_test_announced = true
	print("[DAILY DEBUG] DAILY TEST button is on the menu. Click ENABLE 3, or press Ctrl+Shift+9. NEW DAY restores 3 local lives.")


func _announce_editor_daily_test(lives: int) -> void:
	if lives < 0:
		print("[DAILY DEBUG] Local test disabled. Following the server. Server lives: %s. test_mode=%s editor_local=off" % [
			_server_lives_label(),
			DailyTestModeScript.status_label(),
		])
		return
	var shown := GameSession.editor_daily_test_lives
	var fish: PackedStringArray = []
	for i in DailyAttemptScript.ATTEMPT_LIMIT:
		fish.append("colored" if DailyAttemptScript.fish_lit(i, shown) else "gray")
	print("[DAILY DEBUG] Local test enabled. Lives: %d of %d. Button %s. Fish: %s. Server attempts, scores, ghosts, and coins stay unchanged. test_mode=%s editor_local=on" % [
		shown,
		DailyAttemptScript.ATTEMPT_LIMIT,
		"enabled" if shown > 0 else "disabled",
		", ".join(fish),
		DailyTestModeScript.status_label(),
	])


func _log_button_disable_state(status: Dictionary) -> void:
	var counted := bool(status.get("attempts_counted", false))
	var server_used := "absent"
	var server_remaining := "absent"
	var server_max := "absent"
	if counted:
		if status.has("attempts_used"):
			server_used = str(int(status.get("attempts_used", 0)))
		if status.has("attempts_remaining"):
			server_remaining = str(int(status.get("attempts_remaining", 0)))
		if status.has("attempts_used") and status.has("attempts_remaining"):
			server_max = str(int(status.get("attempts_used", 0)) + int(status.get("attempts_remaining", 0)))
	var course: Variant = status.get("course", {})
	var date := ""
	var seed := 0
	if typeof(course) == TYPE_DICTIONARY:
		date = str(course.get("challenge_date", "")).strip_edges()
		seed = int(course.get("course_seed", 0))
	if date == "":
		var challenge_id := str(status.get("challenge_id", ""))
		var parts := challenge_id.split(":")
		if parts.size() >= 2:
			date = parts[1]
	var available := date != "" or seed != 0
	var run_active := false
	if GameSession:
		run_active = GameSession.practice_daily or GameSession.match_mode == GameSession.MODE_DAILY
	var loading_done := not _status_busy and not _daily_checking
	var editor_on := _editor_daily_test_active()
	var editor_lives := GameSession.editor_daily_test_lives if editor_on else -1
	var disabled := _daily_button != null and _daily_button.disabled
	var because := "none"
	var reasons: PackedStringArray = []
	if disabled:
		if editor_on and editor_lives <= 0:
			because = "editor_local_lives_zero"
			reasons.append("editor_local_lives_zero")
		elif _daily_locked or _daily_lives == 0:
			because = "server_lives_zero"
			reasons.append("server_lives_zero")
			if _daily_locked:
				reasons.append("daily_locked")
			if _saved_attempts_spent():
				reasons.append("local_cache_spent")
		elif _daily_lives < 0:
			because = "status_loading"
			reasons.append("status_loading")
			reasons.append("server_lives_unknown")
			if not DailyTestModeScript.enabled():
				reasons.append("export_test_mode_off")
			if not editor_on:
				reasons.append("editor_local_off")
		else:
			because = "held_disabled"
			reasons.append("held_disabled")
		if not status.is_empty() and not bool(status.get("ok", false)):
			reasons.append("status_not_ok")
		if run_active:
			reasons.append("run_active")
	else:
		reasons.append("none")
		if editor_on:
			reasons.append("editor_local_button_enabled")
	var playable := _daily_button != null and not disabled
	print("[daily] button_state server_used=%s server_remaining=%s server_max=%s client_limit=%d challenge_date=%s available=%s playable=%s run_active=%s status_loading_done=%s button_disabled=%s because=%s conditions=%s test_mode=%s editor_local=%s editor_lives=%d server_lives=%d" % [
		server_used,
		server_remaining,
		server_max,
		DailyAttemptScript.ATTEMPT_LIMIT,
		date if date != "" else "absent",
		"yes" if available else "no",
		"yes" if playable else "no",
		"yes" if run_active else "no",
		"yes" if loading_done else "no",
		"true" if disabled else "false",
		because,
		",".join(reasons),
		DailyTestModeScript.status_label(),
		"on" if editor_on else "off",
		editor_lives,
		_daily_lives,
	])


func _editor_daily_test_active() -> bool:
	return _editor_daily_debug_allowed() and GameSession.editor_daily_test_enabled()


func _apply_editor_daily_test_presentation() -> void:
	if not _editor_daily_test_active():
		_daily_visual_override = -1
		_restore_server_daily_button()
		return
	_daily_visual_override = GameSession.editor_daily_test_lives
	_repaint_attempt_fish()
	if _daily_button:
		_daily_button.disabled = GameSession.editor_daily_test_lives <= 0
		_daily_button.modulate = Color.WHITE
	_apply_mode_art()
	_set_mode_note("")
	_set_mode_reset("")


func _restore_server_daily_button() -> void:
	_present_server_daily("server")


func _present_server_daily(reason: String) -> void:
	if _editor_daily_test_active():
		_apply_editor_daily_test_presentation()
		return
	var lives := _daily_lives
	var checking := _daily_checking or _status_busy
	_daily_locked = lives == 0 and not checking
	var playable := lives > 0 and not checking and not _mode_busy
	if _daily_button and not _mode_busy:
		_daily_button.disabled = not playable
		_daily_button.modulate = Color.WHITE
	_daily_paint_reason = reason
	_repaint_attempt_fish()
	_apply_mode_art()
	_log_daily_lives(reason)
	_log_daily_settled()


func _server_lives_label() -> String:
	if _daily_lives < 0:
		return "unknown"
	return str(_daily_lives)


func _fish_display_lives() -> int:
	if _editor_daily_test_active():
		return GameSession.editor_daily_test_lives
	# Hide the count until this check commits, so a click cannot land on a
	# button that already looks open.
	if _daily_checking or _status_busy:
		return -1
	return _daily_lives


func _apply_attempt_fish(remaining: int) -> void:
	_daily_lives = remaining
	if _editor_daily_test_active():
		_daily_paint_reason = "editor"
		_repaint_attempt_fish()
		return
	_present_server_daily("apply")


func _repaint_attempt_fish() -> void:
	var shown := _fish_display_lives()
	var loading := shown < 0
	for i in _daily_fish.size():
		var icon := _daily_fish[i]
		icon.use_parent_material = false
		icon.material = null
		icon.modulate = Color.WHITE
		icon.self_modulate = Color.WHITE
		icon.visible = not loading
		if loading:
			_log_fish_icon(i, shown, false, icon)
			continue
		var lit := DailyAttemptScript.fish_lit(i, shown)
		if lit:
			if _daily_fish_color == null:
				icon.visible = false
			else:
				icon.texture = _daily_fish_color
		elif _daily_fish_gray_tex != null:
			icon.texture = _daily_fish_gray_tex
		elif _daily_fish_color != null:
			icon.texture = _daily_fish_color
		_log_fish_icon(i, shown, lit, icon)
	_log_fish_count(shown)
	_note_fish_paint(shown)


func _fish_signature(shown: int) -> String:
	if shown < 0:
		return "loading"
	var parts: PackedStringArray = PackedStringArray()
	for i in DailyAttemptScript.ATTEMPT_LIMIT:
		parts.append("colored" if DailyAttemptScript.fish_lit(i, shown) else "gray")
	return ",".join(parts)


func _note_fish_paint(shown: int) -> void:
	var sig := _fish_signature(shown)
	if _daily_paint_sig != "" and sig != _daily_paint_sig and _daily_paint_reason == "layout":
		print("[daily_lives] overwrite previous=%s next=%s reason=layout" % [_daily_paint_sig, sig])
	_daily_paint_sig = sig


func _log_daily_lives(reason: String) -> void:
	var override_on := (
		DailyTestModeScript.enabled()
		or _editor_daily_test_active()
		or _daily_visual_override >= 0
	)
	var shown := _fish_display_lives() if override_on else _daily_lives
	var date := "absent"
	var course: Variant = _last_daily_status.get("course", {})
	if typeof(course) == TYPE_DICTIONARY:
		date = str(course.get("challenge_date", "")).strip_edges()
	if date == "":
		date = "absent"
	var used := "absent"
	var remaining := "absent"
	if shown >= 0:
		used = str(DailyAttemptScript.ATTEMPT_LIMIT - shown)
		remaining = str(shown)
	var colored := "loading"
	if shown >= 0:
		var count := 0
		for i in DailyAttemptScript.ATTEMPT_LIMIT:
			if DailyAttemptScript.fish_lit(i, shown):
				count += 1
		colored = str(count)
	var button_on := _daily_button != null and not _daily_button.disabled and not _mode_shows_locked()
	var fish_ready := _daily_fish.size() == DailyAttemptScript.ATTEMPT_LIMIT and _daily_fish_color != null
	var parsed := bool(_last_daily_status.get("ok", false)) and _daily_source != "inconsistent" and _daily_source != "missing"
	print("[daily_lives] mode=%s date=%s used=%s remaining=%s fish_colored=%s button_enabled=%s source=%s fish_ready=%s parsed=%s overwrite=false reason=%s" % [
		"override" if override_on else "normal",
		date,
		used,
		remaining,
		colored,
		str(button_on),
		_daily_source if _daily_source != "" else "none",
		str(fish_ready),
		str(parsed),
		reason,
	])


func _log_fish_icon(index: int, remaining: int, lit: bool, icon: TextureRect) -> void:
	var tex: Texture2D = icon.texture
	var path := ""
	if tex != null:
		path = tex.resource_path
		if path == "":
			path = "runtime-grayscale" if tex == _daily_fish_gray_tex else "runtime-texture"
	var parent_mod := Color.WHITE
	var parent := icon.get_parent()
	if parent is CanvasItem:
		parent_mod = (parent as CanvasItem).modulate
	var shader_name := ""
	if icon.material is ShaderMaterial:
		var mat := icon.material as ShaderMaterial
		shader_name = mat.shader.resource_path if mat.shader != null else "shader"
	var expected := "loading"
	if remaining >= 0:
		expected = "available" if lit else "consumed"
	print("[daily] fish index=%d expected=%s texture=%s modulate=%s self=%s parent=%s shader=%s grayscale=%s colored_pixels=%s" % [
		index,
		expected,
		path,
		icon.modulate,
		icon.self_modulate,
		parent_mod,
		shader_name if shader_name != "" else "none",
		"yes" if _daily_fish_gray_tex != null and icon.texture == _daily_fish_gray_tex else "no",
		"yes" if _texture_has_color(tex) else "no",
	])


func _log_fish_count(shown: int) -> void:
	var status := _last_daily_status
	var date := "absent"
	var course: Variant = status.get("course", {})
	if typeof(course) == TYPE_DICTIONARY:
		date = str(course.get("challenge_date", "")).strip_edges()
	if date == "":
		var parts := str(status.get("challenge_id", "")).split(":")
		if parts.size() >= 2:
			date = parts[1]
	var used := "absent"
	var remaining := "absent"
	if status.has("attempts_used"):
		used = str(int(status.get("attempts_used", 0)))
	if status.has("attempts_remaining"):
		remaining = str(int(status.get("attempts_remaining", 0)))
	var fish: PackedStringArray = []
	if shown < 0:
		fish = PackedStringArray(["loading", "loading", "loading"])
	else:
		for i in DailyAttemptScript.ATTEMPT_LIMIT:
			fish.append("colored" if DailyAttemptScript.fish_lit(i, shown) else "gray")
	var displayed := "unknown" if shown < 0 else str(shown)
	print("[daily] fish_count challenge_date=%s attempts_used=%s attempts_remaining=%s max=%d displayed=%s fish=%s" % [
		date if date != "" else "absent",
		used,
		remaining,
		DailyAttemptScript.ATTEMPT_LIMIT,
		displayed,
		",".join(fish),
	])


func _redact_player_id(raw: String) -> String:
	var clean := raw.strip_edges()
	if clean.length() <= 8:
		return "redacted" if clean != "" else ""
	return "%s…%s" % [clean.substr(0, 4), clean.substr(clean.length() - 4, 4)]


func _log_normal_daily(status: Dictionary) -> void:
	var override_on := (
		DailyTestModeScript.enabled()
		or _editor_daily_test_active()
		or _daily_visual_override >= 0
	)
	var date := "absent"
	var course: Variant = status.get("course", {})
	if typeof(course) == TYPE_DICTIONARY:
		date = str(course.get("challenge_date", "")).strip_edges()
	if date == "":
		date = "absent"
	var used := "absent"
	var remaining := "absent"
	if bool(status.get("attempts_counted", false)):
		used = str(int(status.get("attempts_used", 0)))
		remaining = str(int(status.get("attempts_remaining", 0)))
	var colored := "loading"
	if not override_on and _daily_lives >= 0:
		var count := 0
		for i in DailyAttemptScript.ATTEMPT_LIMIT:
			if DailyAttemptScript.fish_lit(i, _daily_lives):
				count += 1
		colored = str(count)
	elif override_on and GameSession.editor_daily_test_lives >= 0:
		var count := 0
		for i in DailyAttemptScript.ATTEMPT_LIMIT:
			if DailyAttemptScript.fish_lit(i, GameSession.editor_daily_test_lives):
				count += 1
		colored = str(count)
	var enabled := _daily_button != null and not _daily_button.disabled and not _mode_shows_locked()
	print("[daily] mode=%s" % ("override" if override_on else "normal"))
	print("[daily] challenge_date=%s" % date)
	print("[daily] attempts_used=%s" % used)
	print("[daily] attempts_remaining=%s" % remaining)
	print("[daily] fish_colored=%s" % colored)
	print("[daily] button_enabled=%s" % str(enabled))
	print("[daily] server_fields=%s attempted=%s" % [
		str(status.get("raw_fields", "absent")),
		str(bool(status.get("attempted", false))),
	])


func _log_daily_menu(kind: String, status: Dictionary = {}, phase: String = "", lives: int = -999) -> void:
	var shown_lives := _daily_lives if lives == -999 else lives
	var shown_phase := phase
	if shown_phase == "":
		if _status_busy or _daily_checking:
			shown_phase = "loading"
		elif _daily_lives >= 0:
			shown_phase = "confirmed"
		else:
			shown_phase = "unavailable"
	var player := ""
	if GameSession:
		player = _redact_player_id(str(GameSession.player_id))
	var period := str(status.get("challenge_id", ""))
	var course: Variant = status.get("course", {})
	if period == "" and typeof(course) == TYPE_DICTIONARY:
		period = str(course.get("challenge_id", ""))
	var used: Variant = status.get("attempts_used", "absent") if not status.is_empty() else "absent"
	var response_remaining: Variant = status.get("attempts_remaining", "absent") if not status.is_empty() else "absent"
	print("[daily] menu when=%s player=%s period=%s as_of=%s resets=%s fields=%s attempted=%s used=%s response_remaining=%s shown_lives=%s phase=%s button_enabled=%s locked=%s ok=%s error=%s" % [
		kind,
		player,
		period,
		str(status.get("as_of_unix", "")),
		str(status.get("resets_at_unix", "")),
		str(status.get("raw_fields", "")),
		str(status.get("attempted", "")),
		str(used),
		str(response_remaining),
		shown_lives,
		shown_phase,
		str(_daily_button != null and not _daily_button.disabled),
		str(_mode_shows_locked()),
		str(status.get("ok", "")),
		str(status.get("error", "")),
	])


func _log_daily_authority(status: Dictionary, merged: Dictionary, applied: bool) -> void:
	var course: Variant = status.get("course", {})
	var date := ""
	var challenge_id := str(merged.get("challenge_id", status.get("challenge_id", ""))).strip_edges()
	if typeof(course) == TYPE_DICTIONARY:
		date = str(course.get("challenge_date", "")).strip_edges()
		if challenge_id == "":
			challenge_id = str(course.get("challenge_id", "")).strip_edges()
	var counted := bool(status.get("attempts_counted", false))
	var server_used := "absent"
	var server_remaining := "absent"
	if counted:
		server_used = str(int(status.get("attempts_used", 0)))
		server_remaining = str(int(status.get("attempts_remaining", 0)))
	var local_challenge := ""
	var local_used := 0
	if GameSession:
		local_challenge = GameSession.daily_attempt_challenge.strip_edges()
		local_used = GameSession.daily_attempt_used
	var cache := local_challenge != "" or local_used > 0
	var cache_applied := bool(merged.get("store", false))
	if (
		not counted
		and local_challenge != ""
		and local_used > 0
		and (challenge_id == "" or challenge_id == local_challenge)
		and int(merged.get("lives", -1)) == 0
	):
		cache_applied = true
	var account := "none"
	var backend := get_node_or_null("/root/Backend")
	if backend != null and backend.has_method("has_session") and backend.has_session():
		account = "shared_production_player"
	elif GameSession and str(GameSession.player_id).begins_with("local_"):
		account = "local_fallback"
	var player := ""
	if GameSession:
		player = _redact_player_id(str(GameSession.player_id))
	var reason := "server_count"
	if not bool(status.get("ok", false)):
		reason = "status_unavailable"
	elif cache_applied and not counted:
		reason = "local_cache_floor"
	elif not counted:
		reason = "server_omitted_attempts_remaining"
	elif bool(status.get("attempts_inferred", false)):
		reason = "legacy_status_inferred"
	elif _daily_lives == 0:
		reason = "server_none_remaining"
	print("[daily] authority date=%s challenge=%s server_used=%s server_remaining=%s ui_lives=%d display_lives=%d local_cache=%s local_challenge=%s local_used=%d cache_applied=%s account=%s player=%s editor_binary=%s editor_hint=%s applied=%s reason=%s" % [
		date if date != "" else "absent",
		challenge_id if challenge_id != "" else "absent",
		server_used,
		server_remaining,
		_daily_lives,
		_fish_display_lives(),
		"yes" if cache else "no",
		local_challenge if local_challenge != "" else "none",
		local_used,
		"yes" if cache_applied else "no",
		account,
		player,
		str(_editor_daily_debug_allowed()),
		str(Engine.is_editor_hint()),
		str(applied),
		reason,
	])


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
	if _editor_daily_test_active():
		return GameSession.editor_daily_test_lives <= 0
	if DailyTestModeScript.enabled():
		return false
	if _daily_checking or _status_busy or _daily_lives < 0:
		return true
	return _daily_locked


func _apply_mode_art() -> void:
	if _mode_card == null:
		return
	# mode_locked and mode_unlocked are the same full sheet. The daily button
	# is already drawn locked on one and open on the other, so the card texture
	# is replaced. A second copy is not stacked on top.
	var tex := Sprites.tex("mode_locked" if _mode_shows_locked() else "mode_unlocked")
	if tex:
		_mode_card.texture = tex


func _saved_attempt_period_open() -> bool:
	var resets := int(GameSession.daily_attempt_resets_unix)
	if resets <= 0:
		return false
	var now := 0
	var backend := get_node_or_null("/root/Backend")
	if backend and backend.has_method("estimated_server_unix"):
		now = int(backend.estimated_server_unix())
	if now <= 0:
		return false
	return now < resets


func _cache_for_status_merge() -> Array:
	if not _saved_attempt_period_open():
		return ["", 0]
	return [GameSession.daily_attempt_challenge, GameSession.daily_attempt_used]


func _open_modes() -> void:
	if _modes == null:
		return
	_mode_busy = false
	_modes.visible = true
	if _editor_daily_test_active():
		_apply_editor_daily_test_presentation()
	elif _daily_checking or _status_busy:
		_arm_daily_pending()
	elif _daily_lives == 0 and (_daily_locked or _saved_attempts_spent()):
		var resets := _daily_resets_unix
		if resets <= 0:
			resets = int(GameSession.daily_attempt_resets_unix)
		_show_daily_completed(resets)
	elif _daily_status_settled():
		_apply_attempt_fish(_daily_lives)
	else:
		_set_mode_note("")
		_set_mode_reset("")
		_hold_daily_until_status()
	_layout_mode_overlay()
	if _editor_daily_test_active():
		_apply_editor_daily_test_presentation()
	_announce_editor_daily_controls()
	_log_daily_menu("open")
	if not _editor_daily_test_active() and not _daily_status_settled():
		_refresh_daily_status()


func _saved_attempts_spent() -> bool:
	if DailyTestModeScript.enabled():
		return false
	return (
		GameSession.daily_attempt_challenge.strip_edges() != ""
		and GameSession.daily_attempt_used >= DailyAttemptScript.ATTEMPT_LIMIT
	)


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


func _set_mode_note(_text: String) -> void:
	# The three fish and the locked artwork are the only status on this button.
	if _mode_note == null:
		return
	_mode_note.visible = false
	_layout_mode_status()


func _set_mode_reset(_text: String) -> void:
	if _mode_reset == null:
		return
	_mode_reset.visible = false
	_layout_mode_status()


func _on_identity_ready() -> void:
	if _editor_daily_test_active() or _mode_busy or _launching:
		return
	if not _daily_needs_session and _daily_status_settled():
		return
	_daily_needs_session = false
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
		_daily_button.modulate = Color.WHITE
	_apply_attempt_fish(0)
	_apply_mode_art()
	_set_mode_note("")
	_set_mode_reset("")


func _clear_daily_lock() -> void:
	if (_daily_checking or _status_busy) and not _editor_daily_test_active():
		_arm_daily_pending()
		return
	_daily_checking = false
	if _daily_lives <= 0:
		if _daily_lives == 0:
			_daily_locked = true
		if _daily_button and not _mode_busy:
			_daily_button.disabled = true
			_daily_button.modulate = Color.WHITE
		_apply_mode_art()
		return
	_daily_locked = false
	_daily_resets_unix = 0
	if _daily_button and not _mode_busy:
		_daily_button.disabled = false
		_daily_button.modulate = Color.WHITE
	_apply_mode_art()
	if _modes and _modes.visible and not _mode_busy:
		_set_mode_note("")
		_set_mode_reset("")
	if DailyTestModeScript.enabled():
		_apply_daily_test_override()


func _keep_daily_unavailable() -> void:
	if _editor_daily_test_active():
		# A missing session must not lock the editor-only life count.
		_apply_editor_daily_test_presentation()
		return
	var cache: Array = _cache_for_status_merge()
	var cached_used := int(cache[1])
	if str(cache[0]) != "" and cached_used >= DailyAttemptScript.ATTEMPT_LIMIT:
		_show_daily_completed(GameSession.daily_attempt_resets_unix if _daily_resets_unix <= 0 else _daily_resets_unix)
		return
	_hold_daily_until_status()


func _hold_daily_until_status() -> void:
	if DailyTestModeScript.enabled() or _editor_daily_test_active():
		return
	_apply_attempt_fish(-1)
	if _daily_button and not _daily_locked:
		_daily_button.disabled = true


func _daily_status_settled() -> bool:
	return (
		not _editor_daily_test_active()
		and not _daily_checking
		and not _status_busy
		and _daily_lives >= 0
		and bool(_last_daily_status.get("ok", false))
		and _daily_net_retry_msec == 0
	)


func _arm_daily_pending() -> void:
	if _editor_daily_test_active():
		return
	if _daily_button and not _mode_busy:
		_daily_button.disabled = true
		_daily_button.modulate = Color.WHITE
	_repaint_attempt_fish()
	_apply_mode_art()


func _colored_fish_count(lives: int) -> int:
	if lives < 0:
		return -1
	var count := 0
	for i in DailyAttemptScript.ATTEMPT_LIMIT:
		if DailyAttemptScript.fish_lit(i, lives):
			count += 1
	return count


func _log_daily_settled() -> void:
	if _editor_daily_test_active():
		return
	var shown := _fish_display_lives()
	var remaining := "absent"
	var colored := "loading"
	if shown >= 0:
		remaining = str(shown)
		colored = str(_colored_fish_count(shown))
	print("[daily] checking=%s remaining=%s fish_colored=%s button_disabled=%s" % [
		str(_daily_checking),
		remaining,
		colored,
		str(_daily_button != null and _daily_button.disabled),
	])


func _commit_daily_lives(lives: int) -> void:
	_daily_checking = false
	_status_busy = false
	if _editor_daily_test_active():
		_apply_editor_daily_test_presentation()
		return
	if lives >= 0:
		_daily_net_retry_msec = 0
		_daily_needs_session = false
	if lives == 0:
		_show_daily_completed(_daily_resets_unix)
	elif lives > 0:
		_apply_attempt_fish(lives)
	else:
		_hold_daily_until_status()


func _fail_daily_status(status: Dictionary) -> void:
	_status_busy = false
	_daily_checking = false
	_hold_daily_until_status()
	var code := int(status.get("status", 0))
	if not _editor_daily_test_active() and (code == 0 or code >= 500):
		_daily_net_retry_msec = Time.get_ticks_msec() + 30000
	else:
		_daily_net_retry_msec = 0


func _finish_daily_status(status: Dictionary, generation: int) -> void:
	if generation != _status_gen:
		return
	_status_busy = false
	if _status_again:
		_status_again = false
		_refresh_daily_status()
		if not _status_busy:
			_fail_daily_status(status)
		return
	if not is_inside_tree():
		_daily_checking = false
		return
	var verdict := DailyAttemptScript.count_verdict(status)
	_daily_source = str(verdict.get("source", "unavailable"))
	if not bool(status.get("ok", false)) or not bool(verdict.get("consistent", true)):
		if bool(status.get("ok", false)):
			print("[daily_lives] inconsistent used=%s remaining=%s" % [
				str(verdict.get("used", -1)),
				str(verdict.get("remaining", -1)),
			])
		_last_daily_status = status
		_fail_daily_status(status)
		_log_daily_authority(status, {"lives": -1, "store": false}, true)
		_log_button_disable_state(status)
		return
	var cache: Array = _cache_for_status_merge()
	var merged: Dictionary = DailyAttemptScript.merge_lives(
		str(cache[0]),
		int(cache[1]),
		status
	)
	if bool(merged.get("store", false)):
		GameSession.note_ranked_attempts(
			str(merged.get("challenge_id", "")),
			int(merged.get("used", 0)),
			int(status.get("resets_at_unix", -1)),
			bool(merged.get("authoritative", false))
		)
	var lives := int(merged.get("lives", -1))
	var course: Variant = status.get("course", {})
	if typeof(course) == TYPE_DICTIONARY and int(course.get("course_seed", 0)) != 0:
		_status_course = course
	_last_daily_status = status
	if lives >= 0:
		_daily_resets_unix = int(status.get("resets_at_unix", _daily_resets_unix))
	_commit_daily_lives(lives)
	if DailyTestModeScript.enabled():
		_apply_daily_test_override()
	if _editor_daily_test_active():
		_apply_editor_daily_test_presentation()
	_log_daily_authority(status, merged, true)
	_log_button_disable_state(status)
	print("[daily] status_ui status=%d ok=%s attempted=%s error=%s button_disabled=%s test_mode=%s editor_local=%s" % [
		int(status.get("status", 0)),
		str(bool(status.get("ok", false))),
		str(bool(status.get("attempted", false))),
		str(status.get("error", "")),
		str(_daily_button != null and _daily_button.disabled),
		DailyTestModeScript.status_label(),
		"on" if _editor_daily_test_active() else "off",
	])
	_log_normal_daily(status)


func _refresh_daily_status(follow_when_busy: bool = false) -> void:
	if _editor_daily_test_active():
		return
	if _status_busy:
		if follow_when_busy:
			_status_again = true
		return
	if _mode_busy:
		return
	var backend := get_node_or_null("/root/Backend")
	if backend == null or not backend.has_method("fetch_daily_attempt_status"):
		print("[daily] status_ui skipped error=no_backend")
		_fail_daily_status({"ok": false, "status": 0, "error": "no_backend"})
		return
	if not backend.has_method("has_session") or not backend.has_session():
		_daily_needs_session = true
		print("[daily] status_ui skipped error=no_session button_disabled=%s" % str(_daily_button != null and _daily_button.disabled))
		_fail_daily_status({"ok": false, "status": 0, "error": "no_session"})
		return
	_daily_needs_session = false
	_status_busy = true
	_daily_checking = true
	_status_gen += 1
	var gen := _status_gen
	_arm_daily_pending()
	_log_daily_settled()
	var status: Dictionary = await backend.fetch_daily_attempt_status()
	_finish_daily_status(status, gen)


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
	_apply_attempt_fish(DailyAttemptScript.ATTEMPT_LIMIT)
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
		if _daily_button:
			_daily_button.disabled = false
		_set_mode_note("")
		return
	print("[daily] practice seed=%d id=%s" % [GameSession.course_seed, GameSession.current_challenge_id()])
	await _open_game()


func _editor_test_course() -> Dictionary:
	if int(_status_course.get("course_seed", 0)) != 0 and str(_status_course.get("challenge_id", "")).strip_edges() != "":
		return _status_course.duplicate(true)
	if _status_busy:
		for _i in 300:
			await get_tree().process_frame
			if not _status_busy:
				break
		if int(_status_course.get("course_seed", 0)) != 0 and str(_status_course.get("challenge_id", "")).strip_edges() != "":
			return _status_course.duplicate(true)
	var backend := get_node_or_null("/root/Backend")
	if backend and backend.has_method("challenge_for_new_match"):
		var ready: Variant = backend.challenge_for_new_match()
		if typeof(ready) == TYPE_DICTIONARY and int(ready.get("course_seed", 0)) != 0 and str(ready.get("challenge_id", "")).strip_edges() != "":
			return ready
	if backend and backend.has_method("fetch_daily_attempt_status"):
		var status: Dictionary = await backend.fetch_daily_attempt_status()
		var course: Variant = status.get("course", {})
		if typeof(course) == TYPE_DICTIONARY and int(course.get("course_seed", 0)) != 0:
			_status_course = course
			return course.duplicate(true)
	return {}


func _start_editor_daily_test() -> void:
	if not _editor_daily_test_active() or _mode_busy:
		return
	if GameSession.editor_daily_test_lives <= 0:
		_apply_editor_daily_test_presentation()
		print("[DAILY DEBUG] Local test blocked. Lives left: 0")
		return
	_mode_busy = true
	_mode_token += 1
	var token := _mode_token
	var course := await _editor_test_course()
	if not is_inside_tree() or token != _mode_token:
		_mode_busy = false
		return
	if int(course.get("course_seed", 0)) == 0 or str(course.get("challenge_id", "")).strip_edges() == "":
		_mode_busy = false
		print("[DAILY DEBUG] Local test blocked. Daily course is not loaded.")
		_apply_editor_daily_test_presentation()
		return
	if not GameSession.begin_editor_daily_test(course):
		_mode_busy = false
		_apply_editor_daily_test_presentation()
		return
	var left := GameSession.consume_editor_daily_test_life()
	_apply_editor_daily_test_presentation()
	print("[DAILY DEBUG] Local test run started. Lives left: %d seed=%d id=%s" % [
		left,
		GameSession.course_seed,
		GameSession.current_challenge_id(),
	])
	await _open_game()


func _choose_unlimited() -> void:
	if _mode_busy:
		return
	_begin_game(GameSession.MODE_UNLIMITED)


func _choose_daily() -> void:
	if _editor_daily_test_active():
		_start_editor_daily_test()
		return
	if DailyTestModeScript.enabled():
		_start_practice_daily()
		return
	if _mode_busy or _daily_checking or _status_busy:
		_arm_daily_pending()
		print("[daily] choose blocked busy=%s checking=%s button_disabled=%s" % [
			str(_mode_busy),
			str(_daily_checking or _status_busy),
			str(_daily_button != null and _daily_button.disabled),
		])
		return
	if _daily_locked:
		print("[daily] choose blocked locked=true")
		_show_daily_completed(_daily_resets_unix)
		return
	if _daily_lives <= 0:
		print("[daily] choose blocked lives=%d" % _daily_lives)
		if _daily_lives == 0:
			_show_daily_completed(_daily_resets_unix)
		else:
			_hold_daily_until_status()
		return
	if not _daily_backend_ready():
		print("[daily] choose blocked error=backend_not_ready")
		_hold_daily_until_status()
		return
	_mode_busy = true
	_mode_token += 1
	var token := _mode_token
	if _daily_button:
		_daily_button.disabled = true
	_set_mode_note("")
	_set_mode_reset("")
	var backend := get_node_or_null("/root/Backend")
	var claim: Dictionary = {}
	if backend:
		claim = await backend.claim_daily_attempt()
	if not is_inside_tree() or token != _mode_token or _modes == null or not _modes.visible:
		if claim.get("already_used", false) and DailyAttemptScript.lives_from_claim(claim) <= 0:
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
		if claim.get("already_used", false) and DailyAttemptScript.lives_from_claim(claim) <= 0:
			_show_daily_completed(int(claim.get("resets_at_unix", 0)))
		elif claim.get("already_used", false):
			_apply_attempt_fish(DailyAttemptScript.lives_from_claim(claim))
			if GameSession.has_method("clear_claim_key"):
				GameSession.clear_claim_key()
			if _daily_button:
				_daily_button.disabled = false
			_set_mode_note("")
		elif _daily_button and not _daily_locked:
			_daily_button.disabled = false
		_set_mode_note("")
		return
	var challenge: Dictionary = claim.get("challenge", {})
	_set_mode_note("")
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
		if bool(started.get("already_started", false)) and DailyAttemptScript.lives_from_claim(started) <= 0:
			_show_daily_completed(int(claim.get("resets_at_unix", 0)))
		elif bool(started.get("already_started", false)):
			_apply_attempt_fish(DailyAttemptScript.lives_from_claim(started))
			if _daily_button:
				_daily_button.disabled = false
			_set_mode_note("")
		elif _daily_button and not _daily_locked:
			_daily_button.disabled = false
		_set_mode_note("")
		return
	print("[daily] choose enter_game attempt_id=%s seed=%d" % [
		str(challenge.get("attempt_id", "")),
		int(challenge.get("course_seed", 0)),
	])
	if bool(started.get("attempts_counted", false)):
		var started_status := {
			"ok": true,
			"attempts_counted": true,
			"attempts_remaining": int(started.get("attempts_remaining", 0)),
			"challenge_id": str(challenge.get("challenge_id", "")),
		}
		if started.has("attempts_used"):
			started_status["attempts_used"] = int(started.get("attempts_used", 0))
		var merged: Dictionary = DailyAttemptScript.merge_lives(
			GameSession.daily_attempt_challenge,
			GameSession.daily_attempt_used,
			started_status
		)
		if bool(merged.get("store", false)):
			GameSession.note_ranked_attempts(
				str(merged.get("challenge_id", "")),
				int(merged.get("used", 0)),
				int(claim.get("resets_at_unix", -1)),
				bool(merged.get("authoritative", false))
			)
		_apply_attempt_fish(int(merged.get("lives", 0)))
	_begin_claimed_game(challenge)


func _begin_claimed_game(challenge: Dictionary) -> void:
	if str(challenge.get("attempt_id", "")).strip_edges() == "":
		_mode_busy = false
		print("[daily] choose enter_game error=missing_attempt")
		if _daily_button and not _daily_locked:
			_daily_button.disabled = false
		_set_mode_note("")
		return
	if _name_edit:
		_on_name_changed(_name_edit.text)
	GameSession.begin_claimed_daily(challenge)
	await _open_game()


func _begin_game(mode: String) -> void:
	if _name_edit:
		_on_name_changed(_name_edit.text)
	GameSession.start_match(mode)
	await _open_game()


func _open_game() -> void:
	if _launching:
		return
	_launching = true
	var sprites := get_node_or_null("/root/Sprites")
	if sprites and sprites.has_method("await_gameplay"):
		await sprites.await_gameplay()
	if not is_inside_tree():
		return
	get_tree().change_scene_to_file.call_deferred("res://scenes/game/game.tscn")
