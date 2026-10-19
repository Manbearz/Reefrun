class_name DailyMissionsOverlay
extends CanvasLayer

const GlyphScript := preload("res://scripts/mission_glyph.gd")
const SpriteTextScript := preload("res://scripts/sprite_text.gd")

const ART_PATH := "res://assets/sprites/daily_missions_card.png"
const CHECK_PATH := "res://assets/sprites/checkmark.png"
const ART_SIZE := Vector2(1145, 1374)
# Missions artwork only. The baked "Tap to Jump Up" banner starts lower and stays clipped.
const CONTENT := Rect2(107, 70, 946, 1000)
const BOARD_CLIP_H := 1072.0
const SHADE := Color(0.0, 0.07, 0.16, 0.5)
const SLOTS: PackedStringArray = ["easy", "medium", "hard"]

const DESC := [
	Rect2(312, 460, 478, 68),
	Rect2(312, 604, 478, 68),
	Rect2(312, 748, 478, 68),
]
const TRACK := [
	Rect2(312, 532, 320, 40),
	Rect2(312, 676, 320, 40),
	Rect2(312, 820, 320, 40),
]
const COUNT := [
	Rect2(642, 530, 140, 44),
	Rect2(642, 674, 140, 44),
	Rect2(642, 818, 140, 44),
]
const REWARD := [
	Rect2(858, 488, 136, 76),
	Rect2(858, 632, 136, 76),
	Rect2(858, 776, 136, 76),
]
const CHECK := [
	Rect2(830, 478, 140, 96),
	Rect2(830, 622, 140, 96),
	Rect2(830, 766, 140, 96),
]
const COIN_COVER := [
	Rect2(796, 470, 176, 106),
	Rect2(796, 614, 176, 106),
	Rect2(796, 762, 176, 106),
]
const BONUS_REWARD := Rect2(858, 928, 136, 80)
const BONUS_CHECK := Rect2(830, 922, 140, 96)
const BONUS_COIN_COVER := Rect2(796, 902, 190, 128)
const ICONS := [
	Rect2(216, 481, 84, 84),
	Rect2(216, 626, 84, 84),
	Rect2(216, 771, 84, 84),
]
const STATUS := [
	Rect2(388, 961, 30, 30),
	Rect2(550, 961, 30, 30),
	Rect2(711, 961, 30, 30),
]
# Full-screen board shown from the Daily Missions button. Lobby keeps the folding card.
const SCREEN_PATH := "res://assets/sprites/main_daily_missions.png"
const SCREEN_SIZE := Vector2(941, 1672)
const SCREEN_PLATE := Color8(2, 66, 126)
const SCREEN_DESC := [
	Rect2(244, 698, 408, 64),
	Rect2(244, 846, 408, 76),
	Rect2(244, 1002, 408, 76),
]
const SCREEN_TRACK := [
	Rect2(248, 770, 270, 28),
	Rect2(248, 926, 270, 32),
	Rect2(248, 1084, 270, 32),
]
const SCREEN_COUNT := [
	Rect2(526, 766, 118, 32),
	Rect2(520, 922, 124, 34),
	Rect2(514, 1080, 136, 34),
]
const SCREEN_REWARD := [
	Rect2(668, 708, 160, 96),
	Rect2(660, 856, 172, 108),
	Rect2(660, 1014, 172, 108),
]
const SCREEN_CHECK := [
	Rect2(692, 712, 120, 90),
	Rect2(684, 864, 128, 92),
	Rect2(684, 1022, 128, 92),
]
const SCREEN_COIN := [
	Rect2(656, 692, 200, 124),
	Rect2(656, 848, 200, 124),
	Rect2(656, 1006, 200, 124),
]
const SCREEN_BONUS_REWARD := Rect2(664, 1180, 168, 104)
const SCREEN_BONUS_CHECK := Rect2(692, 1184, 120, 92)
const SCREEN_BONUS_COIN := Rect2(656, 1168, 200, 124)
const SCREEN_ICONS := [
	Rect2(0, 0, 0, 0),
	Rect2(0, 0, 0, 0),
	Rect2(0, 0, 0, 0),
]
const SCREEN_BACK := Rect2(200, 1418, 540, 168)
signal dismissed

const FOLD_SECS := 0.30
const WIDGET_SIZE := Vector2(168, 54)
const TOAST_SIZE := Vector2(210, 56)
const BORDER := Color8(146, 210, 240)

const TRACK_COLOR := Color8(1, 38, 76)
const FILL_COLOR := Color8(49, 227, 97)
const PILL := Color8(0, 39, 79)
const PANEL := Color8(0, 64, 113)
const DESC_PLATE := Color8(4, 74, 128)

