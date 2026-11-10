extends SceneTree

const SAMPLES: PackedStringArray = [
	"0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
	"00", "01", "10", "11", "22", "88", "99",
	"100", "101", "111", "300", "888", "999", "1000", "8888", "9999", "10000",
	"0/2", "1/2", "2/2", "0/10", "9/10", "10/10",
	"-1",
]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok := true
	ok = _check("digit padding", _padding()) and ok
	ok = _check("digit spacing", _spacing()) and ok
	ok = _check("mission counters", _missions()) and ok
	ok = _check("gameplay coins", _coins()) and ok
	ok = _check("contact sheet", _sheet()) and ok
	print("[numbers] ok=%s" % ok)
	quit(0 if ok else 1)


func _check(name: String, passed: bool) -> bool:
	if not passed:
		push_error("[numbers] FAIL %s" % name)
	else:
		print("[numbers] pass %s" % name)
	return passed


func _load(path: String) -> Image:
	var image := Image.new()
	if image.load(path) != OK:
		push_error("[numbers] unreadable %s" % path)
		return null
	return image


func _ink(image: Image) -> Rect2i:
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a < 1.0 / 255.0:
				continue
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
	if max_x < 0:
		return Rect2i()
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


func _padding() -> bool:
	var ok := true
	for prefix in ["num_white", "num_gold"]:
		var bottoms: Array[int] = []
		for digit in 10:
			var path := "res://assets/sprites/%s_%d.png" % [prefix, digit]
			var image := _load(path)
			if image == null:
				return false
			var ink := _ink(image)
			if ink.size.x < 1:
				push_error("[numbers] %s_%d is empty" % [prefix, digit])
				return false
			var left := ink.position.x
			var top := ink.position.y
			var right := image.get_width() - ink.end.x
			var bottom := image.get_height() - ink.end.y
			bottoms.append(image.get_height())
			if left < 8 or top < 8 or right < 8 or bottom < 8:
				push_error("[numbers] %s_%d padding L%d T%d R%d B%d" % [prefix, digit, left, top, right, bottom])
				ok = false
			if image.get_pixel(0, 0).a > 0.0 or image.get_pixel(image.get_width() - 1, image.get_height() - 1).a > 0.0:
				push_error("[numbers] %s_%d touches the frame" % [prefix, digit])
				ok = false
			print("[numbers] %s_%d %dx%d ink %dx%d pad %d,%d,%d,%d" % [
				prefix, digit, image.get_width(), image.get_height(), ink.size.x, ink.size.y, left, top, right, bottom,
			])
		for bottom in bottoms:
			if bottom != bottoms[0]:
				push_error("[numbers] %s heights differ" % prefix)
				ok = false
				break
	for symbol in ["alpha_slash", "alpha_hyphen", "alpha_plus", "alpha_colon"]:
		var image := _load("res://assets/sprites/%s.png" % symbol)
		if image == null:
			return false
		var ink := _ink(image)
		var left := ink.position.x
		var top := ink.position.y
		var right := image.get_width() - ink.end.x
		var bottom := image.get_height() - ink.end.y
		print("[numbers] %s %dx%d pad %d,%d,%d,%d" % [symbol, image.get_width(), image.get_height(), left, top, right, bottom])
		if left < 1 or top < 1 or right < 1 or bottom < 1:
			push_error("[numbers] %s ink touches the crop" % symbol)
			ok = false
	return ok


func _place(value: String, height: float, box: Vector2, gold: bool, fit: bool):
	var line: Control = load("res://scripts/sprite_text.gd").new()
	line.configure(value, height, box, HORIZONTAL_ALIGNMENT_CENTER, gold, fit)
	root.add_child(line)
	return line


func _glyphs_fit(line, value: String) -> bool:
	if line.get_child_count() < 1:
		push_error("[numbers] %s drew nothing" % value)
		return false
	var previous: Control = null
	for child in line.get_children():
		var glyph := child as Control
		if glyph.position.x < -0.5 or glyph.position.y < -0.5:
			push_error("[numbers] %s starts outside %s" % [value, glyph.position])
			return false
		if glyph.position.x + glyph.size.x > line.size.x + 0.5:
			push_error("[numbers] %s ends past the box %s in %s" % [value, glyph.position + glyph.size, line.size])
			return false
		if glyph.position.y + glyph.size.y > line.size.y + 0.5:
			push_error("[numbers] %s is taller than the box" % value)
			return false
		if previous != null and glyph.position.x < previous.position.x + previous.size.x - 0.5:
			push_error("[numbers] %s glyphs overlap" % value)
			return false
		previous = glyph
	return true


