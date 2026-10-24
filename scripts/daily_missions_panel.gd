extends Control

signal closed

const Missions := preload("res://scripts/daily_missions.gd")

var _title: Label
var _countdown: Label
var _status: Label
var _scroll: ScrollContainer
var _list: VBoxContainer
var _back: Button
var _cards := {}
var _asked_reset := false


func _ready() -> void:
	visible = false
	z_index = 90
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	resized.connect(_layout)
	var backend := get_node_or_null("/root/Backend")
	if backend and backend.has_signal("daily_missions_changed") and not backend.daily_missions_changed.is_connected(_render):
		backend.daily_missions_changed.connect(_render)
	_layout()


func open() -> void:
	visible = true
	_asked_reset = false
	_layout()
	_render()
	var backend := get_node_or_null("/root/Backend")
	if backend and backend.has_method("refresh_daily_missions"):
		backend.refresh_daily_missions()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.008, 0.05, 0.1, 0.9)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	_title = UIKit.make_label("DAILY MISSIONS", 28, Palette.FOAM)
	add_child(_title)
	_countdown = UIKit.make_label("RESETS AT MIDNIGHT", 16, Palette.SAND)
	add_child(_countdown)
	_status = UIKit.make_label("", 18, Palette.TEXT_DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 12)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	for slot in ["easy", "medium", "hard", "bonus"]:
		_cards[slot] = _make_card(slot)
		_list.add_child(_cards[slot].panel)
	_back = _make_button("BACK", Palette.MID, Palette.FOAM)
	_back.pressed.connect(func() -> void:
		visible = false
		closed.emit()
	)
	add_child(_back)


func _make_card(slot: String) -> Dictionary:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _card_style(slot))
	var margin := MarginContainer.new()
	for edge in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(edge, 14)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)
	var heading := UIKit.make_label(_heading(slot), 15, _tier_color(slot))
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(heading)
	var body := UIKit.make_label("", 16, Palette.TEXT)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(body)
	var track := Control.new()
	track.custom_minimum_size = Vector2(0, 12)
	box.add_child(track)
	var bar_bg := ColorRect.new()
	bar_bg.color = Color(0.01, 0.05, 0.08, 1)
	bar_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(bar_bg)
	var bar_fill := ColorRect.new()
	bar_fill.color = Palette.ACCENT
	bar_fill.anchor_left = 0.0
	bar_fill.anchor_top = 0.0
	bar_fill.anchor_bottom = 1.0
	bar_fill.anchor_right = 0.0
	bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(bar_fill)
	var count := UIKit.make_label("", 14, Palette.TEXT_DIM)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(count)
	var claim := _make_button("CLAIM", Palette.GOLD, Palette.DEEP)
	claim.visible = false
	claim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(claim)
	var mark := UIKit.make_label("✓ CLAIMED", 16, Palette.GOLD)
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	mark.visible = false
	box.add_child(mark)
	return {
		"panel": panel,
		"body": body,
		"bar": bar_fill,
		"count": count,
		"claim": claim,
		"mark": mark,
	}


func _process(_delta: float) -> void:
	if not visible:
		return
	_refresh_countdown()


func _render() -> void:
	var board: Dictionary = {}
	if GameSession and GameSession.get("mission_board") is Dictionary:
		board = GameSession.mission_board
	var loaded := bool(board.get("ok", false))
	_status.visible = not loaded
	_scroll.visible = loaded
	if not loaded:
		var backend := get_node_or_null("/root/Backend")
		var note := "LOADING DAILY MISSIONS"
		if backend and str(backend.get("mission_note")) == "error":
			note = "COULD NOT LOAD"
		_status.text = note
		_countdown.text = "RESETS AT MIDNIGHT"
		return
	_fill_slot("easy", _slot(board, "easy"))
	_fill_slot("medium", _slot(board, "medium"))
	_fill_slot("hard", _slot(board, "hard"))
	_fill_bonus(board.get("bonus", {}))
	_refresh_countdown()


func _fill_slot(slot: String, row: Dictionary) -> void:
	var card: Dictionary = _cards[slot]
	var reward := int(Missions.REWARDS.get(slot, 0))
	card.body.text = str(row.get("description", ""))
	var progress := int(row.get("progress", 0))
	var goal := maxi(1, int(row.get("goal", 1)))
	var complete := bool(row.get("complete", false))
	var claimed := bool(row.get("claimed", false))
	card.count.text = "%d / %d    %d COINS" % [mini(progress, goal), goal, reward]
	card.bar.anchor_right = clampf(float(progress) / float(goal), 0.0, 1.0)
	card.claim.visible = false
	_show_auto_state(card, complete and not claimed, claimed)