var _host: Control
var _descriptions: Array[_BubbleText] = []
var _fills: Array[Panel] = []
var _counters: Array[SpriteText] = []
var _reward_text: Array[SpriteText] = []
var _reward_backs: Array[CanvasItem] = []
var _coin_covers: Array[Panel] = []
var _marks: Array[_RewardMark] = []
var _icon_holders: Array[Control] = []
var _status: Array = []
var _bonus_text: SpriteText
var _bonus_back: CanvasItem
var _bonus_cover: Panel
var _bonus_mark: _RewardMark
var _fill_ratio: Array[float] = [0.0, 0.0, 0.0]
var _applied := false
var _widget: Panel
var _widget_icon: Control
var _widget_count: SpriteText
var _widget_track: Panel
var _widget_fill: Panel
var _toast_layer: CanvasLayer
var _toast: Panel
var _toast_text: SpriteText
var _toast_queue: Array = []
var _toast_tween: Tween
var _announced := {}
var _widget_ratio := 0.0
var _mode := "hidden"
var _motion: Tween
var _shade: ColorRect
var _dismissible := false
var _screen := false
var _desc: Array = DESC
var _track: Array = TRACK
var _count: Array = COUNT
var _reward: Array = REWARD
var _check: Array = CHECK
var _coin: Array = COIN_COVER
var _icons: Array = ICONS
var _status_rect: Array = STATUS
var _bonus_reward: Rect2 = BONUS_REWARD
var _bonus_check: Rect2 = BONUS_CHECK
var _bonus_coin: Rect2 = BONUS_COIN_COVER
var _desc_color: Color = DESC_PLATE


func use_screen_board() -> void:
	_screen = true
	_desc = SCREEN_DESC
	_track = SCREEN_TRACK
	_count = SCREEN_COUNT
	_reward = SCREEN_REWARD
	_check = SCREEN_CHECK
	_coin = SCREEN_COIN
	_icons = SCREEN_ICONS
	_status_rect = []
	_bonus_reward = SCREEN_BONUS_REWARD
	_bonus_check = SCREEN_BONUS_CHECK
	_bonus_coin = SCREEN_BONUS_COIN
	_desc_color = SCREEN_PLATE


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 30
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_shade = ColorRect.new()
	_shade.color = SHADE
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade.visible = false
	_shade.gui_input.connect(_on_shade_input)
	root.add_child(_shade)
	_host = Control.new()
	_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_host.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_host.clip_contents = true
	var art_size := SCREEN_SIZE if _screen else ART_SIZE
	_host.size = art_size if _screen else Vector2(ART_SIZE.x, BOARD_CLIP_H)
	root.add_child(_host)
	var art := TextureRect.new()
	art.name = "art"
	art.texture = load(SCREEN_PATH if _screen else ART_PATH)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.position = Vector2.ZERO
	art.size = art_size
	_host.add_child(art)
	for i in SLOTS.size():
		_build_row(i)
	_bonus_text = _reward_label(_bonus_reward, "+25", true)
	_bonus_cover = _add_coin_cover(_bonus_coin)
	_bonus_mark = _add_mark(_bonus_coin)
	if _screen:
		_build_screen_back()
	for i in _status_rect.size():
		var dot := _StatusDot.new()
		dot.position = _status_rect[i].position
		dot.size = _status_rect[i].size
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_host.add_child(dot)
		_status.append(dot)
	_build_widget()
	_build_toast()
	if not get_viewport().size_changed.is_connected(layout_to_screen):
		get_viewport().size_changed.connect(layout_to_screen)
	layout_to_screen()
	refresh_from_session()


func layout_to_screen() -> void:
	if _host == null:
		return
	if _motion == null and _mode == "board":
		_apply_board_layout()
	_layout_widget()
	_layout_toast()


func mode() -> String:
	return _mode


func announced_count() -> int:
	return _announced.size()


func present(next: String, immediate := false) -> void:
	if next != "board" and next != "widget" and next != "aside":
		next = "hidden"
	var previous := _mode
	_mode = next
	if _motion:
		_motion.kill()
		_motion = null
	if next == "hidden":
		visible = false
		if _host:
			_host.visible = false
		if _widget:
			_widget.visible = false
		_clear_toast_motion()
		_apply_shade()
		return
	if next == "aside":
		_park()
		_apply_shade()
		return
	visible = true
	if next == "board":
		if immediate or previous != "widget":
			_snap_board()
		else:
			_animate_to_board()
	elif immediate or previous != "board":
		_snap_widget()
	else:
		_animate_to_widget()
	_apply_shade()
	_pump_toast()


func board_fills_screen() -> bool:
	if not _screen or _host == null or _mode != "board":
		return false
	var screen := _viewport_size()
	var scale := Vector2(screen.x / SCREEN_SIZE.x, screen.y / SCREEN_SIZE.y)
	return _host.visible and _host.position.is_equal_approx(Vector2.ZERO) and _host.scale.is_equal_approx(scale) and is_equal_approx(_host.size.x, SCREEN_SIZE.x) and is_equal_approx(_host.size.y, SCREEN_SIZE.y)


func set_dismissible(enabled: bool) -> void:
	_dismissible = enabled
	_apply_shade()


func shade_alpha() -> float:
	if _shade == null or not _shade.visible:
		return 0.0
	return _shade.modulate.a


func shade_blocks_play() -> bool:
	return _shade != null and _shade.visible and _shade.mouse_filter != Control.MOUSE_FILTER_IGNORE


func board_brightness() -> float:
	if _host == null:
		return 0.0
	return _host.modulate.a


static func fold_shade_alpha(elapsed: float) -> float:
	var u := clampf(elapsed / FOLD_SECS, 0.0, 1.0)
	return 1.0 - _cubic_in_out(u)


static func _cubic_in_out(t: float) -> float:
	if t < 0.5:
		return 4.0 * t * t * t
	var f := -2.0 * t + 2.0
	return 1.0 - (f * f * f) / 2.0


func dismiss_catches_taps() -> bool:
	return _shade != null and _shade.visible and _shade.mouse_filter == Control.MOUSE_FILTER_STOP


