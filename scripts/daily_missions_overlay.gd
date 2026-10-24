class_name DailyMissionsOverlay
extends CanvasLayer

const GlyphScript := preload("res://scripts/mission_glyph.gd")
const ButtonFeedbackScript := preload("res://scripts/button_feedback.gd")
const SpriteTextScript := preload("res://scripts/sprite_text.gd")

const ART_PATH := "res://assets/sprites/daily_missions_card_board.png"
const CHECK_PATH := "res://assets/sprites/checkmark.png"
const ART_SIZE := Vector2(1145, 1374)
# Missions artwork only. The baked "Tap to Jump Up" banner starts lower and stays clipped.
const CONTENT := Rect2(107, 70, 946, 1000)
const BOARD_CLIP_H := 1072.0
const SHADE := Color(0.0, 0.07, 0.16, 0.5)
const SLOTS: PackedStringArray = ["easy", "medium", "hard"]

const DESC := [
	Rect2(348, 482, 430, 50),
	Rect2(348, 626, 430, 50),
	Rect2(348, 772, 430, 50),
]
# Interior of the painted bar, inside the frame. The fill is clipped to this groove.
const TRACK := [
	Rect2(344, 538, 300, 30),
	Rect2(344, 683, 300, 30),
	Rect2(344, 828, 300, 30),
]
const LOBBY_COIN := [
	Rect2(802, 476, 71, 92),
	Rect2(802, 622, 72, 92),
	Rect2(802, 769, 72, 93),
]
const LOBBY_COIN_TEX: PackedStringArray = [
	"res://assets/sprites/lobby_coin_1.png",
	"res://assets/sprites/lobby_coin_2.png",
	"res://assets/sprites/lobby_coin_3.png",
]
const LOBBY_BONUS_COIN := Rect2(802, 910, 75, 97)
const LOBBY_BONUS_COIN_TEX := "res://assets/sprites/lobby_coin_bonus.png"
const COUNT := [
	Rect2(668, 536, 104, 34),
	Rect2(668, 681, 104, 34),
	Rect2(668, 826, 104, 34),
]
const REWARD := [
	Rect2(878, 500, 70, 52),
	Rect2(878, 645, 70, 52),
	Rect2(878, 790, 70, 52),
]
const CHECK := [
	Rect2(821, 468, 108, 108),
	Rect2(821, 613, 108, 108),
	Rect2(821, 758, 108, 108),
]
const COIN_COVER := [
	Rect2(796, 470, 176, 106),
	Rect2(796, 614, 176, 106),
	Rect2(796, 762, 176, 106),
]
const BONUS_REWARD := Rect2(888, 944, 72, 44)
const BONUS_CHECK := Rect2(830, 906, 108, 108)
const BONUS_TITLE := Rect2(368, 914, 390, 36)
const BONUS_COIN_COVER := Rect2(796, 902, 190, 128)
const ICONS := [
	Rect2(218, 486, 80, 80),
	Rect2(218, 630, 80, 80),
	Rect2(218, 776, 80, 80),
]
const STATUS := [
	Rect2(379, 963, 48, 48),
	Rect2(540, 963, 48, 48),
	Rect2(702, 963, 48, 48),
]
# Full-screen board shown from the Daily Missions button. Lobby keeps the folding card.
const SCREEN_PATH := "res://assets/sprites/main_daily_missions_board.png"
const SCREEN_SIZE := Vector2(941, 1672)
# Header, board, and BACK button. Side water outside this band may be cropped.
const SCREEN_KEEP := Rect2(64, 140, 820, 1476)
# Icon circles through the reward checks. This is the part that must stay on screen.
const SCREEN_FOCUS := Rect2(108, 140, 780, 1476)
# Right edge of the blue mission card. The picture shifts so this meets the screen.
const SCREEN_CARD_RIGHT := 865.0
const SCREEN_WATER := Color8(2, 16, 40)
const COIN_ICON := "res://assets/ui/mission_icons/collect_coins.png"
# Name band between the icon and the coin. Taller than the old caption so one short line reads large.
const SCREEN_DESC := [
	Rect2(220, 684, 458, 76),
	Rect2(220, 812, 458, 106),
	Rect2(222, 968, 456, 108),
]
# Interior of the painted capsule, after the baked green fill was removed.
const SCREEN_TRACK := [
	Rect2(254, 768, 260, 26),
	Rect2(254, 928, 260, 26),
	Rect2(254, 1086, 260, 26),
]
const SCREEN_COUNT := [
	Rect2(528, 764, 108, 32),
	Rect2(528, 924, 108, 32),
	Rect2(528, 1082, 108, 32),
]
# Number, then the coin. One size for +5, +10, +20, and the +25 bonus.
const REWARD_TEXT_H := 42.0
const REWARD_COIN_H := 34.0
const REWARD_GAP := 8.0
const REWARD_CENTER_X := 755.0
const SCREEN_REWARD_CENTER := [
	Vector2(REWARD_CENTER_X, 753.0),
	Vector2(REWARD_CENTER_X, 915.0),
	Vector2(REWARD_CENTER_X, 1073.0),
]
const SCREEN_BONUS_CENTER := Vector2(REWARD_CENTER_X, 1235.0)
const SCREEN_REWARD := [
	Rect2(706.6, 732.0, 57.5, REWARD_TEXT_H),
	Rect2(689.8, 894.0, 91.1, REWARD_TEXT_H),
	Rect2(685.9, 1052.0, 98.8, REWARD_TEXT_H),
]
const SCREEN_COIN_ICON := [
	Rect2(772.1, 736.0, 31.4, REWARD_COIN_H),
	Rect2(788.9, 898.0, 31.4, REWARD_COIN_H),
	Rect2(792.7, 1056.0, 31.4, REWARD_COIN_H),
]
const SCREEN_CHECK := [
	Rect2(701, 699, 108, 108),
	Rect2(701, 861, 108, 108),
	Rect2(701, 1019, 108, 108),
]
const SCREEN_COIN := [
	Rect2(0, 0, 0, 0),
	Rect2(0, 0, 0, 0),
	Rect2(0, 0, 0, 0),
]
const SCREEN_BONUS_REWARD := Rect2(687.9, 1214.0, 94.9, REWARD_TEXT_H)
const SCREEN_BONUS_COIN_ICON := Rect2(790.8, 1218.0, 31.4, REWARD_COIN_H)
const SCREEN_BONUS_CHECK := Rect2(701, 1181, 108, 108)
# Left, middle, and right circles under "COMPLETE ALL 3 MISSIONS".
const SCREEN_STATUS := [
	Rect2(274, 1227, 50, 50),
	Rect2(415, 1227, 50, 50),
	Rect2(555, 1227, 50, 50),
]
const SCREEN_BONUS_COIN := Rect2(0, 0, 0, 0)
const SCREEN_ICONS := [
	Rect2(131, 716, 80, 80),
	Rect2(131, 868, 80, 80),
	Rect2(133, 1026, 80, 80),
]
const SCREEN_BACK := Rect2(200, 1418, 540, 168)
# Bottom of the blue mission card, and the painted top of the Back button.
const SCREEN_CARD_BOTTOM := 1328.0
const SCREEN_BACK_FACE := 1432.0
# One shared mission-name size, about a fifth smaller than the previous large captions.
const SCREEN_DESC_PX := 35.0
const SCREEN_RESET := Rect2(
	(SCREEN_SIZE.x - 580.0) * 0.5,
	(SCREEN_CARD_BOTTOM + SCREEN_BACK_FACE - 40.0) * 0.5,
	580.0,
	40.0
)
const LOBBY_RESET := Rect2(280, 430, 580, 36)
signal dismissed