func _spacing() -> bool:
	var ok := true
	for value in SAMPLES:
		var line: Control = _place(value, 28.0, Vector2(420.0, 48.0), false, true)
		ok = _glyphs_fit(line, value) and ok
		line.free()
		var gold: Control = _place(value, 28.0, Vector2(420.0, 48.0), true, true)
		ok = _glyphs_fit(gold, "gold " + value) and ok
		gold.free()
	return ok


func _missions() -> bool:
	var overlay = load("res://scripts/daily_missions_overlay.gd").new()
	overlay.use_screen_board()
	root.add_child(overlay)
	overlay.present("board", true)
	overlay.show_board({
		"ok": true,
		"slots": [
			{"slot": "easy", "mission_id": 50, "description": "Enter 2 dives.", "goal": 2, "progress": 0, "reward": 5, "complete": false, "claimed": false},
			{"slot": "medium", "mission_id": 1, "description": "Pass 10 pipes.", "goal": 10, "progress": 9, "reward": 10, "complete": false, "claimed": false},
			{"slot": "hard", "mission_id": 32, "description": "Pass 200 pipes.", "goal": 200, "progress": 200, "reward": 20, "complete": true, "claimed": false},
		],
		"bonus": {"reward": 25, "unlocked": false, "claimed": false},
	}, "")
	var counters: Array = overlay.get("_counters")
	var samples: PackedStringArray = ["0/2", "1/2", "2/2", "0/10", "9/10", "10/10", "200/200"]
	var ok := counters.size() == 3
	for sample in samples:
		for counter in counters:
			var line = counter
			line.set_value(sample)
			if line.clip_contents:
				push_error("[numbers] mission counter clips %s" % sample)
				ok = false
			for child in line.get_children():
				var glyph := child as Control
				if glyph.position.x < 1.0 or glyph.position.y < 1.0:
					push_error("[numbers] mission %s glyph %s" % [sample, glyph.position])
					ok = false
					break
				if glyph.position.x + glyph.size.x > line.size.x - 1.0 or glyph.position.y + glyph.size.y > line.size.y - 1.0:
					push_error("[numbers] mission %s overflows %s in %s" % [sample, glyph.position + glyph.size, line.size])
					ok = false
					break
	overlay.free()
	return ok


func _coins() -> bool:
	var hud = load("res://scenes/game/hud.gd").new()
	root.add_child(hud)
	hud.set_coins(10000)
	var line = hud._coin_text
	var ok := line != null and _glyphs_fit(line, "10000")
	if ok:
		var right: float = line.position.x + line.size.x
		if right > RR.VIEW_W - 4.0:
			push_error("[numbers] coin box passes the screen edge %.1f" % right)
			ok = false
	hud.free()
	return ok


func _sheet() -> bool:
	var cell := 80
	var cols := 10
	var sheet := Image.create(cols * cell, 2 * cell, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.04, 0.07, 0.12, 1.0))
	for row in 2:
		var prefix := "num_gold" if row == 0 else "num_white"
		for digit in 10:
			var image := _load("res://assets/sprites/%s_%d.png" % [prefix, digit])
			if image == null:
				return false
			var scale := float(cell - 8) / float(maxi(image.get_width(), image.get_height()))
			var tw := maxi(1, int(image.get_width() * scale))
			var th := maxi(1, int(image.get_height() * scale))
			var sized := image.duplicate()
			sized.resize(tw, th, Image.INTERPOLATE_NEAREST)
			var at := Vector2i(digit * cell + (cell - tw) / 2, row * cell + (cell - th) / 2)
			sheet.blit_rect(sized, Rect2i(0, 0, tw, th), at)
	var dest := "C:/Users/civis/AppData/Local/Temp/reefrun_number_glyphs.png"
	var err := sheet.save_png(dest)
	if err != OK:
		push_error("[numbers] contact sheet save failed %s" % err)
		return false
	print("[numbers] sheet %s" % dest)
	return true