func card_contains(point: Vector2) -> bool:
	if _host == null or not _host.visible or _mode != "board":
		return false
	if _screen:
		var screen := _viewport_size()
		if not Rect2(Vector2.ZERO, screen).has_point(point):
			return false
		var fit := Vector2(screen.x / SCREEN_SIZE.x, screen.y / SCREEN_SIZE.y)
		var back := Rect2(SCREEN_BACK.position * fit, SCREEN_BACK.size * fit)
		return not back.has_point(point)
	var placed := _layout_transform(_viewport_size(), _safe_margins(_viewport_size()))
	var scale := float(placed.scale)
	var origin: Vector2 = placed.position
	return Rect2(origin + CONTENT.position * scale, CONTENT.size * scale).has_point(point)


func _apply_shade() -> void:
	if _shade == null:
		return
	if _motion != null:
		_set_shade_input()
		return
	if visible and _mode == "board":
		_show_shade_now()
	else:
		_hide_shade_now()


func _set_shade_input() -> void:
	if _shade == null:
		return
	var catch := _dismissible and visible and _mode == "board"
	_shade.mouse_filter = Control.MOUSE_FILTER_STOP if catch else Control.MOUSE_FILTER_IGNORE


func _show_shade_now() -> void:
	if _shade == null:
		return
	if _screen:
		_hide_shade_now()
		return
	_shade.visible = true
	_shade.modulate.a = 1.0
	_set_shade_input()


func _hide_shade_now() -> void:
	if _shade == null:
		return
	_shade.visible = false
	_shade.modulate.a = 0.0
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _on_shade_input(event: InputEvent) -> void:
	if _mode != "board" or not _dismissible:
		return
	var press := false
	var point := Vector2.ZERO
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		press = mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT
		point = mouse.position
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		press = touch.pressed
		point = touch.position
	else:
		return
	var viewport := get_viewport()
	if viewport:
		viewport.set_input_as_handled()
	if not press or card_contains(point):
		return
	present("hidden")
	dismissed.emit()


func _build_screen_back() -> void:
	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.position = SCREEN_BACK.position
	btn.size = SCREEN_BACK.size
	var empty := StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal", empty)
	btn.add_theme_stylebox_override("hover", empty)
	btn.add_theme_stylebox_override("pressed", empty)
	btn.add_theme_stylebox_override("focus", empty)
	btn.pressed.connect(_dismiss_from_back)
	_host.add_child(btn)


func _dismiss_from_back() -> void:
	if _mode != "board":
		return
	present("hidden")
	dismissed.emit()


func _park() -> void:
	visible = true
	if _host:
		_host.visible = false
	if _widget:
		_widget.visible = false
	_pump_toast()


func announce_reward(slot: String, coins: int, mission_date: String) -> void:
	if not should_announce(_announced, mission_date, slot, coins, "claimed"):
		return
	_announced["%s:%s" % [mission_date, slot]] = true
	_toast_queue.append({"coins": coins})
	_pump_toast()


static func should_announce(seen: Dictionary, mission_date: String, slot: String, coins: int, reason: String) -> bool:
	if reason != "claimed" or coins <= 0 or slot.is_empty():
		return false
	return not seen.has("%s:%s" % [mission_date, slot])


static func widget_rect(screen: Vector2, margins: Vector4) -> Rect2:
	var size := WIDGET_SIZE
	var left := margins.x
	var top := maxf(margins.y, 76.0)
	var score_left := screen.x * 0.5 - 88.0
	if left + size.x > score_left:
		size.x = minf(size.x, maxf(1.0, score_left - left))
	var fish_top := RR.VIEW_H * 0.42 - 52.0
	if top + size.y > fish_top - 12.0:
		top = maxf(margins.y, fish_top - 12.0 - size.y)
	return Rect2(left, top, size.x, size.y)


static func toast_rect(screen: Vector2, margins: Vector4) -> Rect2:
	var size := TOAST_SIZE
	var x := clampf((screen.x - size.x) * 0.5, margins.x, maxf(margins.x, screen.x - margins.z - size.x))
	var y := maxf(margins.y + 8.0, 156.0)
	var fish_top := RR.VIEW_H * 0.42 - 56.0
	if y + size.y > fish_top:
		y = maxf(margins.y, fish_top - size.y - 8.0)
	return Rect2(x, y, size.x, size.y)


static func widget_clears_play(rect: Rect2, screen: Vector2) -> bool:
	if rect.size.x < 96.0 or rect.size.y < 48.0:
		return false
	if rect.position.x < 0.0 or rect.end.x > screen.x or rect.position.y < 0.0 or rect.end.y > screen.y:
		return false
	var blockers: Array[Rect2] = [
		Rect2(12, 18, 64, 36),
		Rect2(12, 52, 170, 20),
		Rect2(screen.x * 0.5 - 88.0, 70.0, 176.0, 78.0),
		Rect2(screen.x * 0.5 - 20.0, 48.0, 40.0, 30.0),
		Rect2(screen.x - 120.0, 8.0, 112.0, 44.0),
		Rect2(RR.PLAYER_X - 50.0, RR.VIEW_H * 0.42 - 50.0, 100.0, 100.0),
		Rect2(screen.x - 56.0, RR.PLAY_TOP, 56.0, RR.PLAY_BOTTOM - RR.PLAY_TOP),
	]
	for block in blockers:
		if rect.intersects(block):
			return false
	return true


func refresh_from_session() -> void:
	var note := ""
	var backend := get_node_or_null("/root/Backend")
	if backend:
		note = str(backend.get("mission_note"))
	show_board(GameSession.mission_board, note)