const FOLD_SECS := 0.30
const WIDGET_SIZE := Vector2(168, 54)
const TOAST_SIZE := Vector2(210, 56)
const BORDER := Color8(146, 210, 240)
const REWARD_PLATE := Color8(0, 64, 116)

const TRACK_COLOR := Color8(1, 38, 76)
const FILL_COLOR := Color8(49, 227, 97)
const PANEL := Color8(0, 64, 113)

var _host: Control
var _descriptions: Array[_BubbleText] = []
var _fills: Array[Panel] = []
var _counters: Array[SpriteText] = []
var _reward_text: Array[SpriteText] = []
var _reward_backs: Array[CanvasItem] = []
var _coin_covers: Array[Panel] = []
var _coin_icons: Array[TextureRect] = []
var _marks: Array[_RewardMark] = []
var _icon_holders: Array[Control] = []
var _status: Array = []
var _bonus_text: SpriteText
var _bonus_back: CanvasItem
var _bonus_cover: Panel
var _bonus_coin_icon: TextureRect
var _bonus_mark: _RewardMark
var _screen_fill: ColorRect
var _edge_top: TextureRect
var _edge_bottom: TextureRect
var _edge_top_tex: ImageTexture
var _edge_bottom_tex: ImageTexture
var _board_pixels: Image
var _fill_ratio: Array[float] = [0.0, 0.0, 0.0]
var _applied := false
var _countdown: _BubbleText
var _countdown_wait := 0.0
var _countdown_refresh := false
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


