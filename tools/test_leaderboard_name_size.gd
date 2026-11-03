extends SceneTree

# Headless check that leaderboard names of 1 to 7 characters share one glyph size.
# Godot --headless --path . --script res://tools/test_leaderboard_name_size.gd

const SessionScript := preload("res://autoload/game_session.gd")

var _failed := 0


func _initialize() -> void:
	ProjectSettings.set_setting("network/http_proxy/host", "127.0.0.1")
	ProjectSettings.set_setting("network/http_proxy/port", 9)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var menu_script: GDScript = load("res://scenes/menu/main_menu.gd") as GDScript
	if menu_script == null:
		push_error("[leaderboard-names] menu script did not load")
		quit(1)
		return
	var menu = menu_script.new()
	root.add_child(menu)
	var ok := true
	ok = _check("overlay layout", _overlay_layout(menu)) and ok
	ok = _check("name mode", _name_mode(menu)) and ok
	ok = _check("score mode unchanged", _score_mode(menu)) and ok
	ok = _check("scale follows the board", _scale_ratio(menu)) and ok
	ok = _check("row positions", _row_positions(menu)) and ok
	ok = _check("representative names", _representative(menu)) and ok
	ok = _check("seven characters fit", _widest_fits(menu)) and ok
	ok = _check("all three boards", _periods(menu)) and ok
	ok = _check("arrow alignment", _arrows(menu)) and ok
	print("[leaderboard-names] ok=%s" % ok)
	quit(0 if ok else 1)


func _check(name: String, passed: bool) -> bool:
	if passed:
		print("[leaderboard-names] %s=pass" % name)
		return true
	_failed += 1
	print("[leaderboard-names] %s=FAIL" % name)
	return false


func _overlay_layout(menu) -> bool:
	var card = menu._score_card
	if card == null or card.scale != Vector2.ONE or menu.scale != Vector2.ONE:
		push_error("[leaderboard-names] overlay transform changed")
		return false
	var layout = load("res://scripts/rr.gd")
	var screen: Vector2 = layout.screen_size()
	if card.position.distance_to(Vector2.ZERO) > 0.05 or card.size.distance_to(screen) > 0.05:
		push_error("[leaderboard-names] card %s %s expected full screen %s" % [card.position, card.size, screen])
		return false
	var saved_size: Vector2 = card.size
	_show(menu, 0, ["A", "ABCDEFG"])
	if menu._score_card.size.distance_to(saved_size) > 0.05 or menu._score_card.position.distance_to(Vector2.ZERO) > 0.05:
		push_error("[leaderboard-names] names resized the overlay")
		return false
	var back_art: Rect2 = menu._score_art_rect(menu.BACK_BOX)
	if menu._score_back.position.distance_to(back_art.position) > 0.05 or menu._score_back.size.distance_to(back_art.size) > 0.05:
		push_error("[leaderboard-names] back button moved")
		return false
	var arrow := Vector2(menu.ARROW_BOX, menu.ARROW_BOX)
	if menu._score_arrow_left_icon.size.distance_to(arrow) > 0.05 or menu._score_arrow_right_icon.size.distance_to(arrow) > 0.05:
		push_error("[leaderboard-names] arrow buttons changed size")
		return false
	print("[leaderboard-names] overlay=%s at %s" % [card.size, card.position])
	return true


func _name_mode(menu) -> bool:
	if menu._score_names.size() != 10:
		push_error("[leaderboard-names] expected 10 name rows, got %d" % menu._score_names.size())
		return false
	for line in menu._score_names:
		if line._fit_box:
			push_error("[leaderboard-names] name row still auto-fits")
			return false
		if line.scale != Vector2.ONE:
			push_error("[leaderboard-names] name container is scaled")
			return false
	return true


func _score_mode(menu) -> bool:
	for line in menu._score_values:
		if not line._fit_box:
			push_error("[leaderboard-names] score column changed")
			return false
	return menu._score_values.size() == 10