func show_board(board: Dictionary, note: String) -> void:
	var slots := _slots_by_name(board)
	var loading := slots.is_empty() and note != "error"
	var failed := slots.is_empty() and note == "error"
	for i in SLOTS.size():
		var slot_name := SLOTS[i]
		var row: Dictionary = slots.get(slot_name, {})
		var reward := int(row.get("reward", DailyMissions.REWARDS.get(slot_name, 0)))
		var goal := int(row.get("goal", 0))
		var progress := int(row.get("progress", 0))
		var complete := bool(row.get("complete", false))
		var claimed := bool(row.get("claimed", false))
		var description := DailyMissions.display_text(str(row.get("description", "")))
		if description.is_empty():
			if failed:
				description = "Could not load missions" if i == 0 else ""
			elif loading:
				description = "Loading daily missions" if i == 0 else ""
		_set_description(i, description)
		var icon_text := "" if row.is_empty() else str(row.get("description", ""))
		_set_icon(i, "" if row.is_empty() else DailyMissions.icon_kind(int(row.get("mission_id", 0)), icon_text))
		var ratio := 0.0 if goal <= 0 else DailyMissions.progress_ratio(progress, goal)
		if complete:
			ratio = 1.0
		_set_fill(i, ratio)
		var shown := 0 if goal <= 0 else mini(maxi(progress, 0), goal)
		_counters[i].set_value("0/0" if goal <= 0 else "%d/%d" % [shown, goal])
		_set_reward(i, reward, complete, claimed, not row.is_empty())
		if i < _status.size():
			_status[i].set_on(claimed)
	var bonus: Dictionary = board.get("bonus", {})
	var bonus_reward := int(bonus.get("reward", DailyMissions.REWARDS.bonus))
	var bonus_claimed := bool(bonus.get("claimed", false))
	var bonus_pending := bool(bonus.get("unlocked", false)) and not bonus_claimed
	_show_bonus_reward(bonus_reward, bonus_pending, bonus_claimed)
	_sync_widget(slots)
	_applied = true


func _build_row(index: int) -> void:
	var plate := Panel.new()
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.position = _desc[index].position
	plate.size = _desc[index].size
	plate.add_theme_stylebox_override("panel", _rounded(_desc_color, 18))
	_host.add_child(plate)
	var description := _BubbleText.new()
	description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	description.position = _desc[index].position + Vector2(12, 6)
	description.size = _desc[index].size - Vector2(24, 12)
	_host.add_child(description)
	_descriptions.append(description)
	var track := Panel.new()
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.position = _track[index].position
	track.size = _track[index].size
	track.add_theme_stylebox_override("panel", _rounded(TRACK_COLOR, 18))
	_host.add_child(track)
	var fill := Panel.new()
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.position = Vector2(5, 5)
	fill.size = Vector2(0, _track[index].size.y - 10)
	fill.visible = false
	fill.add_theme_stylebox_override("panel", _rounded(FILL_COLOR, 14))
	track.add_child(fill)
	_fills.append(fill)
	var pill := Panel.new()
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.position = _count[index].position
	pill.size = _count[index].size
	pill.add_theme_stylebox_override("panel", _rounded(PILL, 16))
	_host.add_child(pill)
	var counter := SpriteTextScript.new()
	counter.configure("0/0", _count[index].size.y * 0.78, _count[index].size, HORIZONTAL_ALIGNMENT_CENTER, false, true)
	counter.position = _count[index].position
	_host.add_child(counter)
	_counters.append(counter)
	_reward_text.append(_reward_label(_reward[index], "+%d" % int(DailyMissions.REWARDS.get(SLOTS[index], 0))))
	_coin_covers.append(_add_coin_cover(_coin[index]))
	_marks.append(_add_mark(_coin[index]))
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.clip_contents = true
	holder.position = _icons[index].position
	holder.size = _icons[index].size
	_host.add_child(holder)
	_icon_holders.append(holder)


func _add_coin_cover(rect: Rect2) -> Panel:
	var cover := Panel.new()
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover.position = rect.position
	cover.size = rect.size
	cover.visible = false
	cover.add_theme_stylebox_override("panel", _rounded(_desc_color if _screen else PANEL, 8))
	_host.add_child(cover)
	return cover


func _add_mark(rect: Rect2) -> _RewardMark:
	var mark := _RewardMark.new()
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.clip_contents = true
	mark.position = rect.position
	mark.size = rect.size
	mark.visible = false
	mark.z_index = 2
	_host.add_child(mark)
	return mark


func _reward_label(rect: Rect2, value: String, bonus := false) -> SpriteText:
	var back := ColorRect.new()
	back.color = PANEL
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.position = rect.position
	back.size = rect.size
	_host.add_child(back)
	if bonus:
		_bonus_back = back
	else:
		_reward_backs.append(back)
	var text := SpriteTextScript.new()
	text.configure(value, rect.size.y * 0.86, rect.size, HORIZONTAL_ALIGNMENT_CENTER, true, true)
	text.position = rect.position
	_host.add_child(text)
	return text


func _set_description(index: int, text: String) -> void:
	_descriptions[index].show_text(text)