func use_screen_board() -> void:
	_screen = true
	_desc = SCREEN_DESC
	_track = SCREEN_TRACK
	_count = SCREEN_COUNT
	_reward = SCREEN_REWARD
	_check = SCREEN_CHECK
	_coin = SCREEN_COIN
	_icons = SCREEN_ICONS
	_status_rect = SCREEN_STATUS
	_bonus_reward = SCREEN_BONUS_REWARD
	_bonus_check = SCREEN_BONUS_CHECK
	_bonus_coin = SCREEN_BONUS_COIN


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 30
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.clip_contents = _screen
	add_child(root)
	_shade = ColorRect.new()
	_shade.color = SHADE
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade.visible = false
	_shade.gui_input.connect(_on_shade_input)
	root.add_child(_shade)
	if _screen:
		_screen_fill = ColorRect.new()
		_screen_fill.color = SCREEN_WATER
		_screen_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_screen_fill.visible = false
		root.add_child(_screen_fill)
		_edge_top = _bleed_rect()
		_edge_bottom = _bleed_rect()
		root.add_child(_edge_top)
		root.add_child(_edge_bottom)
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
	var bonus_coin := SCREEN_BONUS_COIN_ICON if _screen else LOBBY_BONUS_COIN
	var bonus_tex := COIN_ICON if _screen else LOBBY_BONUS_COIN_TEX
	_bonus_coin_icon = _add_coin_icon(bonus_coin, bonus_tex)
	if _screen:
		_place_screen_reward(_bonus_text, _bonus_coin_icon, "+25", SCREEN_BONUS_CENTER)
	_bonus_mark = _add_mark(_bonus_check)
	if _screen:
		_build_screen_back()
	else:
		var title := _BubbleText.new()
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title.position = BONUS_TITLE.position
		title.size = BONUS_TITLE.size
		_host.add_child(title)
		title.show_text("Complete all 3 missions")
	for i in _status_rect.size():
		_status.append(_add_mark(_status_rect[i]))
	_build_widget()
	_build_toast()
	_countdown = _BubbleText.new()
	_countdown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_host.add_child(_countdown)
	_place_countdown(SCREEN_RESET if _screen else LOBBY_RESET)
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
		_hide_screen_fill()
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


