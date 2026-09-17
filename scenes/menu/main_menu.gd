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
var _fish_hats: Array[TextureRect] = []
var _fish_rest: Array[Vector2] = []
var _fish_phase := PackedFloat32Array()
var _fish_speed := PackedFloat32Array()
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
var _score_scale := 1.0
var _check_t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	set_process(true)
	set_process_input(true)
	_backdrop()
	_card_scale = RR.VIEW_W / OVERLAY_W
	var card_size := Vector2(OVERLAY_W, OVERLAY_H) * _card_scale
	var fish_strip := 210.0
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
	if _home.visible:
		_bob_picker(delta)
		if _wallet_flash > 0.0:
			_wallet_flash = maxf(_wallet_flash - delta, 0.0)
			if _wallet_text:
				var pulse := 0.5 + 0.5 * sin(_wallet_flash * 18.0)
				_wallet_text.modulate = Color(1.0, pulse, pulse, 1.0)
				if _wallet_flash <= 0.0:
					_wallet_text.modulate = Color.WHITE
	if not _scores.visible:
		return
	_check_t += delta
	if _check_t < 1.0:
		return
	_check_t = 0.0
	if GameSession.refresh_boards():
		_fill_scores()


func _input(event: InputEvent) -> void:
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
	if _home.visible and _hat_clip != null and _hat_contains(pos):
		_begin_hat_drag(_hat_local(pos))
		_mark_input_handled()
		return
	if _press_button_at(pos):
		_mark_input_handled()
		return
	if _home.visible and _name_edit and _name_edit.is_visible_in_tree() and _name_edit.get_global_rect().has_point(pos):
		_name_edit.grab_focus()
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
	_name_edit.virtual_keyboard_enabled = true
	_name_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	_style_name(_name_edit)
	_name_edit.text_changed.connect(_on_name_changed)
	_name_edit.text_submitted.connect(func(_t: String): _play())
	_home.add_child(_name_edit)
	_home.add_child(_hotspot(PLAY_BOX, _play, _card_pos, _card_scale))
	_home.add_child(_hotspot(SCORE_BOX, _show_scores, _card_pos, _card_scale))
	_build_fish_picker()
	_build_hat_picker()


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


func _hat_row_y() -> float:
	return RR.VIEW_H - RR.GROUND_H + 12.0


func _build_fish_picker() -> void:
	var count := RR.FISH_IDS.size()
	var pad := 18.0
	var gap := 6.0
	var hs_bottom := _card_pos.y + (SCORE_BOX.position.y + SCORE_BOX.size.y) * _card_scale
	var row_h := 88.0
	var row_y := hs_bottom + 28.0
	row_y = minf(row_y, _hat_row_y() - row_h - 36.0)
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
		_fish_rest.append(icon.position)
		_fish_phase.append(float(i) * 1.17 + 0.31)
		_fish_speed.append(1.52 + float(i) * 0.27)
		_home.add_child(icon)
		var hat := TextureRect.new()
		hat.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		hat.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hat.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.add_child(hat)
		_fish_hats.append(hat)
		var btn := Button.new()
		btn.flat = true
		btn.position = Vector2(x, row_y)
		btn.size = Vector2(cell, row_h)
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.pressed.connect(_choose_fish.bind(i))
		_home.add_child(btn)
	_refresh_fish_pick()