func _fill_bonus(row: Dictionary) -> void:
	var card: Dictionary = _cards.bonus
	var progress := int(row.get("progress", 0))
	var claimed := bool(row.get("claimed", false))
	var unlocked := bool(row.get("unlocked", false))
	card.body.text = "COMPLETE ALL 3"
	card.count.text = "%d / 3    25 COINS" % mini(progress, 3)
	card.bar.anchor_right = clampf(float(progress) / 3.0, 0.0, 1.0)
	card.claim.visible = false
	_show_auto_state(card, unlocked and not claimed, claimed)


func _refresh_countdown() -> void:
	var board: Dictionary = {}
	if GameSession and GameSession.get("mission_board") is Dictionary:
		board = GameSession.mission_board
	var server_now := int(board.get("server_now", 0))
	var resets_at := int(board.get("resets_at", 0))
	var fetched_at := int(board.get("fetched_at", 0))
	if server_now <= 0 or resets_at <= 0 or fetched_at <= 0:
		_countdown.text = "RESETS AT MIDNIGHT"
		return
	var left := Missions.remaining_seconds(server_now, resets_at, fetched_at, int(Time.get_unix_time_from_system()))
	_countdown.text = Missions.format_countdown(left)
	if left > 0:
		_asked_reset = false
		return
	if _asked_reset:
		return
	_asked_reset = true
	var backend := get_node_or_null("/root/Backend")
	if backend and backend.has_method("refresh_daily_missions"):
		backend.refresh_daily_missions()


func _show_auto_state(card: Dictionary, pending: bool, claimed: bool) -> void:
	var mark: Label = card.mark
	mark.visible = pending or claimed
	if claimed:
		mark.text = "✓"
		mark.label_settings = UIKit.font(28, Color8(49, 227, 97), true)
	elif pending:
		mark.text = "PENDING"
		mark.label_settings = UIKit.font(16, Palette.SAND, true)


func _slot(board: Dictionary, slot: String) -> Dictionary:
	var rows: Variant = board.get("slots", [])
	if typeof(rows) != TYPE_ARRAY:
		return {}
	for row in rows:
		if typeof(row) == TYPE_DICTIONARY and str(row.get("slot", "")) == slot:
			return row
	return {}


func _layout() -> void:
	var bounds := size
	if bounds.y < 200.0:
		bounds = RR.screen_size()
	var margin := 16.0
	var width := minf(bounds.x - margin * 2.0, 508.0)
	var left := (bounds.x - width) * 0.5
	_title.position = Vector2(left, 18)
	_title.size = Vector2(width, 40)
	_countdown.position = Vector2(left, 58)
	_countdown.size = Vector2(width, 28)
	var back_h := 52.0
	var back_y := bounds.y - back_h - 16.0
	_back.position = Vector2(left, back_y)
	_back.size = Vector2(width, back_h)
	var scroll_top := 96.0
	_scroll.position = Vector2(left, scroll_top)
	_scroll.size = Vector2(width, maxf(120.0, back_y - scroll_top - 12.0))
	_status.position = _scroll.position
	_status.size = Vector2(width, 80)
	_list.custom_minimum_size.x = width - 8.0
	for slot in _cards.keys():
		var body: Label = _cards[slot].body
		body.custom_minimum_size.x = width - 44.0


func _heading(slot: String) -> String:
	match slot:
		"easy":
			return "EASY  ·  5 COINS"
		"medium":
			return "MEDIUM  ·  10 COINS"
		"hard":
			return "HARD  ·  20 COINS"
		_:
			return "COMPLETE ALL 3  ·  25 COINS"


func _tier_color(slot: String) -> Color:
	match slot:
		"easy":
			return Palette.SHALLOW
		"medium":
			return Palette.GOLD
		"hard":
			return Palette.CORAL
		_:
			return Palette.FOAM


func _card_style(slot: String) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.14, 0.22, 0.96)
	style.border_color = _tier_color(slot)
	style.set_border_width_all(2)
	style.set_corner_radius_all(18)
	style.content_margin_left = 2
	style.content_margin_right = 2
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	return style


func _make_button(text: String, fill: Color, font: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 46)
	var normal := StyleBoxFlat.new()
	normal.bg_color = fill
	normal.set_corner_radius_all(16)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	var pressed := normal.duplicate()
	pressed.bg_color = fill.darkened(0.15)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", normal)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", normal)
	button.add_theme_color_override("font_color", font)
	button.add_theme_color_override("font_hover_color", font)
	button.add_theme_color_override("font_pressed_color", font)
	button.add_theme_color_override("font_disabled_color", Palette.TEXT_DIM)
	button.add_theme_font_size_override("font_size", 16)
	return button