func _set_icon(index: int, kind: String) -> void:
	var holder := _icon_holders[index]
	if str(holder.get_meta("kind", "")) == kind and (kind.is_empty() or holder.get_child_count() > 0):
		return
	holder.set_meta("kind", kind)
	for child in holder.get_children():
		holder.remove_child(child)
		child.free()
	if kind.is_empty():
		return
	if kind == "pipe" or kind == "stopwatch" or kind == "flag" or kind == "medal":
		var glyph := GlyphScript.new()
		glyph.position = Vector2.ZERO
		glyph.size = holder.size
		holder.add_child(glyph)
		glyph.set_kind(kind)
		return
	var icon := TextureRect.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.position = Vector2.ZERO
	icon.size = holder.size
	match kind:
		"fish":
			icon.texture = Sprites.tex("fish_blue")
		"coin":
			icon.texture = Sprites.tex("coin")
		_:
			icon.texture = Sprites.tex("pipe_kelp")
	holder.add_child(icon)


func _set_fill(index: int, ratio: float) -> void:
	var fill := _fills[index]
	var inner := Vector2(_track[index].size.x - 10.0, _track[index].size.y - 10.0)
	var target := Vector2(inner.x * ratio, inner.y)
	var previous := _fill_ratio[index]
	_fill_ratio[index] = ratio
	if not _applied:
		fill.size = target
		fill.visible = ratio > 0.001
		return
	if is_equal_approx(previous, ratio):
		return
	fill.visible = true
	var tween := create_tween()
	tween.tween_property(fill, "size", target, 0.25)
	if ratio <= 0.001:
		tween.finished.connect(func() -> void:
			fill.visible = false
		)


func _set_reward(index: int, reward: int, complete: bool, claimed: bool, known: bool) -> void:
	var pending := known and complete and not claimed
	var finished := claimed or pending
	var show_amount := not finished
	_reward_text[index].visible = show_amount
	if index < _reward_backs.size():
		_reward_backs[index].visible = show_amount
	if index < _coin_covers.size():
		_coin_covers[index].visible = finished
	if claimed:
		_marks[index].set_mode("done")
	elif pending:
		_marks[index].set_mode("pending")
	else:
		_marks[index].set_mode("")
		_set_reward_text(_reward_text[index], "+%d" % reward, _reward[index].size)


func _show_bonus_reward(reward: int, pending: bool, claimed: bool) -> void:
	var finished := claimed or pending
	var show_amount := not finished
	_bonus_text.visible = show_amount
	if _bonus_back:
		_bonus_back.visible = show_amount
	if _bonus_cover:
		_bonus_cover.visible = finished
	if claimed:
		_bonus_mark.set_mode("done")
	elif pending:
		_bonus_mark.set_mode("pending")
	else:
		_bonus_mark.set_mode("")
		_set_reward_text(_bonus_text, "+%d" % reward, _bonus_reward.size)


func _slots_by_name(board: Dictionary) -> Dictionary:
	var found := {}
	var rows: Variant = board.get("slots", [])
	if typeof(rows) != TYPE_ARRAY:
		return found
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var name := str(row.get("slot", ""))
		if SLOTS.has(name):
			found[name] = row
	return found


func _set_reward_text(label: SpriteText, value: String, _box: Vector2) -> void:
	label.set_value(value)


func _viewport_size() -> Vector2:
	var tree := get_tree()
	if tree != null and tree.root != null:
		var visible := tree.root.get_visible_rect().size
		if visible.x >= 200.0 and visible.y >= 200.0:
			return visible
	return RR.screen_size()


func _safe_margins(screen: Vector2) -> Vector4:
	var window := DisplayServer.window_get_size()
	if window.x <= 0 or window.y <= 0:
		return Vector4(16, 12, 16, 12)
	var safe := DisplayServer.get_display_safe_area()
	var sx := screen.x / float(window.x)
	var sy := screen.y / float(window.y)
	var safe_right := float(window.x - safe.position.x - safe.size.x)
	var safe_bottom := float(window.y - safe.position.y - safe.size.y)
	return Vector4(
		maxf(16.0, safe.position.x * sx),
		maxf(12.0, safe.position.y * sy),
		maxf(16.0, safe_right * sx),
		maxf(12.0, safe_bottom * sy)
	)


func _layout_transform(screen: Vector2, margins: Vector4) -> Dictionary:
	var avail := Vector2(screen.x - margins.x - margins.z, screen.y - margins.y - margins.w)
	avail.x = maxf(avail.x, 64.0)
	avail.y = maxf(avail.y, 64.0)
	var scale := minf(avail.x / CONTENT.size.x, avail.y / CONTENT.size.y)
	var origin := Vector2(margins.x, margins.y) + avail * 0.5
	var content_center := CONTENT.position + CONTENT.size * 0.5
	return {
		"scale": scale,
		"position": origin - content_center * scale,
	}


func _apply_board_layout() -> void:
	if _host == null:
		return
	if _screen:
		var screen := _viewport_size()
		_host.position = Vector2.ZERO
		_host.scale = Vector2(screen.x / SCREEN_SIZE.x, screen.y / SCREEN_SIZE.y)
		_host.modulate.a = 1.0
		return
	var placed := _layout_transform(_viewport_size(), _safe_margins(_viewport_size()))
	var scale := float(placed.scale)
	_host.scale = Vector2(scale, scale)
	_host.position = placed.position
	_host.modulate.a = 1.0


func _snap_board() -> void:
	_apply_board_layout()
	_host.visible = true
	if _widget:
		_widget.visible = false
		_widget.modulate.a = 1.0
		_widget.scale = Vector2.ONE