static func screen_board_rect(screen: Vector2, margins: Vector4) -> Rect2:
	# One scale. Fill the viewport when that still keeps the mission board on
	# screen. On a taller phone, crop the side water and pin the picture to the
	# top so the header meets the top of the screen.
	var focus := SCREEN_FOCUS
	var cover_scale := maxf(screen.x / SCREEN_SIZE.x, screen.y / SCREEN_SIZE.y)
	var fit_scale := minf(screen.x / focus.size.x, screen.y / focus.size.y)
	var scale := minf(cover_scale, fit_scale)
	var art_size := SCREEN_SIZE * scale
	var min_x := margins.x - focus.position.x * scale
	var max_x := screen.x - margins.z - (focus.position.x + focus.size.x) * scale
	if min_x > max_x:
		var mid_x := (min_x + max_x) * 0.5
		min_x = mid_x
		max_x = mid_x
	var origin_x := (screen.x - art_size.x) * 0.5
	if art_size.x >= screen.x - 0.5:
		var lo_x := maxf(min_x, screen.x - art_size.x)
		var hi_x := minf(max_x, 0.0)
		if lo_x <= hi_x:
			origin_x = (lo_x + hi_x) * 0.5
		else:
			origin_x = clampf((screen.x - art_size.x) * 0.5, minf(min_x, max_x), maxf(min_x, max_x))
	else:
		origin_x = clampf(origin_x, minf(min_x, max_x), maxf(min_x, max_x))
	if art_size.x >= screen.x - 0.5:
		var card_x := screen.x - SCREEN_CARD_RIGHT * scale
		origin_x = clampf(card_x, screen.x - art_size.x, 0.0)
	var min_y := margins.y - focus.position.y * scale
	var back_bottom := SCREEN_BACK.position.y + SCREEN_BACK.size.y
	var max_y := minf(screen.y - (focus.position.y + focus.size.y) * scale, screen.y - margins.w - back_bottom * scale)
	if min_y > max_y:
		var mid_y := (min_y + max_y) * 0.5
		min_y = mid_y
		max_y = mid_y
	var origin_y := clampf(0.0, min_y, max_y)
	if art_size.y >= screen.y - 0.5 and (origin_y > 0.5 or origin_y + art_size.y < screen.y - 0.5):
		var lo_y := maxf(min_y, screen.y - art_size.y)
		var hi_y := minf(max_y, 0.0)
		if lo_y <= hi_y:
			origin_y = lo_y
	return Rect2(Vector2(origin_x, origin_y), art_size)


func placed_screen_board() -> Rect2:
	var screen := _viewport_size()
	return screen_board_rect(screen, _safe_margins(screen))


static func screen_cover_rect(screen: Vector2) -> Rect2:
	return Rect2(Vector2.ZERO, screen)


func board_fills_screen() -> bool:
	if not _screen or _host == null or _screen_fill == null or _mode != "board":
		return false
	var screen := _viewport_size()
	var placed := placed_screen_board()
	var scale := placed.size.x / SCREEN_SIZE.x
	var covered := _screen_fill.visible and _screen_fill.position.is_equal_approx(Vector2.ZERO) and _screen_fill.size.is_equal_approx(screen)
	var content := _host.visible and _host.position.is_equal_approx(placed.position) and _host.scale.is_equal_approx(Vector2(scale, scale))
	var art_count := 0
	for child in _host.get_children():
		if child is TextureRect and str(child.name) == "art":
			art_count += 1
	var span := placed
	if _edge_top != null and _edge_top.visible:
		span = span.merge(Rect2(_edge_top.position, _edge_top.size))
	if _edge_bottom != null and _edge_bottom.visible:
		span = span.merge(Rect2(_edge_bottom.position, _edge_bottom.size))
	var fills := span.grow(1.0).encloses(Rect2(Vector2.ZERO, screen))
	return covered and content and fills and art_count == 1 and is_equal_approx(_host.size.x, SCREEN_SIZE.x) and is_equal_approx(_host.size.y, SCREEN_SIZE.y)


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
		var placed := placed_screen_board()
		var scale := placed.size.x / SCREEN_SIZE.x
		if scale <= 0.0:
			return true
		var local := (point - placed.position) / scale
		return not SCREEN_BACK.has_point(local)
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


func _place_countdown(box: Rect2) -> void:
	# Anchors keep the same spot on the scaled board at every phone size.
	var bounds := _host.size
	_countdown.anchor_left = box.position.x / bounds.x
	_countdown.anchor_top = box.position.y / bounds.y
	_countdown.anchor_right = box.end.x / bounds.x
	_countdown.anchor_bottom = box.end.y / bounds.y
	_countdown.offset_left = 0.0
	_countdown.offset_top = 0.0
	_countdown.offset_right = 0.0
	_countdown.offset_bottom = 0.0


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
	ButtonFeedbackScript.use_plate(
		btn,
		load(SCREEN_PATH) as Texture2D,
		SCREEN_BACK,
		Rect2(247, 1432, 435, 132),
		0.46,
		"blue"
	)
	_host.add_child(btn)