func _scale_ratio(menu) -> bool:
	var saved: Vector2 = menu._score_scale
	menu._score_scale = Vector2(0.37, 0.37)
	var small: float = menu._score_name_height()
	menu._score_scale = Vector2(1.8, 1.8)
	var large: float = menu._score_name_height()
	menu._score_scale = saved
	menu._layout_scores()
	var small_art := small / 0.37
	var large_art := large / 1.8
	if not is_equal_approx(small_art, large_art):
		push_error("[leaderboard-names] font size changed with screen scale %s vs %s" % [small_art, large_art])
		return false
	return true


func _row_positions(menu) -> bool:
	for i in menu._score_names.size():
		var src: Rect2 = menu._row_content_rect(i, menu.SCORE_NAME_X, menu.SCORE_NAME_W, 2.0)
		var expected: Vector2 = menu._score_pos + src.position * menu._score_scale
		var line = menu._score_names[i]
		if line.position.distance_to(expected) > 0.05:
			push_error("[leaderboard-names] row %d moved to %s expected %s" % [i, line.position, expected])
			return false
		if absf(line.size.x - src.size.x * menu._score_scale.x) > 0.05:
			push_error("[leaderboard-names] row %d width changed" % i)
			return false
	return true


func _representative(menu) -> bool:
	var names := ["A", "AB", "ABCD", "ABCDEFG", "W", "WW", "WWWW", "WWWWWWW", "I", "8"]
	_show(menu, 0, names)
	var cap := _glyph_height(menu._score_names[0])
	if cap <= 1.0:
		push_error("[leaderboard-names] names did not draw")
		return false
	for i in names.size():
		var line = menu._score_names[i]
		var height := _glyph_height(line)
		if absf(height - cap) > 0.05:
			push_error("[leaderboard-names] %s height %.3f cap %.3f" % [names[i], height, cap])
			return false
		if menu._score_values[i].get_child_count() < 1:
			push_error("[leaderboard-names] score missing on row %d" % i)
			return false
		if not _same_aspect(line):
			push_error("[leaderboard-names] %s glyphs are stretched" % names[i])
			return false
		if line.get_child_count() > 0 and line.get_child(0).position.x < -0.05:
			push_error("[leaderboard-names] %s is not left aligned" % names[i])
			return false
	var letter_a: Vector2 = menu._score_names[0].get_child(0).size
	var pair: Vector2 = menu._score_names[5].get_child(0).size
	var quad: Vector2 = menu._score_names[6].get_child(0).size
	if pair.distance_to(quad) > 0.05:
		push_error("[leaderboard-names] W changed between 2 and 4 letters %s vs %s" % [pair, quad])
		return false
	var short_w := _ink_right(menu._score_names[0])
	var mid_w := _ink_right(menu._score_names[1])
	var four_w := _ink_right(menu._score_names[2])
	var long_w := _ink_right(menu._score_names[3])
	if not (short_w < mid_w and mid_w < four_w and four_w < long_w):
		push_error("[leaderboard-names] widths did not grow %s %s %s %s" % [short_w, mid_w, four_w, long_w])
		return false
	var w_one: Vector2 = menu._score_names[4].get_child(0).size
	var w_seven: Vector2 = menu._score_names[7].get_child(0).size
	if w_one.distance_to(w_seven) > 0.05:
		push_error("[leaderboard-names] W changed size %s vs %s" % [w_one, w_seven])
		return false
	print("[leaderboard-names] cap=%.2f A=%.1fx%.1f seven=%.1f column=%.1f" % [cap, letter_a.x, letter_a.y, long_w, menu._score_names[0].size.x])
	return true