func _snap_widget() -> void:
	_apply_board_layout()
	_host.visible = false
	_layout_widget()
	if _widget:
		_widget.visible = true
		_widget.modulate.a = 1.0
		_widget.scale = Vector2.ONE


func _animate_to_widget() -> void:
	if _host == null or _widget == null:
		_snap_widget()
		return
	_host.visible = true
	_layout_widget()
	_widget.visible = true
	_widget.modulate.a = 0.0
	_widget.scale = Vector2(0.86, 0.86)
	var collapsed := _collapsed_transform()
	var duration := FOLD_SECS
	_show_shade_now()
	_motion = create_tween()
	_motion.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_motion.set_parallel(true)
	_motion.tween_property(_host, "position", collapsed.position, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_motion.tween_property(_host, "scale", Vector2.ONE * collapsed.scale, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_motion.tween_property(_host, "modulate:a", 0.0, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_motion.tween_property(_shade, "modulate:a", 0.0, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_motion.tween_property(_widget, "modulate:a", 1.0, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_motion.tween_property(_widget, "scale", Vector2.ONE, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_motion.set_parallel(false)
	_motion.chain().tween_callback(_finish_widget)


func _animate_to_board() -> void:
	if _host == null or _widget == null:
		_snap_board()
		return
	_apply_board_layout()
	var full_pos := _host.position
	var full_scale := _host.scale
	var collapsed := _collapsed_transform()
	_host.visible = true
	_host.position = collapsed.position
	_host.scale = Vector2.ONE * collapsed.scale
	_host.modulate.a = 0.0
	_layout_widget()
	_widget.visible = true
	_widget.modulate.a = 1.0
	_shade.visible = true
	_shade.modulate.a = 0.0
	_set_shade_input()
	var duration := FOLD_SECS
	_motion = create_tween()
	_motion.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_motion.set_parallel(true)
	_motion.tween_property(_host, "position", full_pos, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_motion.tween_property(_host, "scale", full_scale, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_motion.tween_property(_host, "modulate:a", 1.0, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_motion.tween_property(_shade, "modulate:a", 1.0, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_motion.tween_property(_widget, "modulate:a", 0.0, duration * 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_motion.set_parallel(false)
	_motion.chain().tween_callback(_finish_board)


func _finish_widget() -> void:
	_motion = null
	if _mode != "widget":
		return
	_host.visible = false
	_host.modulate.a = 1.0
	_apply_board_layout()
	if _widget:
		_widget.visible = true
		_widget.modulate.a = 1.0
		_widget.scale = Vector2.ONE
	_hide_shade_now()


func _finish_board() -> void:
	_motion = null
	if _mode != "board":
		return
	_apply_board_layout()
	_host.visible = true
	if _widget:
		_widget.visible = false
		_widget.modulate.a = 1.0
		_widget.scale = Vector2.ONE
	_show_shade_now()


func _collapsed_transform() -> Dictionary:
	var widget := widget_rect(_viewport_size(), _safe_margins(_viewport_size()))
	var center := widget.position + widget.size * 0.5
	var fit := minf(widget.size.x / ART_SIZE.x, widget.size.y / ART_SIZE.y)
	return {
		"scale": fit,
		"position": center - ART_SIZE * 0.5 * fit,
	}


func _build_widget() -> void:
	_widget = Panel.new()
	_widget.visible = false
	_widget.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_widget.add_theme_stylebox_override("panel", _plate_style(PANEL, 16))
	_host.get_parent().add_child(_widget)
	_widget_icon = Control.new()
	_widget_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_widget.add_child(_widget_icon)
	var medal := GlyphScript.new()
	medal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	medal.position = Vector2.ZERO
	medal.size = Vector2(38, 38)
	_widget_icon.add_child(medal)
	medal.set_kind("medal")
	_widget_count = SpriteTextScript.new()
	_widget_count.configure("0/3", 22, Vector2(90, 28), HORIZONTAL_ALIGNMENT_LEFT, true)
	_widget.add_child(_widget_count)
	_widget_track = Panel.new()
	_widget_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_widget_track.add_theme_stylebox_override("panel", _rounded(TRACK_COLOR, 4))
	_widget.add_child(_widget_track)
	_widget_fill = Panel.new()
	_widget_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_widget_fill.visible = false
	_widget_fill.add_theme_stylebox_override("panel", _rounded(FILL_COLOR, 3))
	_widget_track.add_child(_widget_fill)
	_silence(_widget)


func _build_toast() -> void:
	_toast_layer = CanvasLayer.new()
	_toast_layer.layer = 48
	_toast_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_toast_layer)
	_toast = Panel.new()
	_toast.visible = false
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.add_theme_stylebox_override("panel", _plate_style(PANEL, 18))
	_toast_layer.add_child(_toast)
	var mark := TextureRect.new()
	mark.texture = load(CHECK_PATH)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.position = Vector2(8, 8)
	mark.size = Vector2(40, 40)
	_toast.add_child(mark)
	var coin := TextureRect.new()
	coin.texture = Sprites.tex("coin")
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin.position = Vector2(52, 12)
	coin.size = Vector2(32, 32)
	_toast.add_child(coin)
	_toast_text = SpriteTextScript.new()
	_toast_text.configure("+0", 26, Vector2(110, 36), HORIZONTAL_ALIGNMENT_LEFT, true)
	_toast_text.position = Vector2(90, 10)
	_toast.add_child(_toast_text)
	_silence(_toast)


func _layout_widget() -> void:
	if _widget == null:
		return
	var rect := widget_rect(_viewport_size(), _safe_margins(_viewport_size()))
	_widget.position = rect.position
	_widget.size = rect.size
	_widget.pivot_offset = rect.size * 0.5
	_widget_icon.position = Vector2(8, (rect.size.y - 38.0) * 0.5)
	_widget_icon.size = Vector2(38, 38)
	_widget_count.position = Vector2(52, 4)
	_widget_count.size = Vector2(maxf(40.0, rect.size.x - 60.0), 26)
	_widget_track.position = Vector2(52, rect.size.y - 16.0)
	_widget_track.size = Vector2(maxf(36.0, rect.size.x - 64.0), 8)
	_widget_fill.position = Vector2(1, 1)
	_apply_widget_fill()


func _layout_toast() -> void:
	if _toast == null:
		return
	var rect := toast_rect(_viewport_size(), _safe_margins(_viewport_size()))
	_toast.position = rect.position
	_toast.size = rect.size
	_toast.pivot_offset = rect.size * 0.5


func _sync_widget(slots: Dictionary) -> void:
	if _widget_count == null:
		return
	var progress := claimed_progress(slots)
	_widget_count.set_value("%d/3" % int(progress.x))
	_widget_ratio = progress.y
	_apply_widget_fill()


static func claimed_progress(slots: Dictionary) -> Vector2:
	var claimed := 0
	var ratio_sum := 0.0
	for slot_name in SLOTS:
		var row: Dictionary = slots.get(slot_name, {})
		var goal := int(row.get("goal", 0))
		var amount := int(row.get("progress", 0))
		if bool(row.get("claimed", false)):
			claimed += 1
			ratio_sum += 1.0
		elif goal > 0:
			ratio_sum += clampf(float(mini(maxi(amount, 0), goal)) / float(goal), 0.0, 1.0)
	return Vector2(claimed, ratio_sum / float(SLOTS.size()))


func _apply_widget_fill() -> void:
	if _widget_fill == null or _widget_track == null:
		return
	var inner := maxf(0.0, _widget_track.size.x - 2.0)
	_widget_fill.size = Vector2(inner * _widget_ratio, maxf(4.0, _widget_track.size.y - 2.0))
	_widget_fill.visible = _widget_ratio > 0.001


func _pump_toast() -> void:
	if _toast == null or _toast_tween != null or _toast_queue.is_empty():
		return
	if _mode == "hidden":
		return
	var item: Dictionary = _toast_queue.pop_front()
	_toast_text.set_value("+%d" % int(item.get("coins", 0)))
	_layout_toast()
	_toast.visible = true
	_toast.modulate.a = 0.0
	_toast.scale = Vector2(0.92, 0.92)
	_toast_tween = create_tween()
	_toast_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_toast_tween.parallel().tween_property(_toast, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_toast_tween.chain().tween_interval(1.15)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_toast_tween.finished.connect(_finish_toast, CONNECT_ONE_SHOT)


func _clear_toast_motion() -> void:
	if _toast_tween:
		_toast_tween.kill()
		_toast_tween = null
	if _toast:
		_toast.visible = false
		_toast.scale = Vector2.ONE


func _finish_toast() -> void:
	_toast_tween = null
	if _toast:
		_toast.visible = false
		_toast.scale = Vector2.ONE
	_pump_toast()


func _plate_style(color: Color, radius: int) -> StyleBoxFlat:
	var style := _rounded(color, radius)
	style.border_color = BORDER
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.shadow_color = Color(0, 0.05, 0.12, 0.35)
	style.shadow_size = 5
	return style


func _silence(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_silence(child)


func _rounded(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style


class _BubbleText extends Control:
	var _value := ""
	var line_count := 1

	func show_text(value: String) -> void:
		var next := value.strip_edges()
		if next == _value and get_child_count() > 0:
			return
		_value = next
		_rebuild()

	func _rebuild() -> void:
		for child in get_children():
			remove_child(child)
			child.free()
		line_count = 1
		if _value.is_empty() or size.x < 8.0 or size.y < 8.0:
			return
		var words := _value.to_upper().split(" ", false)
		var max_h := _sample_height(words)
		var best_lines: Array = []
		var best_scale := 18.0 / max_h
		for px in range(int(size.y), 17, -1):
			var scale := float(px) / max_h
			var packed := _pack(words, scale, max_h)
			if packed.is_empty():
				continue
			var lines := packed.size()
			var block := float(px) * float(lines) + 4.0 * float(lines - 1)
			if block <= size.y + 0.5:
				best_lines = packed
				best_scale = scale
				line_count = lines
				break
		if best_lines.is_empty():
			best_lines = _force_lines(words)
			line_count = best_lines.size()
		_paint(best_lines, best_scale, max_h)

	func _sample_height(words: PackedStringArray) -> float:
		var max_h := 1.0
		for word in words:
			for i in word.length():
				var tex := _glyph(word.substr(i, 1))
				if tex:
					max_h = maxf(max_h, float(tex.get_height()))
		return max_h

	func _pack(words: PackedStringArray, scale: float, max_h: float) -> Array:
		var lines: Array = []
		var current: PackedStringArray = PackedStringArray()
		for word in words:
			var trial := current.duplicate()
			trial.append(word)
			if current.is_empty() or _line_width(trial, scale, max_h) <= size.x:
				current = trial
				continue
			lines.append(current)
			current = PackedStringArray([word])
			if lines.size() >= 2:
				return []
		if not current.is_empty():
			lines.append(current)
		if lines.size() > 2:
			return []
		for line in lines:
			if _line_width(line, scale, max_h) > size.x + 0.5:
				return []
		return lines

	func _force_lines(words: PackedStringArray) -> Array:
		var lines: Array = [PackedStringArray(), PackedStringArray()]
		var mid := maxi(1, int(words.size() / 2.0))
		if words.size() == 1:
			lines[0] = PackedStringArray([words[0]])
			return [lines[0]]
		for i in words.size():
			lines[0 if i < mid else 1].append(words[i])
		if lines[1].is_empty():
			return [lines[0]]
		return lines

	func _paint(lines: Array, scale: float, max_h: float) -> void:
		var heights: Array[float] = []
		var scales: Array[float] = []
		for line in lines:
			var used := scale
			var width := _line_width(line, used, max_h)
			if width > size.x and width > 0.0:
				used *= size.x / width
			scales.append(used)
			heights.append(max_h * used)
		var gap := 4.0 if lines.size() > 1 else 0.0
		var block := gap * float(lines.size() - 1)
		for h in heights:
			block += h
		var y := maxf(0.0, (size.y - block) * 0.5)
		for i in lines.size():
			_paint_line(lines[i], y, scales[i], max_h)
			y += heights[i] + gap

	func _paint_line(words: PackedStringArray, y: float, scale: float, max_h: float) -> void:
		var total := _line_width(words, scale, max_h)
		var x := maxf(0.0, (size.x - total) * 0.5)
		var prev := false
		for w in words.size():
			if w > 0:
				x += max_h * scale * 0.34
				prev = false
			var word := str(words[w])
			for i in word.length():
				var tex := _glyph(word.substr(i, 1))
				var width := max_h * scale * 0.34
				if tex:
					width = float(tex.get_width()) * scale
				if prev and tex:
					x += width * 0.08
				prev = tex != null
				if tex == null:
					x += width
					continue
				var dh := float(tex.get_height()) * scale
				var digit := TextureRect.new()
				digit.texture = tex
				digit.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				digit.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				digit.mouse_filter = Control.MOUSE_FILTER_IGNORE
				digit.size = Vector2(width, dh)
				digit.position = Vector2(x, y + maxf(0.0, (max_h * scale - dh) * 0.5))
				add_child(digit)
				x += width

	func _line_width(words: PackedStringArray, scale: float, max_h: float) -> float:
		var total := 0.0
		for w in words.size():
			if w > 0:
				total += max_h * scale * 0.34
			var word := str(words[w])
			var prev := false
			for i in word.length():
				var tex := _glyph(word.substr(i, 1))
				var width := max_h * scale * 0.34
				if tex:
					width = float(tex.get_width()) * scale
				if prev and tex:
					total += width * 0.08
				total += width
				prev = tex != null
		return total

	func _glyph(ch: String) -> Texture2D:
		return Sprites.glyph(ch)


class _RewardMark extends Control:
	var _mode := ""
	var _spin := 0.0
	var _check: Texture2D

	func _ready() -> void:
		_check = load(CHECK_PATH)

	func set_mode(next: String) -> void:
		_mode = next
		visible = next == "done" or next == "pending"
		set_process(next == "pending")
		queue_redraw()

	func _process(delta: float) -> void:
		_spin += delta
		queue_redraw()

	func _draw() -> void:
		if _mode == "done":
			_draw_check()
		elif _mode == "pending":
			_draw_pending()

	func _draw_check() -> void:
		if _check == null:
			_check = load(CHECK_PATH)
		if _check == null:
			return
		var tex_size := _check.get_size()
		if tex_size.x < 1.0 or tex_size.y < 1.0:
			return
		# The glyph fills most of the file. Scale that body over the coin stack.
		var body := Rect2(tex_size.x * 0.051, tex_size.y * 0.079, tex_size.x * 0.924, tex_size.y * 0.877)
		var fitted := maxf(size.x / body.size.x, size.y / body.size.y)
		var draw_size := tex_size * fitted
		var body_size := body.size * fitted
		var origin := (size - body_size) * 0.5 - body.position * fitted
		draw_texture_rect(_check, Rect2(origin, draw_size), false)

	func _draw_pending() -> void:
		var center := size * 0.5
		var radius := minf(size.x, size.y) * 0.28
		draw_circle(center, radius, Color8(0, 58, 102))
		draw_arc(center, radius * 0.72, 0, TAU, 32, Color8(186, 226, 246), maxf(3.0, radius * 0.12))
		for i in 3:
			var angle := _spin * 2.4 + float(i) * TAU / 3.0
			var dot := center + Vector2(cos(angle), sin(angle)) * radius * 0.34
			draw_circle(dot, radius * 0.14, Color8(214, 246, 255))


class _StatusDot extends Control:
	var _on := false

	func set_on(value: bool) -> void:
		_on = value
		visible = value
		queue_redraw()

	func _draw() -> void:
		if not _on:
			return
		var center := size * 0.5
		var radius := minf(size.x, size.y) * 0.42
		draw_circle(center, radius, Color8(49, 227, 97))
		var mark := PackedVector2Array([
			center + Vector2(-radius * 0.45, 0.05 * radius),
			center + Vector2(-radius * 0.1, radius * 0.4),
			center + Vector2(radius * 0.5, -radius * 0.4),
		])
		draw_polyline(mark, Color(0.95, 1, 1), maxf(2.0, radius * 0.28), true)