func _dismiss_from_back() -> void:
	if _mode != "board":
		return
	present("hidden")
	dismissed.emit()


func _park() -> void:
	visible = true
	_hide_screen_fill()
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


func _process(delta: float) -> void:
	if _countdown == null or _mode == "hidden":
		return
	_countdown_wait += delta
	if _countdown_wait < 1.0:
		return
	_countdown_wait = 0.0
	_refresh_countdown()


func _refresh_countdown() -> void:
	if _countdown == null:
		return
	var board: Dictionary = {}
	if GameSession and GameSession.get("mission_board") is Dictionary:
		board = GameSession.mission_board
	var server_now := int(board.get("server_now", 0))
	var resets_at := int(board.get("resets_at", 0))
	var fetched_at := int(board.get("fetched_at", 0))
	if server_now <= 0 or resets_at <= 0 or fetched_at <= 0:
		_countdown.show_text("")
		return
	var left := DailyMissions.remaining_seconds(server_now, resets_at, fetched_at, int(Time.get_unix_time_from_system()))
	_countdown.show_text(DailyMissions.format_countdown(left))
	if left > 0:
		_countdown_refresh = false
		return
	if _countdown_refresh:
		return
	_countdown_refresh = true
	var backend := get_node_or_null("/root/Backend")
	if backend and backend.has_method("refresh_daily_missions"):
		backend.refresh_daily_missions()


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
		var mission_id := int(row.get("mission_id", 0))
		var description := DailyMissions.display_text(str(row.get("description", "")), mission_id)
		if description.is_empty():
			if failed:
				description = "Missions Unavailable" if i == 0 else ""
			elif loading:
				description = "Loading Missions" if i == 0 else ""
		_set_description(i, description)
		_set_icon(i, 0 if row.is_empty() else int(row.get("mission_id", 0)))
		var ratio := 0.0 if goal <= 0 else DailyMissions.progress_ratio(progress, goal)
		if complete:
			ratio = 1.0
		_set_fill(i, ratio)
		var shown := 0 if goal <= 0 else mini(maxi(progress, 0), goal)
		_counters[i].set_value("0/0" if goal <= 0 else "%d/%d" % [shown, goal])
		_set_reward(i, reward, complete, claimed, not row.is_empty())
		if i < _status.size():
			_status[i].set_mode("done" if complete or claimed else "")
	var bonus: Dictionary = board.get("bonus", {})
	var bonus_reward := int(bonus.get("reward", DailyMissions.REWARDS.bonus))
	var bonus_claimed := bool(bonus.get("claimed", false))
	var bonus_pending := bool(bonus.get("unlocked", false)) and not bonus_claimed
	_show_bonus_reward(bonus_reward, bonus_pending, bonus_claimed)
	_sync_widget(slots)
	_refresh_countdown()
	_applied = true