func _widest_fits(menu) -> bool:
	var alphabet := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	var widest_ch := ""
	var widest := 0.0
	var probe = load("res://scripts/sprite_text.gd").new()
	for i in alphabet.length():
		var ch: String = alphabet.substr(i, 1)
		var sample: String = ch.repeat(SessionScript.NAME_MAX_LEN)
		var width: float = probe.layout_width(sample, 1.0)
		if width > widest:
			widest = width
			widest_ch = ch
	probe.free()
	var names: Array[String] = []
	names.append(widest_ch.repeat(SessionScript.NAME_MAX_LEN))
	for extra in ["A", "WW", "ABCD", "8888888"]:
		names.append(extra)
	_show(menu, 0, names)
	var line = menu._score_names[0]
	var name_h := _glyph_height(line)
	var score_h := _glyph_height(menu._score_values[0])
	if absf(name_h - score_h) > 1.0:
		push_error("[leaderboard-names] name height %.2f does not match score %.2f" % [name_h, score_h])
		return false
	if absf(_glyph_height(menu._score_names[1]) - name_h) > 0.05:
		push_error("[leaderboard-names] short name is a different height")
		return false
	_show(menu, 0, ["SLAMMIN"])
	menu._score_values[0].set_value("40")
	var slam = menu._score_names[0]
	var score = menu._score_values[0]
	var name_right: float = slam.position.x + _ink_right(slam)
	var score_left := 100000.0
	for child in score.get_children():
		score_left = minf(score_left, score.position.x + child.position.x)
	if name_right > score_left - 2.0:
		push_error("[leaderboard-names] SLAMMIN ends at %.1f and meets the score at %.1f" % [name_right, score_left])
		return false
	print("[leaderboard-names] name_h=%.2f score_h=%.2f slam_right=%.1f score_left=%.1f" % [name_h, score_h, name_right, score_left])
	return true


func _periods(menu) -> bool:
	var boards := [
		["A", "AB"],
		["ABCD", "ABCDEFG"],
		["W", "WWWWWWW"],
	]
	var heights: Array[float] = []
	var nodes: Array = []
	var card_size: Vector2 = menu._score_card.size
	for page in boards.size():
		_show(menu, page, boards[page])
		if menu.SCORE_PAGES[menu._score_page] not in ["daily", "weekly", "monthly"]:
			return false
		if menu._score_card.size.distance_to(card_size) > 0.05:
			push_error("[leaderboard-names] %s resized the overlay" % menu.SCORE_PAGES[page])
			return false
		heights.append(_glyph_height(menu._score_names[0]))
		heights.append(_glyph_height(menu._score_names[1]))
		if menu._score_values[0].get_child_count() < 1:
			push_error("[leaderboard-names] %s score did not draw" % menu.SCORE_PAGES[page])
			return false
		nodes.append(menu._score_names[0])
	if nodes[0] != nodes[1] or nodes[1] != nodes[2]:
		push_error("[leaderboard-names] boards do not share name rows")
		return false
	for height in heights:
		if absf(height - heights[0]) > 0.05:
			push_error("[leaderboard-names] period height %.3f vs %.3f" % [height, heights[0]])
			return false
	return true


func _arrows(menu) -> bool:
	var size := Vector2(menu.ARROW_BOX, menu.ARROW_BOX)
	var fits: Array = menu._arrow_fits(size)
	var left_fit: Rect2 = fits[0]
	var right_fit: Rect2 = fits[1]
	var layout = load("res://scripts/rr.gd")
	var ratios: Array[float] = [16.0 / 9.0, 19.5 / 9.0, 20.0 / 9.0]
	for ratio in ratios:
		var screen := Vector2(layout.VIEW_W, layout.VIEW_W * ratio)
		var scale := Vector2(screen.x / menu.SCORE_W, screen.y / menu.SCORE_H)
		var button := Rect2(menu.BACK_VISUAL.position * scale, menu.BACK_VISUAL.size * scale)
		var boxes: Array = menu._arrow_boxes_for(size, button, screen, Vector4.ZERO, left_fit, right_fit)
		if not _arrow_pair(boxes, left_fit, right_fit, button, screen, Vector4(4, 0, 4, 0), "ratio %.3f" % ratio):
			return false
		var inset_boxes: Array = menu._arrow_boxes_for(size, button, screen, Vector4(28, 0, 12, 0), left_fit, right_fit)
		if not _arrow_pair(inset_boxes, left_fit, right_fit, button, screen, Vector4(32, 0, 16, 0), "inset %.3f" % ratio):
			return false
	var left_icon: TextureRect = menu._score_arrow_left_icon
	var right_icon: TextureRect = menu._score_arrow_right_icon
	var left_btn: Button = menu._score_arrow_left_btn
	var right_btn: Button = menu._score_arrow_right_btn
	var left_art := Rect2(left_icon.position + left_fit.position, left_fit.size)
	var right_art := Rect2(right_icon.position + right_fit.position, right_fit.size)
	if left_btn.position.distance_to(left_art.position) > 0.5 or left_btn.size.distance_to(left_art.size) > 0.5:
		push_error("[leaderboard-names] left hitbox %s does not match artwork %s" % [Rect2(left_btn.position, left_btn.size), left_art])
		return false
	if right_btn.position.distance_to(right_art.position) > 0.5 or right_btn.size.distance_to(right_art.size) > 0.5:
		push_error("[leaderboard-names] right hitbox %s does not match artwork %s" % [Rect2(right_btn.position, right_btn.size), right_art])
		return false
	var home: Vector2 = left_icon.position
	var page: int = menu._score_page
	right_btn.pressed.emit()
	if menu._score_page != posmod(page + 1, 3) or left_icon.position.distance_to(home) > 0.05:
		push_error("[leaderboard-names] right arrow did not open the next board")
		return false
	left_btn.pressed.emit()
	if menu._score_page != page or right_icon.position.distance_to(left_icon.position) < 1.0:
		push_error("[leaderboard-names] left arrow did not return to the previous board")
		return false
	var live: Array = menu._score_arrow_boxes(size)
	var live_left := Rect2(live[0].position + left_fit.position, left_fit.size)
	var live_right := Rect2(live[1].position + right_fit.position, right_fit.size)
	print("[leaderboard-names] arrow art left=%s right=%s" % [live_left, live_right])
	return true