func _build_hat_picker() -> void:
	var pad := 12.0
	var cell := _hat_cell
	var gap := _hat_gap
	var icon_h := 52.0
	var price_h := 24.0
	var row_h := icon_h + price_h + 6.0
	var bob := 12.0
	var row_y := _hat_row_y()
	row_y = minf(row_y, RR.VIEW_H - row_h - bob - 6.0)
	var wallet_w := 92.0
	_build_wallet(Vector2(pad, row_y + 18.0), Vector2(wallet_w, 48.0))
	_hat_clip = Control.new()
	_hat_clip.position = Vector2(pad + wallet_w + 6.0, row_y)
	_hat_clip.size = Vector2(RR.VIEW_W - pad * 2.0 - wallet_w - 6.0, row_h + bob)
	_hat_clip.mouse_filter = Control.MOUSE_FILTER_STOP
	_hat_clip.clip_contents = true
	_hat_clip.z_index = 40
	_hat_clip.gui_input.connect(_on_hat_gui)
	_home.add_child(_hat_clip)
	_hat_ids.append(-1)
	for i in RR.HAT_COUNT:
		_hat_ids.append(i)
	var count := _hat_ids.size()
	var inner_w := 4.0 + float(count) * (cell + gap) - gap
	_hat_max_scroll = maxf(0.0, inner_w - _hat_clip.size.x)
	_hat_row = Control.new()
	_hat_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hat_row.custom_minimum_size = Vector2(inner_w, row_h + bob)
	_hat_row.size = Vector2(inner_w, row_h + bob)
	_hat_clip.add_child(_hat_row)
	for n in count:
		var hat_i := _hat_ids[n]
		var x := 4.0 + float(n) * (cell + gap)
		var y := bob * 0.5
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
		var ring := Panel.new()
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ring.position = Vector2.ZERO
		ring.size = holder.size
		ring.z_index = 8
		_hat_rings.append(ring)
		holder.add_child(ring)
		var icon := TextureRect.new()
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.position = Vector2(8.0, 2.0)
		icon.size = Vector2(cell - 16.0, icon_h)
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
		var price := _make_hat_price(cell, price_h)
		price.position = Vector2(0.0, icon_h + 2.0)
		price.visible = hat_i >= 0
		price.z_index = 2
		_hat_prices.append(price)
		holder.add_child(price)
		holder.move_child(ring, holder.get_child_count() - 1)
	_refresh_hat_pick()


func _make_hat_price(cell_w: float, price_h: float) -> Control:
	var wrap := Control.new()
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.size = Vector2(cell_w, price_h)
	var coin := TextureRect.new()
	coin.texture = Sprites.tex("coin")
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin.size = Vector2(18, 18)
	coin.position = Vector2(cell_w * 0.5 - 28.0, (price_h - 18.0) * 0.5)
	wrap.add_child(coin)
	var num := SpriteTextScript.new()
	num.position = Vector2(cell_w * 0.5 - 8.0, 1.0)
	num.configure(str(RR.HAT_PRICE), 16, Vector2(40, price_h - 2.0), HORIZONTAL_ALIGNMENT_LEFT, true)
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


func _choose_hat(index: int) -> void:
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


func _choose_fish(index: int) -> void:
	GameSession.fish_index = clampi(index, 0, RR.FISH_IDS.size() - 1)
	GameSession._save()
	_refresh_fish_pick()
	_refresh_fish_hats()


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
		_place_hat_on_fish(hat, RR.FISH_IDS[i], _fish_icons[i].size)


func _place_hat_on_fish(hat: TextureRect, skin: String, box: Vector2) -> void:
	var hat_tex := hat.texture
	if hat_tex == null:
		return
	var fish_tex := Sprites.tex(skin)
	var fish_h := 64.0
	if fish_tex:
		fish_h = maxf(float(fish_tex.get_height()), 1.0)
	var k := minf(box.x, box.y) / fish_h
	var hat_size := hat_tex.get_size() * (RR.HAT_SCALE * k / RR.FISH_SCALE)
	hat.size = hat_size
	hat.position = box * 0.5 + RR.hat_anchor(skin) * k - hat_size * 0.5 + Vector2(0.0, -hat_size.y * RR.HAT_BRIM)


func _bob_picker(delta: float) -> void:
	_bob_t += delta
	for i in _fish_icons.size():
		var y := sin(_bob_t * _fish_speed[i] + _fish_phase[i]) * 11.0
		var pos := _fish_rest[i] + Vector2(0.0, y)
		_fish_icons[i].position = pos
		_fish_rings[i].position = pos
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
		_score_rows.add_child(_row_text(name, name_box, HORIZONTAL_ALIGNMENT_CENTER, false, _name_text_scale(name)))
		_score_rows.add_child(_row_text(score, score_box, HORIZONTAL_ALIGNMENT_RIGHT, true, SCORE_NUM_SCALE))


func _name_text_scale(name: String) -> float:
	var n := name.strip_edges().length()
	if n <= 4:
		return NAME_TEXT_SCALE
	var t := clampf(float(n - 4) / 10.0, 0.0, 1.0)
	return lerpf(NAME_TEXT_SCALE, NAME_TEXT_SCALE * 0.55, t)


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
	get_tree().change_scene_to_file.call_deferred("res://scenes/game/game.tscn")