func _build_row(index: int) -> void:
	var description := _BubbleText.new()
	description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var inset := Vector2(2, 1)
	description.position = _desc[index].position + inset
	description.size = _desc[index].size - inset * 2.0
	if _screen:
		description.max_px = SCREEN_DESC_PX
	_host.add_child(description)
	_descriptions.append(description)
	var track := Panel.new()
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.clip_contents = true
	track.position = _track[index].position
	track.size = _track[index].size
	var pad := _fill_pad()
	var groove := int(round((_track[index].size.y - pad * 2.0) * 0.5))
	track.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_host.add_child(track)
	var fill := Panel.new()
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.position = Vector2(pad, pad)
	fill.size = Vector2(0, _track[index].size.y - pad * 2.0)
	fill.visible = false
	fill.add_theme_stylebox_override("panel", _rounded(FILL_COLOR, groove))
	track.add_child(fill)
	_fills.append(fill)
	var pill := Panel.new()
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.position = _count[index].position
	pill.size = _count[index].size
	pill.visible = false
	_host.add_child(pill)
	var counter := SpriteTextScript.new()
	counter.configure("0/0", _count[index].size.y * 0.78, _count[index].size, HORIZONTAL_ALIGNMENT_CENTER, false, true)
	counter.position = _count[index].position
	_host.add_child(counter)
	_counters.append(counter)
	var amount := int(DailyMissions.REWARDS.get(SLOTS[index], 0))
	var reward_label := _reward_label(_reward[index], "+%d" % amount)
	_reward_text.append(reward_label)
	_coin_covers.append(_add_coin_cover(_coin[index]))
	var icon_rect: Rect2 = SCREEN_COIN_ICON[index] if _screen else LOBBY_COIN[index]
	var icon_tex := COIN_ICON if _screen else LOBBY_COIN_TEX[index]
	var reward_coin := _add_coin_icon(icon_rect, icon_tex)
	_coin_icons.append(reward_coin)
	if _screen:
		_place_screen_reward(reward_label, reward_coin, "+%d" % amount, SCREEN_REWARD_CENTER[index])
	_marks.append(_add_mark(_check[index]))
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
	cover.z_index = 1
	var radius := 36 if _screen else 8
	cover.add_theme_stylebox_override("panel", _rounded(Color8(1, 66, 128) if _screen else PANEL, radius))
	_host.add_child(cover)
	return cover


func _add_coin_icon(rect: Rect2, texture_path: String) -> TextureRect:
	var coin := TextureRect.new()
	coin.texture = load(texture_path) if rect.size.x > 1.0 else null
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin.position = rect.position
	coin.size = rect.size
	coin.visible = false
	coin.z_index = 4
	_host.add_child(coin)
	return coin


func _fill_pad() -> float:
	return 2.0


func _add_mark(rect: Rect2) -> _RewardMark:
	var mark := _RewardMark.new()
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.clip_contents = false
	mark.position = rect.position
	mark.size = rect.size
	mark.visible = false
	mark.z_index = 8
	_host.add_child(mark)
	return mark


func _reward_label(rect: Rect2, value: String, bonus := false) -> SpriteText:
	var back := ColorRect.new()
	back.color = Color(0, 0, 0, 0) if _screen else REWARD_PLATE
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.position = rect.position
	back.size = rect.size
	back.z_index = 1
	_host.add_child(back)
	if bonus:
		_bonus_back = back
	else:
		_reward_backs.append(back)
	var text := SpriteTextScript.new()
	text.configure(value, rect.size.y * 0.78, rect.size, HORIZONTAL_ALIGNMENT_CENTER, true, true)
	text.position = rect.position
	text.z_index = 2
	_host.add_child(text)
	return text


func _set_description(index: int, text: String) -> void:
	_descriptions[index].show_text(text)


func _set_icon(index: int, mission_id: int) -> void:
	var holder := _icon_holders[index]
	var key := str(mission_id)
	if str(holder.get_meta("kind", "")) == key and (mission_id <= 0 or holder.get_child_count() > 0):
		return
	holder.set_meta("kind", key)
	for child in holder.get_children():
		holder.remove_child(child)
		child.free()
	if mission_id <= 0 or holder.size.x < 1.0 or holder.size.y < 1.0:
		return
	var icon := _MissionIcon.new()
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.position = Vector2.ZERO
	icon.size = holder.size
	icon.show_icon(DailyMissions.icon_texture(mission_id), true)
	holder.add_child(icon)


func _set_fill(index: int, ratio: float) -> void:
	var fill := _fills[index]
	var groove: Rect2 = _track[index]
	var pad := _fill_pad()
	var inner := Vector2(maxf(0.0, groove.size.x - pad * 2.0), maxf(0.0, groove.size.y - pad * 2.0))
	fill.position = Vector2(pad, pad)
	var target := Vector2(inner.x * clampf(ratio, 0.0, 1.0), inner.y)
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