func _arrow_pair(boxes: Array, left_fit: Rect2, right_fit: Rect2, button: Rect2, screen: Vector2, limits: Vector4, label: String) -> bool:
	if boxes.size() != 2:
		return false
	var left := Rect2(boxes[0].position + left_fit.position, left_fit.size)
	var right := Rect2(boxes[1].position + right_fit.position, right_fit.size)
	var button_mid := button.position.y + button.size.y * 0.5
	var left_mid := left.position.y + left.size.y * 0.5
	var right_mid := right.position.y + right.size.y * 0.5
	if absf(left_mid - right_mid) > 0.05:
		push_error("[leaderboard-names] %s arrows are not level" % label)
		return false
	if absf(left_mid - button_mid) > 0.05 and left.position.y > 0.05 and left.end.y < screen.y - 0.05:
		push_error("[leaderboard-names] %s arrows are off the Back button center" % label)
		return false
	var gap_left: float = button.position.x - left.end.x
	var gap_right: float = right.position.x - button.end.x
	if absf(gap_left - gap_right) > 0.05 or gap_left < 8.0:
		push_error("[leaderboard-names] %s gaps %.2f and %.2f" % [label, gap_left, gap_right])
		return false
	var bounds := Rect2(limits.x, limits.y, screen.x - limits.x - limits.z, screen.y - limits.y - limits.w)
	if not bounds.encloses(left) or not bounds.encloses(right):
		push_error("[leaderboard-names] %s arrow leaves the safe screen %s %s" % [label, left, right])
		return false
	if left.intersects(button) or right.intersects(button):
		push_error("[leaderboard-names] %s arrow overlaps the Back button" % label)
		return false
	return true


func _show(menu, page: int, names: Array) -> void:
	var backend: Node = menu.get_node("/root/Backend")
	var rows: Array = []
	for entry in names:
		rows.append({"name": entry, "display_name": entry, "score": 42})
	backend.global_daily = rows if page == 0 else []
	backend.global_weekly = rows if page == 1 else []
	backend.global_monthly = rows if page == 2 else []
	menu._score_page = page
	menu._fill_scores()


func _draw_scale(line) -> float:
	var child = line.get_child(0)
	var tex: Texture2D = child.texture
	return child.size.y / float(tex.get_height())


func _glyph_height(line) -> float:
	var height := 0.0
	for child in line.get_children():
		height = maxf(height, child.size.y)
	return height


func _ink_right(line) -> float:
	var right := 0.0
	for child in line.get_children():
		right = maxf(right, child.position.x + child.size.x)
	return right


func _same_aspect(line) -> bool:
	for child in line.get_children():
		var tex: Texture2D = child.texture
		if tex == null or tex.get_width() <= 0 or tex.get_height() <= 0:
			return false
		var drawn: float = child.size.x / float(tex.get_width())
		var natural: float = child.size.y / float(tex.get_height())
		if absf(drawn - natural) > 0.001:
			return false
	return true