func _set_reward(index: int, reward: int, _complete: bool, claimed: bool, known: bool) -> void:
	var rewarded := known and claimed
	var show_coins := known and not rewarded
	_reward_text[index].visible = show_coins
	if index < _reward_backs.size():
		_reward_backs[index].visible = false
	if index < _coin_covers.size():
		_coin_covers[index].visible = false
	if index < _coin_icons.size():
		_coin_icons[index].visible = show_coins and _coin_icons[index].size.x > 1.0
	if show_coins:
		if _screen and index < _coin_icons.size():
			_place_screen_reward(_reward_text[index], _coin_icons[index], "+%d" % reward, SCREEN_REWARD_CENTER[index])
		else:
			_set_reward_text(_reward_text[index], "+%d" % reward, _reward[index].size)
	_marks[index].set_mode("done" if rewarded else "")


func _show_bonus_reward(reward: int, pending: bool, claimed: bool) -> void:
	var known := pending or claimed or reward > 0
	var rewarded := known and claimed
	var show_coins := known and not rewarded
	_bonus_text.visible = show_coins
	if _bonus_back:
		_bonus_back.visible = false
	if _bonus_cover:
		_bonus_cover.visible = false
	if _bonus_coin_icon:
		_bonus_coin_icon.visible = show_coins and _bonus_coin_icon.size.x > 1.0
	if show_coins:
		if _screen:
			_place_screen_reward(_bonus_text, _bonus_coin_icon, "+%d" % reward, SCREEN_BONUS_CENTER)
		else:
			_set_reward_text(_bonus_text, "+%d" % reward, _bonus_reward.size)
	_bonus_mark.set_mode("done" if rewarded else "")


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


# "+10" then the coin, centered in the blue well. Every amount uses the same size.
func _place_screen_reward(label: SpriteText, coin: TextureRect, value: String, center: Vector2) -> void:
	var text_w := label.layout_width(value, REWARD_TEXT_H, true)
	var coin_w := REWARD_COIN_H * (166.0 / 180.0)
	var left := center.x - (text_w + REWARD_GAP + coin_w) * 0.5
	var text_box := Vector2(text_w, REWARD_TEXT_H)
	label.position = Vector2(left, center.y - REWARD_TEXT_H * 0.5)
	label.configure(value, REWARD_TEXT_H, text_box, HORIZONTAL_ALIGNMENT_LEFT, true, false)
	label.resize_box(REWARD_TEXT_H, text_box)
	label.z_index = 2
	_tint_reward_plus(label)
	if coin == null:
		return
	coin.position = Vector2(left + text_w + REWARD_GAP, center.y - REWARD_COIN_H * 0.5)
	coin.size = Vector2(coin_w, REWARD_COIN_H)


func _tint_reward_plus(label: SpriteText) -> void:
	for child in label.get_children():
		var glyph := child as TextureRect
		if glyph == null or glyph.texture == null:
			continue
		if str(glyph.texture.resource_path).ends_with("alpha_plus.png"):
			glyph.modulate = Color(1.0, 0.86, 0.22)


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


func _bleed_rect() -> TextureRect:
	var strip := TextureRect.new()
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	strip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	strip.stretch_mode = TextureRect.STRETCH_SCALE
	strip.visible = false
	return strip


func _board_image() -> Image:
	if _board_pixels != null and not _board_pixels.is_empty():
		return _board_pixels
	var tex := load(SCREEN_PATH) as Texture2D
	if tex == null:
		return null
	_board_pixels = tex.get_image()
	return _board_pixels


func _continuation(from_bottom: bool, rows: int) -> Image:
	var src := _board_image()
	if src == null or src.is_empty():
		return null
	var width := src.get_width()
	var height := src.get_height()
	var band := mini(72, height)
	var img := Image.create(width, maxi(rows, 1), false, Image.FORMAT_RGBA8)
	for y in img.get_height():
		var dist := y if from_bottom else img.get_height() - 1 - y
		var local := dist % (band * 2)
		var src_y := 0
		if from_bottom:
			src_y = height - 1 - local if local < band else height - band + (local - band)
		else:
			src_y = local if local < band else band * 2 - local
		src_y = clampi(src_y, 0, height - 1)
		img.blit_rect(src, Rect2i(0, src_y, width, 1), Vector2i(0, y))
	return img


func _show_bleed(strip: TextureRect, tex: ImageTexture, gap: Rect2, from_bottom: bool, scale: float) -> ImageTexture:
	if strip == null:
		return tex
	var show := _mode == "board" and gap.size.x > 1.0 and gap.size.y > 1.0
	strip.visible = show
	if not show:
		return tex
	var rows := maxi(1, int(ceil(gap.size.y / maxf(scale, 0.001))))
	var img := _continuation(from_bottom, rows)
	if img == null:
		strip.visible = false
		return tex
	if tex == null:
		tex = ImageTexture.create_from_image(img)
	else:
		tex.set_image(img)
	strip.texture = tex
	strip.position = gap.position
	strip.size = gap.size
	return tex


func _hide_screen_fill() -> void:
	if _screen_fill == null:
		return
	_screen_fill.visible = false
	_screen_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _edge_top:
		_edge_top.visible = false
	if _edge_bottom:
		_edge_bottom.visible = false


func _apply_board_layout() -> void:
	if _host == null:
		return
	if _screen:
		var screen := _viewport_size()
		if _screen_fill:
			_screen_fill.position = Vector2.ZERO
			_screen_fill.size = screen
			_screen_fill.visible = _mode == "board"
			_screen_fill.mouse_filter = Control.MOUSE_FILTER_STOP if _mode == "board" else Control.MOUSE_FILTER_IGNORE
		var placed := placed_screen_board()
		var scale := placed.size.x / SCREEN_SIZE.x
		_host.position = placed.position
		_host.scale = Vector2(scale, scale)
		_host.modulate.a = 1.0
		var top_gap := placed.position.y
		var bottom_gap := screen.y - placed.end.y
		_edge_top_tex = _show_bleed(_edge_top, _edge_top_tex, Rect2(placed.position.x, 0.0, placed.size.x, maxf(0.0, top_gap + 1.0)), false, scale)
		_edge_bottom_tex = _show_bleed(_edge_bottom, _edge_bottom_tex, Rect2(placed.position.x, placed.end.y - 1.0, placed.size.x, maxf(0.0, bottom_gap + 1.0)), true, scale)
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
	_widget_track.clip_contents = true
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
	var max_px := 0.0

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
		var wrapped: Array = []
		var wrapped_scale := best_scale
		var limit := int(size.y)
		if max_px > 0.0:
			limit = mini(limit, int(max_px))
		for px in range(limit, 17, -1):
			var scale := float(px) / max_h
			var packed := _pack(words, scale, max_h)
			if packed.is_empty():
				continue
			var lines := packed.size()
			var block := float(px) * float(lines) + 4.0 * float(lines - 1)
			if block > size.y + 0.5:
				continue
			if lines == 1:
				best_lines = packed
				best_scale = scale
				line_count = 1
				break
			if wrapped.is_empty():
				wrapped = packed
				wrapped_scale = scale
		if best_lines.is_empty() and not wrapped.is_empty():
			best_lines = wrapped
			best_scale = wrapped_scale
			line_count = best_lines.size()
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
		var fitted := minf(size.x / body.size.x, size.y / body.size.y)
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


class _MissionIcon extends Control:
	var texture: Texture2D
	var _circular := false

	func show_icon(next: Texture2D, circular: bool) -> void:
		texture = next
		_circular = circular
		queue_redraw()

	func _draw() -> void:
		if not _circular:
			draw_rect(Rect2(Vector2.ZERO, size), Color8(0, 64, 113), true)
		if texture == null or texture.get_width() < 1 or texture.get_height() < 1:
			return
		var pad := 0.14 if _circular else 0.12
		var box := Rect2(size * pad, size * (1.0 - pad * 2.0))
		var source := Vector2(texture.get_width(), texture.get_height())
		var fit := minf(box.size.x / source.x, box.size.y / source.y)
		var drawn := source * fit
		draw_texture_rect(texture, Rect2(box.position + (box.size - drawn) * 0.5, drawn), false)
